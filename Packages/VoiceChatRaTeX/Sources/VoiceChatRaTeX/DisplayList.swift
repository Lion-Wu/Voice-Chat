import Foundation

public struct RaTeXDisplayList: Decodable, Sendable {
    public let version: Int?
    public let width: Double
    public let height: Double
    public let depth: Double
    public let items: [RaTeXDisplayItem]
}

public enum RaTeXDisplayItem: Decodable, Sendable {
    case glyphPath(RaTeXGlyphPath)
    case line(RaTeXLine)
    case rect(RaTeXRect)
    case path(RaTeXPath)
    case unknown(String)

    private enum TypeKey: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let tag = try decoder.container(keyedBy: TypeKey.self).decode(String.self, forKey: .type)
        switch tag {
        case "GlyphPath":
            self = .glyphPath(try RaTeXGlyphPath(from: decoder))
        case "Line":
            self = .line(try RaTeXLine(from: decoder))
        case "Rect":
            self = .rect(try RaTeXRect(from: decoder))
        case "Path":
            self = .path(try RaTeXPath(from: decoder))
        default:
            self = .unknown(tag)
        }
    }
}

public struct RaTeXGlyphPath: Decodable, Sendable {
    public let x: Double
    public let y: Double
    public let scale: Double
    public let font: String
    public let charCode: UInt32
    public let commands: [RaTeXPathCommand]
    public let color: RaTeXDisplayColor

    private enum CodingKeys: String, CodingKey {
        case x
        case y
        case scale
        case font
        case charCode = "char_code"
        case commands
        case color
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        scale = try container.decode(Double.self, forKey: .scale)
        font = try container.decode(String.self, forKey: .font)
        charCode = try container.decode(UInt32.self, forKey: .charCode)
        commands = try container.decodeIfPresent([RaTeXPathCommand].self, forKey: .commands) ?? []
        color = try container.decode(RaTeXDisplayColor.self, forKey: .color)
    }
}

public struct RaTeXLine: Decodable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let thickness: Double
    public let color: RaTeXDisplayColor
    public let dashed: Bool

    private enum CodingKeys: CodingKey {
        case x
        case y
        case width
        case thickness
        case color
        case dashed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        width = try container.decode(Double.self, forKey: .width)
        thickness = try container.decode(Double.self, forKey: .thickness)
        color = try container.decode(RaTeXDisplayColor.self, forKey: .color)
        dashed = try container.decodeIfPresent(Bool.self, forKey: .dashed) ?? false
    }
}

public struct RaTeXRect: Decodable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let color: RaTeXDisplayColor
}

public struct RaTeXPath: Decodable, Sendable {
    public let x: Double
    public let y: Double
    public let commands: [RaTeXPathCommand]
    public let fill: Bool
    public let color: RaTeXDisplayColor
}

public enum RaTeXPathCommand: Decodable, Sendable {
    case moveTo(x: Double, y: Double)
    case lineTo(x: Double, y: Double)
    case cubicTo(x1: Double, y1: Double, x2: Double, y2: Double, x: Double, y: Double)
    case quadTo(x1: Double, y1: Double, x: Double, y: Double)
    case close
    case unknown(String)

    private enum TypeKey: String, CodingKey {
        case type
    }

    private struct XY: Decodable {
        let x: Double
        let y: Double
    }

    private struct Cubic: Decodable {
        let x1: Double
        let y1: Double
        let x2: Double
        let y2: Double
        let x: Double
        let y: Double
    }

    private struct Quad: Decodable {
        let x1: Double
        let y1: Double
        let x: Double
        let y: Double
    }

    public init(from decoder: Decoder) throws {
        let tag = try decoder.container(keyedBy: TypeKey.self).decode(String.self, forKey: .type)
        switch tag {
        case "MoveTo":
            let data = try XY(from: decoder)
            self = .moveTo(x: data.x, y: data.y)
        case "LineTo":
            let data = try XY(from: decoder)
            self = .lineTo(x: data.x, y: data.y)
        case "CubicTo":
            let data = try Cubic(from: decoder)
            self = .cubicTo(x1: data.x1, y1: data.y1, x2: data.x2, y2: data.y2, x: data.x, y: data.y)
        case "QuadTo":
            let data = try Quad(from: decoder)
            self = .quadTo(x1: data.x1, y1: data.y1, x: data.x, y: data.y)
        case "Close":
            self = .close
        default:
            self = .unknown(tag)
        }
    }
}

public extension RaTeXDisplayList {
    var pathCommandCount: Int {
        items.reduce(0) { total, item in
            total + item.pathCommandCount
        }
    }
}

public extension RaTeXDisplayItem {
    var pathCommandCount: Int {
        switch self {
        case let .glyphPath(glyph):
            return glyph.commands.count
        case let .path(path):
            return path.commands.count
        case .line, .rect, .unknown:
            return 0
        }
    }
}

public struct RaTeXDisplayColor: Decodable, Equatable, Sendable {
    public let r: Float
    public let g: Float
    public let b: Float
    public let a: Float
}
