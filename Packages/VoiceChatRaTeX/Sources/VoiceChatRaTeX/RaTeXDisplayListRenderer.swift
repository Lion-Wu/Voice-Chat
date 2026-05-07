import CoreGraphics
import CoreText
import Foundation

public struct RaTeXDisplayListRenderer: Sendable {
    public let displayList: RaTeXDisplayList
    public let fontSize: CGFloat

    public init(displayList: RaTeXDisplayList, fontSize: CGFloat) {
        self.displayList = displayList
        self.fontSize = fontSize
    }

    public var width: CGFloat {
        CGFloat(displayList.width) * fontSize
    }

    public var height: CGFloat {
        CGFloat(displayList.height) * fontSize
    }

    public var depth: CGFloat {
        CGFloat(displayList.depth) * fontSize
    }

    public var totalHeight: CGFloat {
        height + depth
    }

    public func draw(in context: CGContext) {
        RaTeXFontLoader.ensureLoaded()
        for item in displayList.items {
            switch item {
            case let .glyphPath(glyph):
                drawGlyph(glyph, in: context)
            case let .line(line):
                drawLine(line, in: context)
            case let .rect(rect):
                drawRect(rect, in: context)
            case let .path(path):
                drawPath(path, in: context)
            case .unknown:
                break
            }
        }
    }

    private func pt(_ em: Double) -> CGFloat {
        CGFloat(em) * fontSize
    }

    private func cgColor(_ color: RaTeXDisplayColor) -> CGColor {
        CGColor(
            red: CGFloat(color.r),
            green: CGFloat(color.g),
            blue: CGFloat(color.b),
            alpha: CGFloat(color.a)
        )
    }

    private func postScriptName(for fontID: String) -> String {
        "KaTeX_\(fontID)"
    }

    private func drawGlyph(_ glyph: RaTeXGlyphPath, in context: CGContext) {
        guard let scalar = Unicode.Scalar(glyph.charCode) else { return }

        let character = String(Character(scalar))
        let font = CTFontCreateWithName(
            postScriptName(for: glyph.font) as CFString,
            pt(glyph.scale),
            nil
        )
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: cgColor(glyph.color)
        ]
        guard let attributed = CFAttributedStringCreate(nil, character as CFString, attributes as CFDictionary) else {
            return
        }
        let line = CTLineCreateWithAttributedString(attributed)

        context.saveGState()
        context.translateBy(x: pt(glyph.x), y: pt(glyph.y))
        context.textMatrix = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func drawLine(_ line: RaTeXLine, in context: CGContext) {
        context.saveGState()
        let thickness = max(0.5, pt(line.thickness))
        if line.dashed {
            context.setStrokeColor(cgColor(line.color))
            context.setLineWidth(thickness)
            context.setLineCap(.butt)
            context.setLineDash(phase: 0, lengths: [thickness * 3, thickness * 3])
            context.move(to: CGPoint(x: pt(line.x), y: pt(line.y)))
            context.addLine(to: CGPoint(x: pt(line.x) + pt(line.width), y: pt(line.y)))
            context.strokePath()
        } else {
            context.setFillColor(cgColor(line.color))
            context.fill(
                CGRect(
                    x: pt(line.x),
                    y: pt(line.y) - thickness / 2,
                    width: pt(line.width),
                    height: thickness
                )
            )
        }
        context.restoreGState()
    }

    private func drawRect(_ rect: RaTeXRect, in context: CGContext) {
        context.saveGState()
        context.setFillColor(cgColor(rect.color))
        context.fill(
            CGRect(
                x: pt(rect.x),
                y: pt(rect.y),
                width: pt(rect.width),
                height: pt(rect.height)
            )
        )
        context.restoreGState()
    }

    private func drawPath(_ path: RaTeXPath, in context: CGContext) {
        context.saveGState()
        context.addPath(makePath(from: path.commands, dx: path.x, dy: path.y))
        let color = cgColor(path.color)
        if path.fill {
            context.setFillColor(color)
            context.fillPath()
        } else {
            context.setStrokeColor(color)
            context.strokePath()
        }
        context.restoreGState()
    }

    private func makePath(from commands: [RaTeXPathCommand], dx: Double, dy: Double) -> CGPath {
        let path = CGMutablePath()
        let originX = pt(dx)
        let originY = pt(dy)
        for command in commands {
            switch command {
            case let .moveTo(x, y):
                path.move(to: CGPoint(x: originX + pt(x), y: originY + pt(y)))
            case let .lineTo(x, y):
                path.addLine(to: CGPoint(x: originX + pt(x), y: originY + pt(y)))
            case let .cubicTo(x1, y1, x2, y2, x, y):
                path.addCurve(
                    to: CGPoint(x: originX + pt(x), y: originY + pt(y)),
                    control1: CGPoint(x: originX + pt(x1), y: originY + pt(y1)),
                    control2: CGPoint(x: originX + pt(x2), y: originY + pt(y2))
                )
            case let .quadTo(x1, y1, x, y):
                path.addQuadCurve(
                    to: CGPoint(x: originX + pt(x), y: originY + pt(y)),
                    control: CGPoint(x: originX + pt(x1), y: originY + pt(y1))
                )
            case .close:
                path.closeSubpath()
            case .unknown:
                break
            }
        }
        return path
    }
}
