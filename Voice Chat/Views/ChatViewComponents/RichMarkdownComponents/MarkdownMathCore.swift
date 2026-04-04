//
//  MarkdownMathCore.swift
//  Voice Chat
//

@preconcurrency import Foundation

#if os(iOS) || os(tvOS) || os(watchOS)
@preconcurrency import UIKit
#elseif os(macOS)
@preconcurrency import AppKit
#endif

struct MarkdownMathStyle: @unchecked Sendable, Equatable {
    let baseFont: MarkdownPlatformFont
    let textColor: MarkdownPlatformColor
    let displayPadding: CGSize
    let inlinePadding: CGSize
    let minimumInlineScale: CGFloat
    let minimumDisplayScale: CGFloat

    init(baseFont: MarkdownPlatformFont, textColor: MarkdownPlatformColor) {
        self.baseFont = baseFont
        self.textColor = textColor
        self.displayPadding = CGSize(width: max(6, baseFont.pointSize * 0.45), height: max(6, baseFont.pointSize * 0.3))
        self.inlinePadding = CGSize(width: max(1, baseFont.pointSize * 0.08), height: max(1, baseFont.pointSize * 0.02))
        self.minimumInlineScale = 0.58
        self.minimumDisplayScale = 0.52
    }

    static func == (lhs: MarkdownMathStyle, rhs: MarkdownMathStyle) -> Bool {
        mathFontsEqual(lhs.baseFont, rhs.baseFont) &&
        mathColorsEqual(lhs.textColor, rhs.textColor) &&
        abs(lhs.displayPadding.width - rhs.displayPadding.width) <= 0.01 &&
        abs(lhs.displayPadding.height - rhs.displayPadding.height) <= 0.01 &&
        abs(lhs.inlinePadding.width - rhs.inlinePadding.width) <= 0.01 &&
        abs(lhs.inlinePadding.height - rhs.inlinePadding.height) <= 0.01
    }

    var inlineMathAxisOffset: CGFloat {
        measuredRelationCenterOffset(for: baseFont)
    }
}

final class MarkdownMathRenderNode: @unchecked Sendable {
    let size: CGSize
    let baseline: CGFloat
    let alignmentAxis: CGFloat
    private let drawer: (CGContext, CGPoint) -> Void

    init(
        size: CGSize,
        baseline: CGFloat,
        alignmentAxis: CGFloat? = nil,
        drawer: @escaping (CGContext, CGPoint) -> Void
    ) {
        self.size = CGSize(width: ceil(max(0, size.width)), height: ceil(max(0, size.height)))
        self.baseline = max(0, baseline)
        self.alignmentAxis = min(self.size.height, max(0, alignmentAxis ?? baseline))
        self.drawer = drawer
    }

    func draw(at origin: CGPoint, in context: CGContext) {
        drawer(context, origin)
    }

    static func empty(width: CGFloat = 0) -> MarkdownMathRenderNode {
        MarkdownMathRenderNode(size: CGSize(width: width, height: 0), baseline: 0, alignmentAxis: 0) { _, _ in }
    }
}

struct MarkdownMathRenderOutput: @unchecked Sendable {
    let node: MarkdownMathRenderNode
    let displayMode: Bool
    let style: MarkdownMathStyle

    var padding: CGSize {
        displayMode ? style.displayPadding : style.inlinePadding
    }

    var idealSize: CGSize {
        CGSize(
            width: ceil(node.size.width + padding.width * 2),
            height: ceil(node.size.height + padding.height * 2)
        )
    }

    func scaleToFit(availableWidth: CGFloat) -> CGFloat {
        let contentWidth = max(1, node.size.width)
        let usableWidth = max(1, availableWidth - padding.width * 2)
        return min(1, usableWidth / contentWidth)
    }

    func measuredSize(availableWidth: CGFloat) -> CGSize {
        let scale = scaleToFit(availableWidth: availableWidth)
        let width = min(
            max(1, availableWidth),
            ceil(node.size.width * scale + padding.width * 2)
        )
        let height = ceil(node.size.height * scale + padding.height * 2)
        return CGSize(width: width, height: height)
    }

    func attachmentBounds(availableWidth: CGFloat) -> CGRect {
        let scale = scaleToFit(availableWidth: availableWidth)
        let measured = measuredSize(availableWidth: availableWidth)
        let yOffset: CGFloat
        if displayMode {
            yOffset = 0
        } else {
            let scaledHeight = node.size.height * scale
            let contentY = max(padding.height, (measured.height - scaledHeight) / 2)
            let mathAxis = contentY + node.alignmentAxis * scale
            let surroundingAxis = style.baseFont.ascender - style.inlineMathAxisOffset
            yOffset = surroundingAxis - mathAxis
        }
        return CGRect(x: 0, y: floor(yOffset), width: measured.width, height: measured.height)
    }

    func draw(in context: CGContext, bounds: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = scaleToFit(availableWidth: bounds.width)
        let scaledWidth = node.size.width * scale
        let scaledHeight = node.size.height * scale
        let contentX: CGFloat
        if displayMode {
            contentX = max(padding.width, (bounds.width - scaledWidth) / 2)
        } else {
            contentX = padding.width
        }
        let contentY = max(padding.height, (bounds.height - scaledHeight) / 2)

        context.saveGState()
        context.translateBy(x: bounds.minX + contentX, y: bounds.minY + contentY)
        context.scaleBy(x: scale, y: scale)
        node.draw(at: .zero, in: context)
        context.restoreGState()
    }
}

enum MarkdownMathTypesetter {
    static func render(
        latex: String,
        displayMode: Bool,
        style: MarkdownMathStyle
    ) -> MarkdownMathRenderOutput {
        var parser = MarkdownMathParser(source: latex)
        let expression = parser.parse()
        let fontSize = style.baseFont.pointSize * (displayMode ? 1.16 : 1.0)
        let context = MarkdownMathLayoutContext(
            style: style,
            fontSize: fontSize,
            displayMode: displayMode,
            fontOverride: nil,
            textMode: false
        )
        let node = layout(expression, context: context)
        return MarkdownMathRenderOutput(node: node, displayMode: displayMode, style: style)
    }
}

private enum MarkdownMathFontOverride: Sendable {
    case roman
    case bold
    case italic
    case boldItalic
    case sansSerif
    case monospaced
    case text
}

private struct MarkdownMathLayoutContext: @unchecked Sendable {
    let style: MarkdownMathStyle
    let fontSize: CGFloat
    let displayMode: Bool
    let fontOverride: MarkdownMathFontOverride?
    let textMode: Bool

    func child(fontScale: CGFloat, displayMode: Bool? = nil) -> MarkdownMathLayoutContext {
        MarkdownMathLayoutContext(
            style: style,
            fontSize: max(7, self.fontSize * fontScale),
            displayMode: displayMode ?? self.displayMode,
            fontOverride: fontOverride,
            textMode: textMode
        )
    }

    func overriding(_ override: MarkdownMathFontOverride?) -> MarkdownMathLayoutContext {
        MarkdownMathLayoutContext(
            style: style,
            fontSize: fontSize,
            displayMode: displayMode,
            fontOverride: override,
            textMode: override == .text
        )
    }

    var ruleThickness: CGFloat {
        max(1, fontSize * 0.045)
    }

    var fractionRuleThickness: CGFloat {
        max(0.74, fontSize * 0.038)
    }

    var delimiterStrokeThickness: CGFloat {
        max(0.78, fontSize * 0.039)
    }

    var radicalStrokeThickness: CGFloat {
        max(0.82, fontSize * 0.041)
    }

    var mathAxisOffset: CGFloat {
        measuredRelationCenterOffset(for: mathSerifFont(size: fontSize, override: .roman))
    }
}

private enum MarkdownMathRunKind: Sendable {
    case variable
    case number
    case symbol
    case operatorName
    case largeOperator
    case integralOperator
    case limitOperator
    case text
}

private struct MarkdownMathRun: Sendable {
    let text: String
    let kind: MarkdownMathRunKind
}

private enum MarkdownMathDelimiter: Sendable, Equatable {
    case none
    case glyph(String)
    case singleBar
    case doubleBar
}

private enum MarkdownMathAccent: Sendable {
    case hat
    case tilde
    case bar
    case vec
    case leftVec
    case doubleVec
    case dot
    case ddot
}

private enum MarkdownMathLineDecoration: Sendable {
    case overline
    case underline
}

private enum MarkdownMathBracePosition: Sendable {
    case over
    case under
}

private enum MarkdownMathColumnAlignment: Sendable {
    case left
    case center
    case right
}

private enum MarkdownMathTableLayoutMode: Sendable {
    case standard
    case multline
}

private struct MarkdownMathTableDescriptor: Sendable {
    let rows: [[MarkdownMathExpression]]
    let alignments: [MarkdownMathColumnAlignment]
    let verticalRules: Set<Int>
    let horizontalRules: Set<Int>
    let leftDelimiter: MarkdownMathDelimiter
    let rightDelimiter: MarkdownMathDelimiter
    let compact: Bool
    let layoutMode: MarkdownMathTableLayoutMode
}

private indirect enum MarkdownMathExpression: Sendable {
    case sequence([MarkdownMathExpression])
    case run(MarkdownMathRun)
    case space(CGFloat)
    case fraction(numerator: MarkdownMathExpression, denominator: MarkdownMathExpression, hasRule: Bool)
    case root(index: MarkdownMathExpression?, radicand: MarkdownMathExpression)
    case scripts(base: MarkdownMathExpression, superscript: MarkdownMathExpression?, subscriptExpression: MarkdownMathExpression?)
    case scriptPlacement(base: MarkdownMathExpression, overUnder: Bool)
    case stack(base: MarkdownMathExpression, over: MarkdownMathExpression?, under: MarkdownMathExpression?)
    case delimited(left: MarkdownMathDelimiter, content: MarkdownMathExpression, right: MarkdownMathDelimiter)
    case accent(MarkdownMathAccent, MarkdownMathExpression)
    case line(MarkdownMathLineDecoration, MarkdownMathExpression)
    case boxed(MarkdownMathExpression)
    case brace(MarkdownMathBracePosition, MarkdownMathExpression)
    case table(MarkdownMathTableDescriptor)
    case displayStyle(MarkdownMathExpression)
    case textStyle(MarkdownMathExpression)
    case styled(MarkdownMathFontOverride, MarkdownMathExpression)

    var prefersLimitPlacement: Bool {
        switch self {
        case let .run(run):
            return run.kind == .largeOperator || run.kind == .limitOperator
        case let .scriptPlacement(base, _):
            return base.prefersLimitPlacement
        case let .styled(_, expression):
            return expression.prefersLimitPlacement
        case let .boxed(expression):
            return expression.prefersLimitPlacement
        case let .brace(_, expression):
            return expression.prefersLimitPlacement
        default:
            return false
        }
    }

    var forcedLimitPlacement: Bool? {
        switch self {
        case let .scriptPlacement(_, overUnder):
            return overUnder
        case let .styled(_, expression):
            return expression.forcedLimitPlacement
        case let .boxed(expression):
            return expression.forcedLimitPlacement
        case let .brace(_, expression):
            return expression.forcedLimitPlacement
        default:
            return nil
        }
    }
}

private struct MarkdownMathParser {
    private let characters: [Character]
    private var index: Int = 0

    init(source: String) {
        characters = Array(source)
    }

    mutating func parse() -> MarkdownMathExpression {
        let expression = parseSequence(stoppingAt: .none)
        return simplify(expression)
    }

    private enum StopCondition {
        case none
        case closingBrace
        case rightDelimiter
        case tableCell
        case tableRowOrEnd(environment: String)
    }

    private mutating func parseSequence(stoppingAt stop: StopCondition) -> MarkdownMathExpression {
        var parts: [MarkdownMathExpression] = []

        while index < characters.count {
            if shouldStop(for: stop) {
                break
            }

            if consumeLimitPlacementModifierIfNeeded(in: &parts) {
                continue
            }

            if let chooseExpression = parseInfixChooseIfNeeded(leftParts: parts, stoppingAt: stop) {
                return simplify(chooseExpression)
            }

            if let whitespace = parseWhitespace() {
                parts.append(whitespace)
                continue
            }

            if let commandExpression = parseCommandOrEscape(stoppingAt: stop) {
                parts.append(commandExpression)
                continue
            }

            let current = characters[index]
            if current == "{" {
                index += 1
                let content = parseSequence(stoppingAt: .closingBrace)
                if index < characters.count, characters[index] == "}" {
                    index += 1
                }
                parts.append(applyScriptsIfNeeded(to: content))
                continue
            }

            if current == "^" || current == "_" {
                parts.append(.run(MarkdownMathRun(text: String(current), kind: .symbol)))
                index += 1
                continue
            }

            parts.append(applyScriptsIfNeeded(to: parsePlainRun()))
        }

        return simplify(.sequence(parts))
    }

    private mutating func parseInfixChooseIfNeeded(
        leftParts: [MarkdownMathExpression],
        stoppingAt stop: StopCondition
    ) -> MarkdownMathExpression? {
        guard lookaheadCommand("choose") else { return nil }
        guard leftParts.contains(where: {
            if case .space = $0 { return false }
            return true
        }) else {
            return nil
        }

        index += "\\choose".count

        let trimmedLeftParts = leftParts.reversed().drop(while: {
            if case .space = $0 { return true }
            return false
        }).reversed()
        let numerator = simplify(.sequence(Array(trimmedLeftParts)))
        let denominator = parseSequence(stoppingAt: stop)
        let stacked = MarkdownMathExpression.fraction(
            numerator: numerator,
            denominator: denominator,
            hasRule: false
        )
        return .delimited(left: .glyph("("), content: stacked, right: .glyph(")"))
    }

    private mutating func consumeLimitPlacementModifierIfNeeded(
        in parts: inout [MarkdownMathExpression]
    ) -> Bool {
        guard index < characters.count, characters[index] == "\\" else { return false }
        let savedIndex = index
        index += 1
        let command = parseCommandName()
        let overUnder: Bool
        switch command {
        case "limits":
            overUnder = true
        case "nolimits":
            overUnder = false
        default:
            index = savedIndex
            return false
        }

        for position in parts.indices.reversed() {
            switch parts[position] {
            case .space:
                continue
            default:
                parts[position] = .scriptPlacement(base: parts[position], overUnder: overUnder)
                return true
            }
        }

        return true
    }

    private mutating func parseWhitespace() -> MarkdownMathExpression? {
        guard index < characters.count else { return nil }
        guard characters[index].isWhitespace else { return nil }

        var count = 0
        while index < characters.count, characters[index].isWhitespace {
            count += characters[index] == "\t" ? 2 : 1
            index += 1
        }

        return .space(CGFloat(count) * 0.24)
    }

    private mutating func parseCommandOrEscape(stoppingAt stop: StopCondition) -> MarkdownMathExpression? {
        guard index < characters.count, characters[index] == "\\" else { return nil }

        if index + 1 < characters.count, characters[index + 1] == "\\" {
            if case .tableRowOrEnd = stop {
                return nil
            }
            index += 2
            return .space(0.42)
        }

        index += 1
        guard index < characters.count else {
            return .run(MarkdownMathRun(text: "\\", kind: .symbol))
        }

        if !characters[index].isLetter {
            let escaped = characters[index]
            index += 1
            return applyScriptsIfNeeded(to: parseEscapedSymbol(escaped))
        }

        let command = parseCommandName()
        return applyScriptsIfNeeded(to: parseCommand(command, stoppingAt: stop))
    }

    private mutating func parseCommandName() -> String {
        let start = index
        while index < characters.count, characters[index].isLetter {
            index += 1
        }
        return String(characters[start..<index])
    }

    private mutating func parseCommand(
        _ command: String,
        stoppingAt stop: StopCondition
    ) -> MarkdownMathExpression {
        if let mapped = MarkdownMathCommandMap.symbol(command) {
            return .run(mapped)
        }
        if let operatorName = MarkdownMathCommandMap.operatorName(command) {
            return .run(operatorName)
        }
        if let spaceWidth = MarkdownMathCommandMap.space(command) {
            return .space(spaceWidth)
        }

        switch command {
        case "frac", "dfrac", "tfrac":
            let numerator = parseRequiredArgument()
            let denominator = parseRequiredArgument()
            return .fraction(numerator: numerator, denominator: denominator, hasRule: true)

        case "binom", "dbinom", "tbinom":
            let numerator = parseRequiredArgument()
            let denominator = parseRequiredArgument()
            let stacked = MarkdownMathExpression.fraction(numerator: numerator, denominator: denominator, hasRule: false)
            return .delimited(left: .glyph("("), content: stacked, right: .glyph(")"))

        case "sqrt":
            let indexExpression = parseOptionalBracketArgument()
            let radicand = parseRequiredArgument()
            return .root(index: indexExpression, radicand: radicand)

        case "xrightarrow", "xleftarrow", "xRightarrow", "xLeftarrow", "xleftrightarrow", "xLeftrightarrow":
            return parseExtensibleArrow(named: command)

        case "overset", "stackrel":
            let annotation = parseRequiredArgument()
            let base = parseRequiredArgument()
            return .stack(base: base, over: annotation, under: nil)

        case "underset":
            let annotation = parseRequiredArgument()
            let base = parseRequiredArgument()
            return .stack(base: base, over: nil, under: annotation)

        case "left":
            let leftDelimiter = parseDelimiterToken()
            let content = parseSequence(stoppingAt: .rightDelimiter)
            if lookaheadCommand("right") {
                _ = consumeCommand("right")
            }
            let rightDelimiter = parseDelimiterToken()
            return .delimited(left: leftDelimiter, content: content, right: rightDelimiter)

        case "right":
            return .run(MarkdownMathRun(text: "", kind: .symbol))

        case "text":
            return .run(MarkdownMathRun(text: parseTextArgument(), kind: .text))

        case "textcolor":
            _ = parseGroupText()
            return parseRequiredArgument()

        case "colon":
            return .run(MarkdownMathRun(text: ":", kind: .symbol))

        case "mathrm":
            return .styled(.roman, parseRequiredArgument())

        case "mathbf":
            return .styled(.bold, parseRequiredArgument())

        case "mathit":
            return .styled(.italic, parseRequiredArgument())

        case "mathsf":
            return .styled(.sansSerif, parseRequiredArgument())

        case "mathtt":
            return .styled(.monospaced, parseRequiredArgument())

        case "operatorname":
            if index < characters.count, characters[index] == "*" {
                index += 1
                return .run(MarkdownMathRun(text: parseTextArgument(), kind: .limitOperator))
            }
            return .run(MarkdownMathRun(text: parseTextArgument(), kind: .operatorName))

        case "mathbb":
            return parseMathBlackboard()

        case "mathcal":
            return parseMathCalligraphic()

        case "mathfrak":
            return parseMathFraktur()

        case "overline":
            return .line(.overline, parseRequiredArgument())

        case "underline":
            return .line(.underline, parseRequiredArgument())

        case "boxed", "fbox":
            return .boxed(parseRequiredArgument())

        case "bar":
            return .accent(.bar, parseRequiredArgument())

        case "hat", "widehat":
            return .accent(.hat, parseRequiredArgument())

        case "tilde", "widetilde":
            return .accent(.tilde, parseRequiredArgument())

        case "vec":
            return .accent(.vec, parseRequiredArgument())

        case "overrightarrow":
            return .accent(.vec, parseRequiredArgument())

        case "overleftarrow":
            return .accent(.leftVec, parseRequiredArgument())

        case "overleftrightarrow":
            return .accent(.doubleVec, parseRequiredArgument())

        case "dot":
            return .accent(.dot, parseRequiredArgument())

        case "ddot":
            return .accent(.ddot, parseRequiredArgument())

        case "overbrace":
            return parseBraceCommand(position: .over)

        case "underbrace":
            return parseBraceCommand(position: .under)

        case "begin":
            return parseEnvironment()

        case "substack":
            return parseSubstack()

        case "displaystyle":
            return .displayStyle(parseSequence(stoppingAt: stop))

        case "textstyle":
            return .textStyle(parseSequence(stoppingAt: stop))

        case "boldsymbol":
            return .styled(.boldItalic, parseRequiredArgument())

        case "mod":
            return parseModCommand(parenthesized: false, binary: false)

        case "bmod":
            return parseModCommand(parenthesized: false, binary: true)

        case "pmod":
            return parseModCommand(parenthesized: true, binary: false)

        case "big", "Big", "bigg", "Bigg", "bigl", "bigr", "bigm", "Bigl", "Bigr", "Bigm", "biggl", "biggr", "biggm", "Biggl", "Biggr", "Biggm":
            return expression(forSizedDelimiter: parseDelimiterToken())

        case "middle":
            return expression(forSizedDelimiter: parseDelimiterToken())

        case "limits", "nolimits":
            return .run(MarkdownMathRun(text: "", kind: .symbol))

        default:
            return .run(MarkdownMathRun(text: "\\\(command)", kind: .text))
        }
    }

    private mutating func parseEnvironment() -> MarkdownMathExpression {
        let name = parseGroupText()
        guard !name.isEmpty else {
            return .run(MarkdownMathRun(text: "\\begin{}", kind: .text))
        }

        let descriptor = parseTableDescriptor(named: name)
        return .table(descriptor)
    }

    private mutating func parseExtensibleArrow(named command: String) -> MarkdownMathExpression {
        let under = parseOptionalBracketArgument()
        let over = parseRequiredArgument()
        let arrowText: String
        switch command {
        case "xleftarrow":
            arrowText = "←"
        case "xRightarrow":
            arrowText = "⇒"
        case "xLeftarrow":
            arrowText = "⇐"
        case "xleftrightarrow":
            arrowText = "↔"
        case "xLeftrightarrow":
            arrowText = "⇔"
        default:
            arrowText = "→"
        }
        let base = MarkdownMathExpression.run(MarkdownMathRun(text: arrowText, kind: .symbol))
        return .stack(base: base, over: over, under: under)
    }

    private mutating func parseBraceCommand(position: MarkdownMathBracePosition) -> MarkdownMathExpression {
        let base = MarkdownMathExpression.brace(position, parseRequiredArgument())
        var over: MarkdownMathExpression?
        var under: MarkdownMathExpression?

        while index < characters.count {
            let marker = characters[index]
            guard marker == "^" || marker == "_" else { break }
            index += 1
            let argument = parseRequiredArgument()
            if marker == "^" {
                over = argument
            } else {
                under = argument
            }
        }

        if over != nil || under != nil {
            return .stack(base: base, over: over, under: under)
        }
        return base
    }

    private mutating func parseSubstack() -> MarkdownMathExpression {
        let raw = parseGroupText()
        guard !raw.isEmpty else {
            return .run(MarkdownMathRun(text: "", kind: .text))
        }

        let rowSources = splitSubstackRows(from: raw)
        let rows = rowSources.map { row in
            var parser = MarkdownMathParser(source: row)
            return [parser.parse()]
        }
        return .table(
            MarkdownMathTableDescriptor(
                rows: rows,
                alignments: [.center],
                verticalRules: [],
                horizontalRules: [],
                leftDelimiter: .none,
                rightDelimiter: .none,
                compact: true,
                layoutMode: .standard
            )
        )
    }

    private func splitSubstackRows(from raw: String) -> [String] {
        var rows: [String] = []
        var current = ""
        let chars = Array(raw)
        var cursor = 0

        while cursor < chars.count {
            if chars[cursor] == "\\", cursor + 1 < chars.count, chars[cursor + 1] == "\\" {
                rows.append(current)
                current = ""
                cursor += 2
                continue
            }
            current.append(chars[cursor])
            cursor += 1
        }

        rows.append(current)
        return rows.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private mutating func parseMathBlackboard() -> MarkdownMathExpression {
        let rawText = parseGroupText()
        guard !rawText.isEmpty else {
            return .run(MarkdownMathRun(text: "", kind: .text))
        }

        if let mapped = rawText.unicodeScalars.count == 1 ? blackboardBoldCharacter(for: rawText) : nil {
            return .run(MarkdownMathRun(text: mapped, kind: .text))
        }

        return .styled(.bold, .run(MarkdownMathRun(text: rawText, kind: .text)))
    }

    private mutating func parseMathCalligraphic() -> MarkdownMathExpression {
        let rawText = parseGroupText()
        guard !rawText.isEmpty else {
            return .run(MarkdownMathRun(text: "", kind: .text))
        }

        if let mapped = rawText.unicodeScalars.count == 1 ? calligraphicCharacter(for: rawText) : nil {
            return .run(MarkdownMathRun(text: mapped, kind: .text))
        }

        return .styled(.italic, .run(MarkdownMathRun(text: rawText, kind: .text)))
    }

    private mutating func parseMathFraktur() -> MarkdownMathExpression {
        let rawText = parseGroupText()
        guard !rawText.isEmpty else {
            return .run(MarkdownMathRun(text: "", kind: .text))
        }

        if let mapped = rawText.unicodeScalars.count == 1 ? frakturCharacter(for: rawText) : nil {
            return .run(MarkdownMathRun(text: mapped, kind: .text))
        }

        return .styled(.bold, .run(MarkdownMathRun(text: rawText, kind: .text)))
    }

    private mutating func parseModCommand(parenthesized: Bool, binary: Bool) -> MarkdownMathExpression {
        let argument = parseRequiredArgument()
        var parts: [MarkdownMathExpression] = [.space(binary ? 0.36 : 0.30)]

        if parenthesized {
            parts.append(.run(MarkdownMathRun(text: "(", kind: .symbol)))
        }

        parts.append(.run(MarkdownMathRun(text: "mod", kind: .operatorName)))
        parts.append(.space(0.18))
        parts.append(argument)

        if parenthesized {
            parts.append(.run(MarkdownMathRun(text: ")", kind: .symbol)))
        }

        return simplify(.sequence(parts))
    }

    private func blackboardBoldCharacter(for rawText: String) -> String? {
        switch rawText {
        case "C": return "ℂ"
        case "E": return "𝔼"
        case "H": return "ℍ"
        case "N": return "ℕ"
        case "P": return "ℙ"
        case "Q": return "ℚ"
        case "R": return "ℝ"
        case "Z": return "ℤ"
        default: return nil
        }
    }

    private func calligraphicCharacter(for rawText: String) -> String? {
        switch rawText {
        case "A": return "𝒜"
        case "B": return "ℬ"
        case "C": return "𝒞"
        case "D": return "𝒟"
        case "E": return "ℰ"
        case "F": return "ℱ"
        case "G": return "𝒢"
        case "H": return "ℋ"
        case "I": return "ℐ"
        case "J": return "𝒥"
        case "K": return "𝒦"
        case "L": return "ℒ"
        case "M": return "ℳ"
        case "N": return "𝒩"
        case "O": return "𝒪"
        case "P": return "𝒫"
        case "Q": return "𝒬"
        case "R": return "ℛ"
        case "S": return "𝒮"
        case "T": return "𝒯"
        case "U": return "𝒰"
        case "V": return "𝒱"
        case "W": return "𝒲"
        case "X": return "𝒳"
        case "Y": return "𝒴"
        case "Z": return "𝒵"
        default: return nil
        }
    }

    private func frakturCharacter(for rawText: String) -> String? {
        switch rawText {
        case "A": return "𝔄"
        case "B": return "𝔅"
        case "C": return "ℭ"
        case "D": return "𝔇"
        case "E": return "𝔈"
        case "F": return "𝔉"
        case "G": return "𝔊"
        case "H": return "ℌ"
        case "I": return "ℑ"
        case "J": return "𝔍"
        case "K": return "𝔎"
        case "L": return "𝔏"
        case "M": return "𝔐"
        case "N": return "𝔑"
        case "O": return "𝔒"
        case "P": return "𝔓"
        case "Q": return "𝔔"
        case "R": return "ℜ"
        case "S": return "𝔖"
        case "T": return "𝔗"
        case "U": return "𝔘"
        case "V": return "𝔙"
        case "W": return "𝔚"
        case "X": return "𝔛"
        case "Y": return "𝔜"
        case "Z": return "ℨ"
        case "a": return "𝔞"
        case "b": return "𝔟"
        case "c": return "𝔠"
        case "d": return "𝔡"
        case "e": return "𝔢"
        case "f": return "𝔣"
        case "g": return "𝔤"
        case "h": return "𝔥"
        case "i": return "𝔦"
        case "j": return "𝔧"
        case "k": return "𝔨"
        case "l": return "𝔩"
        case "m": return "𝔪"
        case "n": return "𝔫"
        case "o": return "𝔬"
        case "p": return "𝔭"
        case "q": return "𝔮"
        case "r": return "𝔯"
        case "s": return "𝔰"
        case "t": return "𝔱"
        case "u": return "𝔲"
        case "v": return "𝔳"
        case "w": return "𝔴"
        case "x": return "𝔵"
        case "y": return "𝔶"
        case "z": return "𝔷"
        default: return nil
        }
    }

    private func expression(forSizedDelimiter delimiter: MarkdownMathDelimiter) -> MarkdownMathExpression {
        switch delimiter {
        case .none:
            return .run(MarkdownMathRun(text: "", kind: .symbol))
        case .singleBar:
            return .run(MarkdownMathRun(text: "|", kind: .symbol))
        case .doubleBar:
            return .run(MarkdownMathRun(text: "‖", kind: .symbol))
        case let .glyph(text):
            return .run(MarkdownMathRun(text: text, kind: .symbol))
        }
    }

    private mutating func parseTableDescriptor(named name: String) -> MarkdownMathTableDescriptor {
        let compact = name == "smallmatrix" || name == "subarray"
        let layoutMode: MarkdownMathTableLayoutMode = {
            switch name {
            case "multline", "multline*":
                return .multline
            default:
                return .standard
            }
        }()
        let alignmentSpec: [MarkdownMathColumnAlignment]
        let verticalRules: Set<Int>
        if name == "array" || name == "subarray" {
            let raw = parseGroupText()
            let parsed = parseArrayAlignmentSpec(raw)
            alignmentSpec = parsed.alignments
            verticalRules = parsed.verticalRules
        } else if name == "alignedat" || name == "alignedat*" || name == "alignat" || name == "alignat*" {
            let columnPairCount = Int(parseGroupText().trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            alignmentSpec = Array(
                repeating: [MarkdownMathColumnAlignment.right, .left],
                count: max(0, columnPairCount)
            )
            .flatMap { $0 }
            verticalRules = []
        } else {
            alignmentSpec = []
            verticalRules = []
        }

        var rows: [[MarkdownMathExpression]] = []
        var currentRow: [MarkdownMathExpression] = []
        var currentCellParts: [MarkdownMathExpression] = []
        var horizontalRules: Set<Int> = []

        while index < characters.count {
            if currentCellParts.isEmpty {
                while index < characters.count, characters[index].isWhitespace {
                    index += 1
                }
            }

            if lookaheadEnvironmentEnd(name) {
                _ = consumeEnvironmentEnd(name)
                if !currentCellParts.isEmpty || !currentRow.isEmpty {
                    currentRow.append(simplify(.sequence(currentCellParts)))
                    rows.append(currentRow)
                }
                break
            }

            if lookaheadCommand("hline") || lookaheadCommand("cline") {
                if lookaheadCommand("hline") {
                    _ = consumeCommand("hline")
                } else {
                    _ = consumeCommand("cline")
                    _ = parseRequiredArgument()
                }

                if !currentCellParts.isEmpty {
                    currentRow.append(simplify(.sequence(currentCellParts)))
                    currentCellParts = []
                }
                if !currentRow.isEmpty {
                    rows.append(currentRow)
                    currentRow = []
                }
                horizontalRules.insert(rows.count)
                continue
            }

            if lookaheadTableRowBreak() {
                index += 2
                currentRow.append(simplify(.sequence(currentCellParts)))
                rows.append(currentRow)
                currentRow = []
                currentCellParts = []
                continue
            }

            if characters[index] == "&" {
                index += 1
                currentRow.append(simplify(.sequence(currentCellParts)))
                currentCellParts = []
                continue
            }

            let cellPart = parseSequence(stoppingAt: .tableRowOrEnd(environment: name))
            currentCellParts.append(cellPart)
        }

        if rows.isEmpty {
            currentRow.append(simplify(.sequence(currentCellParts)))
            rows.append(currentRow)
        }

        let columnCount = rows.map(\.count).max() ?? 0
        let alignments: [MarkdownMathColumnAlignment]
        if !alignmentSpec.isEmpty {
            alignments = resolvedAlignments(
                base: alignmentSpec,
                fallbackPattern: [.right, .left],
                columnCount: columnCount
            )
        } else if name == "cases" {
            alignments = resolvedAlignments(
                base: [.left, .left],
                fallbackPattern: [.left],
                columnCount: columnCount
            )
        } else if name == "aligned" || name == "align" || name == "align*" || name == "split" {
            alignments = resolvedAlignments(
                base: [.right, .left],
                fallbackPattern: [.right, .left],
                columnCount: columnCount
            )
        } else if name == "gather" || name == "gather*" || name == "gathered" {
            alignments = resolvedAlignments(
                base: [.center],
                fallbackPattern: [.center],
                columnCount: columnCount
            )
        } else {
            alignments = []
        }

        let leftDelimiter: MarkdownMathDelimiter
        let rightDelimiter: MarkdownMathDelimiter
        switch name {
        case "pmatrix":
            leftDelimiter = .glyph("(")
            rightDelimiter = .glyph(")")
        case "bmatrix":
            leftDelimiter = .glyph("[")
            rightDelimiter = .glyph("]")
        case "Bmatrix":
            leftDelimiter = .glyph("{")
            rightDelimiter = .glyph("}")
        case "vmatrix":
            leftDelimiter = .singleBar
            rightDelimiter = .singleBar
        case "Vmatrix":
            leftDelimiter = .doubleBar
            rightDelimiter = .doubleBar
        case "cases":
            leftDelimiter = .glyph("{")
            rightDelimiter = .none
        default:
            leftDelimiter = .none
            rightDelimiter = .none
        }

        return MarkdownMathTableDescriptor(
            rows: rows,
            alignments: alignments,
            verticalRules: verticalRules,
            horizontalRules: horizontalRules,
            leftDelimiter: leftDelimiter,
            rightDelimiter: rightDelimiter,
            compact: compact,
            layoutMode: layoutMode
        )
    }

    private func resolvedAlignments(
        base: [MarkdownMathColumnAlignment],
        fallbackPattern: [MarkdownMathColumnAlignment],
        columnCount: Int
    ) -> [MarkdownMathColumnAlignment] {
        guard columnCount > 0 else { return base }
        guard !base.isEmpty else { return [] }
        guard base.count < columnCount, !fallbackPattern.isEmpty else {
            return Array(base.prefix(columnCount))
        }

        var resolved = base
        var patternIndex = 0
        while resolved.count < columnCount {
            resolved.append(fallbackPattern[patternIndex % fallbackPattern.count])
            patternIndex += 1
        }
        return resolved
    }

    private func parseArrayAlignmentSpec(
        _ raw: String
    ) -> (alignments: [MarkdownMathColumnAlignment], verticalRules: Set<Int>) {
        var alignments: [MarkdownMathColumnAlignment] = []
        var verticalRules: Set<Int> = []

        for character in raw {
            switch character {
            case "l":
                alignments.append(.left)
            case "c":
                alignments.append(.center)
            case "r":
                alignments.append(.right)
            case "|":
                verticalRules.insert(alignments.count)
            default:
                continue
            }
        }

        return (alignments, verticalRules)
    }

    private func lookaheadEnvironmentEnd(_ name: String) -> Bool {
        guard lookaheadCommand("end") else { return false }
        var cursor = index + 4
        guard cursor < characters.count, characters[cursor] == "{" else { return false }
        cursor += 1
        let nameStart = cursor
        while cursor < characters.count, characters[cursor] != "}" {
            cursor += 1
        }
        guard cursor < characters.count else { return false }
        let candidate = String(characters[nameStart..<cursor])
        return candidate == name
    }

    private mutating func consumeEnvironmentEnd(_ name: String) -> Bool {
        guard lookaheadEnvironmentEnd(name) else { return false }
        index += 4
        _ = parseGroupText()
        return true
    }

    private func lookaheadTableRowBreak() -> Bool {
        index + 1 < characters.count && characters[index] == "\\" && characters[index + 1] == "\\"
    }

    private func shouldStop(for stop: StopCondition) -> Bool {
        switch stop {
        case .none:
            return false
        case .closingBrace:
            return characters[index] == "}"
        case .rightDelimiter:
            return lookaheadCommand("right")
        case .tableCell:
            return characters[index] == "&"
        case let .tableRowOrEnd(environment):
            return characters[index] == "&" || lookaheadTableRowBreak() || lookaheadEnvironmentEnd(environment)
        }
    }

    private func lookaheadCommand(_ command: String) -> Bool {
        let sequence = Array("\\\(command)")
        guard index + sequence.count <= characters.count else { return false }
        for offset in sequence.indices where characters[index + offset] != sequence[offset] {
            return false
        }
        return true
    }

    private mutating func consumeCommand(_ command: String) -> Bool {
        guard lookaheadCommand(command) else { return false }
        index += command.count + 1
        return true
    }

    private mutating func parseRequiredArgument() -> MarkdownMathExpression {
        guard index < characters.count else {
            return .run(MarkdownMathRun(text: "", kind: .symbol))
        }

        if characters[index] == "{" {
            index += 1
            let content = parseSequence(stoppingAt: .closingBrace)
            if index < characters.count, characters[index] == "}" {
                index += 1
            }
            return simplify(content)
        }

        if let commandExpression = parseCommandOrEscape(stoppingAt: .none) {
            return simplify(commandExpression)
        }

        let atom = parsePlainRun()
        return simplify(atom)
    }

    private mutating func parseOptionalBracketArgument() -> MarkdownMathExpression? {
        guard index < characters.count, characters[index] == "[" else { return nil }
        index += 1
        let content = parseUntilBracketClose()
        return simplify(.sequence(content))
    }

    private mutating func parseUntilBracketClose() -> [MarkdownMathExpression] {
        var parts: [MarkdownMathExpression] = []
        while index < characters.count, characters[index] != "]" {
            if let whitespace = parseWhitespace() {
                parts.append(whitespace)
                continue
            }
            if let command = parseCommandOrEscape(stoppingAt: .none) {
                parts.append(command)
                continue
            }
            if characters[index] == "{" {
                index += 1
                parts.append(parseSequence(stoppingAt: .closingBrace))
                if index < characters.count, characters[index] == "}" {
                    index += 1
                }
                continue
            }
            parts.append(parsePlainRun(stoppingAt: ["]"]))
        }
        if index < characters.count, characters[index] == "]" {
            index += 1
        }
        return parts
    }

    private mutating func parseTextArgument() -> String {
        let raw = parseGroupText()
        return raw.replacingOccurrences(of: "\\\\", with: "\n")
    }

    private mutating func parseGroupText() -> String {
        guard index < characters.count, characters[index] == "{" else { return "" }
        index += 1
        var depth = 1
        let start = index
        while index < characters.count {
            let character = characters[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    let text = String(characters[start..<index])
                    index += 1
                    return text
                }
            }
            index += 1
        }
        return String(characters[start..<characters.count])
    }

    private mutating func parseDelimiterToken() -> MarkdownMathDelimiter {
        guard index < characters.count else { return .none }
        if characters[index] == "." {
            index += 1
            return .none
        }
        if characters[index] == "|" {
            index += 1
            return .singleBar
        }
        if characters[index] == "[" || characters[index] == "]" || characters[index] == "(" || characters[index] == ")" {
            let delimiter = MarkdownMathDelimiter.glyph(String(characters[index]))
            index += 1
            return delimiter
        }
        if characters[index] == "{" || characters[index] == "}" {
            let delimiter = MarkdownMathDelimiter.glyph(String(characters[index]))
            index += 1
            return delimiter
        }
        if characters[index] == "\\" {
            index += 1
            if index < characters.count, !characters[index].isLetter {
                let symbol = characters[index]
                index += 1
                if symbol == "|" { return .singleBar }
                return .glyph(String(symbol))
            }
            let command = parseCommandName()
            switch command {
            case "lbrace", "rbrace":
                return .glyph(command == "lbrace" ? "{" : "}")
            case "lvert", "rvert":
                return .singleBar
            case "lVert", "rVert":
                return .doubleBar
            case "langle": return .glyph("⟨")
            case "rangle": return .glyph("⟩")
            case "lceil": return .glyph("⌈")
            case "rceil": return .glyph("⌉")
            case "lfloor": return .glyph("⌊")
            case "rfloor": return .glyph("⌋")
            case "Vert": return .doubleBar
            case "vert": return .singleBar
            case "{": return .glyph("{")
            case "}": return .glyph("}")
            default:
                return .glyph(command)
            }
        }
        let delimiter = MarkdownMathDelimiter.glyph(String(characters[index]))
        index += 1
        return delimiter
    }

    private mutating func parseEscapedSymbol(_ symbol: Character) -> MarkdownMathExpression {
        switch symbol {
        case "{", "}", "$", "%", "#", "_", "&":
            return .run(MarkdownMathRun(text: String(symbol), kind: .symbol))
        case ",":
            return .space(0.16)
        case ":":
            return .space(0.22)
        case ";":
            return .space(0.30)
        case "!":
            return .space(0)
        case " ":
            return .space(0.22)
        case "|":
            return .run(MarkdownMathRun(text: "|", kind: .symbol))
        default:
            return .run(MarkdownMathRun(text: "\\\(symbol)", kind: .text))
        }
    }

    private mutating func parsePlainRun(stoppingAt additionalStops: Set<Character> = []) -> MarkdownMathExpression {
        let start = index
        while index < characters.count {
            let character = characters[index]
            if additionalStops.contains(character) {
                break
            }
            if character == "\\" || character == "{" || character == "}" || character == "^" || character == "_" || character == "'" || character.isWhitespace {
                break
            }
            if character == "&" { break }
            index += 1
        }
        let text = String(characters[start..<index])
        let runs = makeRuns(from: text)
        return simplify(.sequence(runs.map(MarkdownMathExpression.run)))
    }

    private mutating func applyScriptsIfNeeded(to base: MarkdownMathExpression) -> MarkdownMathExpression {
        var superscript: MarkdownMathExpression?
        var subscriptExpression: MarkdownMathExpression?
        var consumed = false

        while index < characters.count {
            let marker = characters[index]
            guard marker == "^" || marker == "_" || marker == "'" else { break }
            consumed = true
            index += 1
            switch marker {
            case "^":
                superscript = parseRequiredArgument()
            case "_":
                subscriptExpression = parseRequiredArgument()
            case "'":
                let prime = MarkdownMathExpression.run(MarkdownMathRun(text: "′", kind: .symbol))
                if let existingSuperscript = superscript {
                    superscript = simplify(.sequence([existingSuperscript, prime]))
                } else {
                    superscript = prime
                }
                while index < characters.count, characters[index] == "'" {
                    index += 1
                    if let existingSuperscript = superscript {
                        superscript = simplify(.sequence([
                            existingSuperscript,
                            .run(MarkdownMathRun(text: "′", kind: .symbol))
                        ]))
                    }
                }
            default:
                break
            }
        }

        if consumed {
            return .scripts(base: base, superscript: superscript, subscriptExpression: subscriptExpression)
        }
        return base
    }

    private func simplify(_ expression: MarkdownMathExpression) -> MarkdownMathExpression {
        switch expression {
        case let .sequence(parts):
            let flat = parts.flatMap { expression -> [MarkdownMathExpression] in
                switch expression {
                case let .sequence(inner):
                    return inner
                default:
                    return [expression]
                }
            }
            if flat.isEmpty { return .run(MarkdownMathRun(text: "", kind: .symbol)) }
            if flat.count == 1, let only = flat.first { return only }
            return .sequence(flat)
        default:
            return expression
        }
    }

    private func makeRuns(from text: String) -> [MarkdownMathRun] {
        guard !text.isEmpty else { return [] }
        var runs: [MarkdownMathRun] = []
        var current = ""
        var currentKind: MarkdownMathRunKind?

        func kind(for character: Character) -> MarkdownMathRunKind {
            if character.isNumber { return .number }
            if character.isLetter { return .variable }
            return .symbol
        }

        func flush() {
            guard !current.isEmpty, let currentKind else { return }
            runs.append(MarkdownMathRun(text: current, kind: currentKind))
            current = ""
        }

        for character in text {
            let nextKind = kind(for: character)
            if currentKind == nil {
                currentKind = nextKind
            } else if currentKind != nextKind {
                flush()
                currentKind = nextKind
            }
            current.append(character)
        }
        flush()
        return runs
    }
}

#if DEBUG
enum MarkdownMathDiagnostics {
    static func parserIssues(in latex: String) -> [String] {
        var parser = MarkdownMathParser(source: latex)
        let expression = parser.parse()
        var issues: [String] = []
        collectIssues(from: expression, into: &issues)
        return issues
    }

    private static func collectIssues(
        from expression: MarkdownMathExpression,
        into issues: inout [String]
    ) {
        switch expression {
        case let .sequence(parts):
            for part in parts {
                collectIssues(from: part, into: &issues)
            }
        case let .run(run):
            if run.text.hasPrefix("\\") {
                issues.append("unresolved-run:\(run.text)")
            }
        case let .fraction(numerator, denominator, _):
            collectIssues(from: numerator, into: &issues)
            collectIssues(from: denominator, into: &issues)
        case let .root(index, radicand):
            if let index {
                collectIssues(from: index, into: &issues)
            }
            collectIssues(from: radicand, into: &issues)
        case let .scripts(base, superscript, subscriptExpression):
            collectIssues(from: base, into: &issues)
            if let superscript {
                collectIssues(from: superscript, into: &issues)
            }
            if let subscriptExpression {
                collectIssues(from: subscriptExpression, into: &issues)
            }
        case let .scriptPlacement(base, _):
            collectIssues(from: base, into: &issues)
        case let .stack(base, over, under):
            collectIssues(from: base, into: &issues)
            if let over {
                collectIssues(from: over, into: &issues)
            }
            if let under {
                collectIssues(from: under, into: &issues)
            }
        case let .delimited(left, content, right):
            collectIssues(from: content, into: &issues)
            collectDelimiterIssues(left, into: &issues)
            collectDelimiterIssues(right, into: &issues)
        case let .accent(_, base):
            collectIssues(from: base, into: &issues)
        case let .line(_, base):
            collectIssues(from: base, into: &issues)
        case let .boxed(base):
            collectIssues(from: base, into: &issues)
        case let .brace(_, base):
            collectIssues(from: base, into: &issues)
        case let .table(descriptor):
            for row in descriptor.rows {
                for cell in row {
                    collectIssues(from: cell, into: &issues)
                }
            }
        case let .displayStyle(content):
            collectIssues(from: content, into: &issues)
        case let .textStyle(content):
            collectIssues(from: content, into: &issues)
        case let .styled(_, content):
            collectIssues(from: content, into: &issues)
        case .space:
            break
        }
    }

    private static func collectDelimiterIssues(
        _ delimiter: MarkdownMathDelimiter,
        into issues: inout [String]
    ) {
        if case let .glyph(text) = delimiter,
           text.count > 1,
           text.allSatisfy({ $0.isLetter }) {
            issues.append("suspicious-delimiter:\(text)")
        }
    }
}
#endif

private enum MarkdownMathCommandMap {
    static func symbol(_ command: String) -> MarkdownMathRun? {
        switch command {
        case "alpha": return MarkdownMathRun(text: "α", kind: .variable)
        case "beta": return MarkdownMathRun(text: "β", kind: .variable)
        case "gamma": return MarkdownMathRun(text: "γ", kind: .variable)
        case "delta": return MarkdownMathRun(text: "δ", kind: .variable)
        case "epsilon", "varepsilon": return MarkdownMathRun(text: "ε", kind: .variable)
        case "zeta": return MarkdownMathRun(text: "ζ", kind: .variable)
        case "eta": return MarkdownMathRun(text: "η", kind: .variable)
        case "theta", "vartheta": return MarkdownMathRun(text: "θ", kind: .variable)
        case "iota": return MarkdownMathRun(text: "ι", kind: .variable)
        case "kappa": return MarkdownMathRun(text: "κ", kind: .variable)
        case "lambda": return MarkdownMathRun(text: "λ", kind: .variable)
        case "mu": return MarkdownMathRun(text: "μ", kind: .variable)
        case "nu": return MarkdownMathRun(text: "ν", kind: .variable)
        case "xi": return MarkdownMathRun(text: "ξ", kind: .variable)
        case "pi", "varpi": return MarkdownMathRun(text: "π", kind: .variable)
        case "rho", "varrho": return MarkdownMathRun(text: "ρ", kind: .variable)
        case "sigma", "varsigma": return MarkdownMathRun(text: "σ", kind: .variable)
        case "tau": return MarkdownMathRun(text: "τ", kind: .variable)
        case "upsilon": return MarkdownMathRun(text: "υ", kind: .variable)
        case "phi", "varphi": return MarkdownMathRun(text: "φ", kind: .variable)
        case "chi": return MarkdownMathRun(text: "χ", kind: .variable)
        case "psi": return MarkdownMathRun(text: "ψ", kind: .variable)
        case "omega": return MarkdownMathRun(text: "ω", kind: .variable)
        case "Gamma": return MarkdownMathRun(text: "Γ", kind: .symbol)
        case "Delta": return MarkdownMathRun(text: "Δ", kind: .symbol)
        case "Theta": return MarkdownMathRun(text: "Θ", kind: .symbol)
        case "Lambda": return MarkdownMathRun(text: "Λ", kind: .symbol)
        case "Xi": return MarkdownMathRun(text: "Ξ", kind: .symbol)
        case "Pi": return MarkdownMathRun(text: "Π", kind: .symbol)
        case "Sigma": return MarkdownMathRun(text: "Σ", kind: .symbol)
        case "Upsilon": return MarkdownMathRun(text: "Υ", kind: .symbol)
        case "Phi": return MarkdownMathRun(text: "Φ", kind: .symbol)
        case "Psi": return MarkdownMathRun(text: "Ψ", kind: .symbol)
        case "Omega": return MarkdownMathRun(text: "Ω", kind: .symbol)
        case "times": return MarkdownMathRun(text: "×", kind: .symbol)
        case "cdot": return MarkdownMathRun(text: "·", kind: .symbol)
        case "pm": return MarkdownMathRun(text: "±", kind: .symbol)
        case "mp": return MarkdownMathRun(text: "∓", kind: .symbol)
        case "div": return MarkdownMathRun(text: "÷", kind: .symbol)
        case "neq", "ne": return MarkdownMathRun(text: "≠", kind: .symbol)
        case "leq", "le": return MarkdownMathRun(text: "≤", kind: .symbol)
        case "geq", "ge": return MarkdownMathRun(text: "≥", kind: .symbol)
        case "approx": return MarkdownMathRun(text: "≈", kind: .symbol)
        case "equiv": return MarkdownMathRun(text: "≡", kind: .symbol)
        case "sim": return MarkdownMathRun(text: "∼", kind: .symbol)
        case "propto": return MarkdownMathRun(text: "∝", kind: .symbol)
        case "to", "rightarrow", "longrightarrow": return MarkdownMathRun(text: "→", kind: .symbol)
        case "leftarrow", "longleftarrow": return MarkdownMathRun(text: "←", kind: .symbol)
        case "leftrightarrow", "longleftrightarrow": return MarkdownMathRun(text: "↔", kind: .symbol)
        case "Rightarrow", "Longrightarrow": return MarkdownMathRun(text: "⇒", kind: .symbol)
        case "Leftarrow", "Longleftarrow": return MarkdownMathRun(text: "⇐", kind: .symbol)
        case "Leftrightarrow", "Longleftrightarrow": return MarkdownMathRun(text: "⇔", kind: .symbol)
        case "gets": return MarkdownMathRun(text: "←", kind: .symbol)
        case "iff": return MarkdownMathRun(text: "⇔", kind: .symbol)
        case "implies": return MarkdownMathRun(text: "⇒", kind: .symbol)
        case "mapsto": return MarkdownMathRun(text: "↦", kind: .symbol)
        case "infty": return MarkdownMathRun(text: "∞", kind: .symbol)
        case "partial": return MarkdownMathRun(text: "∂", kind: .symbol)
        case "nabla": return MarkdownMathRun(text: "∇", kind: .symbol)
        case "Re": return MarkdownMathRun(text: "ℜ", kind: .symbol)
        case "Im": return MarkdownMathRun(text: "ℑ", kind: .symbol)
        case "hbar": return MarkdownMathRun(text: "ℏ", kind: .symbol)
        case "aleph": return MarkdownMathRun(text: "ℵ", kind: .symbol)
        case "ell": return MarkdownMathRun(text: "ℓ", kind: .variable)
        case "forall": return MarkdownMathRun(text: "∀", kind: .symbol)
        case "exists": return MarkdownMathRun(text: "∃", kind: .symbol)
        case "in": return MarkdownMathRun(text: "∈", kind: .symbol)
        case "notin": return MarkdownMathRun(text: "∉", kind: .symbol)
        case "emptyset": return MarkdownMathRun(text: "∅", kind: .symbol)
        case "top": return MarkdownMathRun(text: "⊤", kind: .symbol)
        case "subset": return MarkdownMathRun(text: "⊂", kind: .symbol)
        case "subseteq": return MarkdownMathRun(text: "⊆", kind: .symbol)
        case "supset": return MarkdownMathRun(text: "⊃", kind: .symbol)
        case "supseteq": return MarkdownMathRun(text: "⊇", kind: .symbol)
        case "setminus": return MarkdownMathRun(text: "∖", kind: .symbol)
        case "mid": return MarkdownMathRun(text: "∣", kind: .symbol)
        case "parallel": return MarkdownMathRun(text: "∥", kind: .symbol)
        case "perp": return MarkdownMathRun(text: "⟂", kind: .symbol)
        case "cup": return MarkdownMathRun(text: "∪", kind: .symbol)
        case "cap": return MarkdownMathRun(text: "∩", kind: .symbol)
        case "land": return MarkdownMathRun(text: "∧", kind: .symbol)
        case "lor": return MarkdownMathRun(text: "∨", kind: .symbol)
        case "neg": return MarkdownMathRun(text: "¬", kind: .symbol)
        case "otimes": return MarkdownMathRun(text: "⊗", kind: .symbol)
        case "oplus": return MarkdownMathRun(text: "⊕", kind: .symbol)
        case "bullet": return MarkdownMathRun(text: "•", kind: .symbol)
        case "circ": return MarkdownMathRun(text: "○", kind: .symbol)
        case "angle": return MarkdownMathRun(text: "∠", kind: .symbol)
        case "sum": return MarkdownMathRun(text: "∑", kind: .largeOperator)
        case "prod": return MarkdownMathRun(text: "∏", kind: .largeOperator)
        case "coprod": return MarkdownMathRun(text: "∐", kind: .largeOperator)
        case "int": return MarkdownMathRun(text: "∫", kind: .integralOperator)
        case "iint": return MarkdownMathRun(text: "∬", kind: .integralOperator)
        case "iiint": return MarkdownMathRun(text: "∭", kind: .integralOperator)
        case "iiiint": return MarkdownMathRun(text: "⨌", kind: .integralOperator)
        case "oint": return MarkdownMathRun(text: "∮", kind: .integralOperator)
        case "oiint": return MarkdownMathRun(text: "∯", kind: .integralOperator)
        case "oiiint": return MarkdownMathRun(text: "∰", kind: .integralOperator)
        case "bigcup": return MarkdownMathRun(text: "⋃", kind: .largeOperator)
        case "bigcap": return MarkdownMathRun(text: "⋂", kind: .largeOperator)
        case "bigoplus": return MarkdownMathRun(text: "⨁", kind: .largeOperator)
        case "bigotimes": return MarkdownMathRun(text: "⨂", kind: .largeOperator)
        case "dots", "ldots": return MarkdownMathRun(text: "…", kind: .symbol)
        case "cdots": return MarkdownMathRun(text: "⋯", kind: .symbol)
        case "vdots": return MarkdownMathRun(text: "⋮", kind: .symbol)
        case "ddots": return MarkdownMathRun(text: "⋱", kind: .symbol)
        case "triangle", "vartriangle", "bigtriangleup": return MarkdownMathRun(text: "△", kind: .symbol)
        case "triangledown", "bigtriangledown": return MarkdownMathRun(text: "▽", kind: .symbol)
        case "triangleleft", "lhd": return MarkdownMathRun(text: "◃", kind: .symbol)
        case "triangleright", "rhd": return MarkdownMathRun(text: "▹", kind: .symbol)
        case "blacktriangle": return MarkdownMathRun(text: "▲", kind: .symbol)
        case "blacktriangledown": return MarkdownMathRun(text: "▼", kind: .symbol)
        case "blacktriangleleft", "unlhd": return MarkdownMathRun(text: "◀", kind: .symbol)
        case "blacktriangleright", "unrhd": return MarkdownMathRun(text: "▶", kind: .symbol)
        case "triangleq": return MarkdownMathRun(text: "≜", kind: .symbol)
        case "because": return MarkdownMathRun(text: "∵", kind: .symbol)
        case "therefore": return MarkdownMathRun(text: "∴", kind: .symbol)
        case "prime": return MarkdownMathRun(text: "′", kind: .symbol)
        case "dprime": return MarkdownMathRun(text: "″", kind: .symbol)
        case "trprime": return MarkdownMathRun(text: "‴", kind: .symbol)
        case "backprime": return MarkdownMathRun(text: "‵", kind: .symbol)
        case "vert": return MarkdownMathRun(text: "|", kind: .symbol)
        case "Vert": return MarkdownMathRun(text: "‖", kind: .symbol)
        case "lvert", "rvert": return MarkdownMathRun(text: "|", kind: .symbol)
        case "lVert", "rVert": return MarkdownMathRun(text: "‖", kind: .symbol)
        case "langle": return MarkdownMathRun(text: "⟨", kind: .symbol)
        case "rangle": return MarkdownMathRun(text: "⟩", kind: .symbol)
        case "lceil": return MarkdownMathRun(text: "⌈", kind: .symbol)
        case "rceil": return MarkdownMathRun(text: "⌉", kind: .symbol)
        case "lfloor": return MarkdownMathRun(text: "⌊", kind: .symbol)
        case "rfloor": return MarkdownMathRun(text: "⌋", kind: .symbol)
        case "lbrace", "rbrace": return MarkdownMathRun(text: command == "lbrace" ? "{" : "}", kind: .symbol)
        default:
            return nil
        }
    }

    static func operatorName(_ command: String) -> MarkdownMathRun? {
        switch command {
        case "sin", "cos", "tan", "cot", "sec", "csc",
             "arcsin", "arccos", "arctan", "arccot", "arcsec", "arccsc",
             "sinh", "cosh", "tanh":
            return MarkdownMathRun(text: command, kind: .operatorName)
        case "log", "ln", "exp", "det", "dim", "gcd", "deg", "Pr", "arg", "ker", "rank", "tr", "diag", "sgn":
            return MarkdownMathRun(text: command, kind: .operatorName)
        case "lim", "limsup", "liminf", "sup", "inf", "max", "min":
            return MarkdownMathRun(text: command, kind: .limitOperator)
        default:
            return nil
        }
    }

    static func space(_ command: String) -> CGFloat? {
        switch command {
        case ",": return 0.16
        case ":": return 0.22
        case ";": return 0.30
        case "!": return 0
        case "quad": return 0.80
        case "qquad": return 1.60
        default: return nil
        }
    }
}

private func layout(
    _ expression: MarkdownMathExpression,
    context: MarkdownMathLayoutContext
) -> MarkdownMathRenderNode {
    switch expression {
    case let .sequence(parts):
        return layoutSequence(parts, context: context)

    case let .run(run):
        return layoutRun(run, context: context)

    case let .space(emWidth):
        return MarkdownMathRenderNode.empty(width: max(0, emWidth) * context.fontSize)

    case let .fraction(numerator, denominator, hasRule):
        return layoutFraction(
            numerator: numerator,
            denominator: denominator,
            hasRule: hasRule,
            context: context
        )

    case let .root(index, radicand):
        return layoutRoot(index: index, radicand: radicand, context: context)

    case let .scripts(base, superscript, subscriptExpression):
        return layoutScripts(
            base: base,
            superscript: superscript,
            subscriptExpression: subscriptExpression,
            context: context
        )

    case let .scriptPlacement(base, _):
        return layout(base, context: context)

    case let .stack(base, over, under):
        return layoutStack(base: base, over: over, under: under, context: context)

    case let .delimited(left, content, right):
        return layoutDelimited(left: left, content: content, right: right, context: context)

    case let .accent(accent, base):
        return layoutAccent(accent, base: base, context: context)

    case let .line(decoration, base):
        return layoutLineDecoration(decoration, base: base, context: context)

    case let .boxed(base):
        return layoutBoxed(base, context: context)

    case let .brace(position, base):
        return layoutBrace(position, base: base, context: context)

    case let .table(descriptor):
        return layoutTable(descriptor, context: context)

    case let .displayStyle(content):
        return layout(
            content,
            context: MarkdownMathLayoutContext(
                style: context.style,
                fontSize: context.fontSize,
                displayMode: true,
                fontOverride: context.fontOverride,
                textMode: context.textMode
            )
        )

    case let .textStyle(content):
        return layout(
            content,
            context: MarkdownMathLayoutContext(
                style: context.style,
                fontSize: context.fontSize,
                displayMode: false,
                fontOverride: context.fontOverride,
                textMode: context.textMode
            )
        )

    case let .styled(override, content):
        return layout(content, context: context.overriding(override))
    }
}

private func layoutSequence(
    _ parts: [MarkdownMathExpression],
    context: MarkdownMathLayoutContext
) -> MarkdownMathRenderNode {
    let nodes = parts
        .map { layout($0, context: context) }
        .filter { $0.size.width > 0 || $0.size.height > 0 }

    guard !nodes.isEmpty else { return MarkdownMathRenderNode.empty() }

    let alignmentAxis = nodes.map(\.alignmentAxis).max() ?? 0
    let descent = nodes.map { $0.size.height - $0.alignmentAxis }.max() ?? 0
    let height = alignmentAxis + descent
    let baseline = nodes.map { alignmentAxis + ($0.baseline - $0.alignmentAxis) }.max() ?? alignmentAxis

    var x: CGFloat = 0
    let offsets: [CGPoint] = nodes.map { node in
        let point = CGPoint(x: x, y: alignmentAxis - node.alignmentAxis)
        x += node.size.width
        return point
    }

    return MarkdownMathRenderNode(
        size: CGSize(width: x, height: height),
        baseline: baseline,
        alignmentAxis: alignmentAxis
    ) { cgContext, origin in
        for (node, offset) in zip(nodes, offsets) {
            node.draw(at: CGPoint(x: origin.x + offset.x, y: origin.y + offset.y), in: cgContext)
        }
    }
}

private func layoutRun(
    _ run: MarkdownMathRun,
    context: MarkdownMathLayoutContext
) -> MarkdownMathRenderNode {
    guard !run.text.isEmpty else { return MarkdownMathRenderNode.empty() }

    let font = resolvedFont(for: run, context: context)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: context.style.textColor
    ]
    let attributed = NSAttributedString(string: run.text, attributes: attributes)
    let size = measureAttributedText(attributed, width: .greatestFiniteMagnitude)
    let baseline = fontAscender(font)
    let alignmentAxis = opticalAlignmentAxis(for: run, attributed: attributed, font: font, size: size, context: context)

    return MarkdownMathRenderNode(size: size, baseline: baseline, alignmentAxis: alignmentAxis) { _, origin in
        attributed.draw(at: origin)
    }
}

private func layoutFraction(
    numerator: MarkdownMathExpression,
    denominator: MarkdownMathExpression,
    hasRule: Bool,
    context: MarkdownMathLayoutContext
) -> MarkdownMathRenderNode {
    let childContext = context.child(fontScale: context.displayMode ? 0.88 : 0.78, displayMode: false)
    let numeratorNode = layout(numerator, context: childContext)
    let denominatorNode = layout(denominator, context: childContext)
    let paddingX = max(2, context.fontSize * 0.18)
    let gap = max(2, context.fontSize * 0.12)
    let rule = hasRule ? context.fractionRuleThickness : 0
    let width = max(numeratorNode.size.width, denominatorNode.size.width) + paddingX * 2
    let numeratorX = (width - numeratorNode.size.width) / 2
    let denominatorX = (width - denominatorNode.size.width) / 2
    let numeratorY: CGFloat = 0
    let ruleY = numeratorNode.size.height + gap
    let denominatorY = ruleY + rule + gap
    let height = denominatorY + denominatorNode.size.height
    let axisY = numeratorNode.size.height + gap + (hasRule ? rule / 2 : 0)
    // Keep the rule centered on the surrounding math axis so relation symbols and large operators
    // don't appear to sag when a row contains taller fractions.
    let baseline = axisY + context.mathAxisOffset

    return MarkdownMathRenderNode(
        size: CGSize(width: width, height: height),
        baseline: baseline,
        alignmentAxis: axisY
    ) { cgContext, origin in
        numeratorNode.draw(at: CGPoint(x: origin.x + numeratorX, y: origin.y + numeratorY), in: cgContext)
        if hasRule {
            cgContext.saveGState()
            cgContext.setStrokeColor(context.style.textColor.cgColor)
            cgContext.setLineWidth(rule)
            cgContext.setLineCap(.butt)
            let lineY = origin.y + ruleY + rule / 2
            cgContext.move(to: CGPoint(x: origin.x + paddingX * 0.35, y: lineY))
            cgContext.addLine(to: CGPoint(x: origin.x + width - paddingX * 0.35, y: lineY))
            cgContext.strokePath()
            cgContext.restoreGState()
        }
        denominatorNode.draw(at: CGPoint(x: origin.x + denominatorX, y: origin.y + denominatorY), in: cgContext)
    }
}

private func layoutRoot(
    index indexExpression: MarkdownMathExpression?,
    radicand: MarkdownMathExpression,
    context: MarkdownMathLayoutContext
) -> MarkdownMathRenderNode {
    let radicandNode = layout(radicand, context: context)
    let lineThickness = context.radicalStrokeThickness
    let topPadding = max(lineThickness, context.fontSize * 0.08)
    let barGap = max(1, context.fontSize * 0.05)
    let radicandY = topPadding + lineThickness + barGap
    let baseline = radicandY + lineThickness + radicandNode.baseline
    let radicalBodyHeight = radicandY + radicandNode.size.height - topPadding
    let radicalWidth = max(context.fontSize * 0.56, radicalBodyHeight * 0.35)

    let indexNode: MarkdownMathRenderNode?
    let indexX: CGFloat
    let indexY: CGFloat
    if let indexExpression {
        let node = layout(indexExpression, context: context.child(fontScale: 0.55, displayMode: false))
        indexNode = node
        indexX = 0
        indexY = max(0, topPadding - node.size.height * 0.42)
    } else {
        indexNode = nil
        indexX = 0
        indexY = 0
    }

    let radicalX = (indexNode?.size.width ?? 0) * 0.74
    let contentX = radicalX + radicalWidth
    let width = contentX + radicandNode.size.width
    let height = max(
        radicandY + radicandNode.size.height,
        topPadding + radicalBodyHeight,
        indexY + (indexNode?.size.height ?? 0)
    )

    return MarkdownMathRenderNode(
        size: CGSize(width: width, height: height),
        baseline: baseline,
        alignmentAxis: radicandY + lineThickness + radicandNode.alignmentAxis
    ) { cgContext, origin in
        if let indexNode {
            indexNode.draw(at: CGPoint(x: origin.x + indexX, y: origin.y + indexY), in: cgContext)
        }

        let bodyTop = origin.y + topPadding
        let bodyBottom = origin.y + radicandY + radicandNode.size.height
        let cuspX = origin.x + contentX - lineThickness * 0.6
        let startX = origin.x + radicalX
        let hookX = startX + radicalWidth * 0.10
        let dipX = startX + radicalWidth * 0.22

        cgContext.saveGState()
        cgContext.setStrokeColor(context.style.textColor.cgColor)
        cgContext.setLineWidth(lineThickness)
        cgContext.setLineCap(.round)
        cgContext.setLineJoin(.round)
        cgContext.move(to: CGPoint(x: startX, y: bodyBottom - radicalBodyHeight * 0.22))
        cgContext.addLine(to: CGPoint(x: hookX, y: bodyBottom - radicalBodyHeight * 0.30))
        cgContext.addLine(to: CGPoint(x: dipX, y: bodyBottom))
        cgContext.addLine(to: CGPoint(x: cuspX, y: bodyTop + lineThickness))
        cgContext.addLine(to: CGPoint(x: origin.x + contentX + radicandNode.size.width, y: bodyTop + lineThickness))
        cgContext.strokePath()
        cgContext.restoreGState()

        radicandNode.draw(at: CGPoint(x: origin.x + contentX, y: origin.y + radicandY + lineThickness), in: cgContext)
    }
}

private func layoutScripts(
    base: MarkdownMathExpression,
    superscript: MarkdownMathExpression?,
    subscriptExpression: MarkdownMathExpression?,
    context: MarkdownMathLayoutContext
) -> MarkdownMathRenderNode {
    let baseNode = layout(base, context: context)
    guard superscript != nil || subscriptExpression != nil else { return baseNode }

    let scriptContext = context.child(fontScale: 0.7, displayMode: false)
    let superscriptNode = superscript.map { layout($0, context: scriptContext) }
    let subscriptNode = subscriptExpression.map { layout($0, context: scriptContext) }

    let prefersLimitPlacement = base.forcedLimitPlacement ?? (context.displayMode && base.prefersLimitPlacement)
    if prefersLimitPlacement {
        let gap = max(2, context.fontSize * 0.15)
        let width = max(baseNode.size.width, superscriptNode?.size.width ?? 0, subscriptNode?.size.width ?? 0)
        let superscriptY: CGFloat = 0
        let baseY = (superscriptNode?.size.height ?? 0) + (superscriptNode == nil ? 0 : gap)
        let subscriptY = baseY + baseNode.size.height + (subscriptNode == nil ? 0 : gap)
        let height = subscriptY + (subscriptNode?.size.height ?? 0)
        let baseline = baseY + baseNode.baseline

        return MarkdownMathRenderNode(
            size: CGSize(width: width, height: height),
            baseline: baseline,
            alignmentAxis: baseY + baseNode.alignmentAxis
        ) { cgContext, origin in
            if let superscriptNode {
                let x = (width - superscriptNode.size.width) / 2
                superscriptNode.draw(at: CGPoint(x: origin.x + x, y: origin.y + superscriptY), in: cgContext)
            }
            let baseX = (width - baseNode.size.width) / 2
            baseNode.draw(at: CGPoint(x: origin.x + baseX, y: origin.y + baseY), in: cgContext)
            if let subscriptNode {
                let x = (width - subscriptNode.size.width) / 2
                subscriptNode.draw(at: CGPoint(x: origin.x + x, y: origin.y + subscriptY), in: cgContext)
            }
        }
    }

    let gapX = max(1, context.fontSize * 0.06)
    let scriptX = baseNode.size.width + gapX
    let superscriptBaseline = baseNode.baseline - context.fontSize * 0.46
    let subscriptBaseline = baseNode.baseline + context.fontSize * 0.30
    let superscriptY = superscriptNode.map { superscriptBaseline - $0.baseline } ?? 0
    let subscriptY = subscriptNode.map { subscriptBaseline - $0.baseline } ?? 0
    let top = min(0, superscriptY)
    let bottom = max(
        baseNode.size.height,
        subscriptNode.map { subscriptY + $0.size.height } ?? baseNode.size.height
    )
    let width = baseNode.size.width + gapX + max(superscriptNode?.size.width ?? 0, subscriptNode?.size.width ?? 0)
    let height = bottom - top
    let baseline = baseNode.baseline - top

    return MarkdownMathRenderNode(
        size: CGSize(width: width, height: height),
        baseline: baseline,
        alignmentAxis: baseNode.alignmentAxis - top
    ) { cgContext, origin in
        let shiftedOrigin = CGPoint(x: origin.x, y: origin.y - top)
        baseNode.draw(at: shiftedOrigin, in: cgContext)
        if let superscriptNode {
            superscriptNode.draw(
                at: CGPoint(x: shiftedOrigin.x + scriptX, y: shiftedOrigin.y + superscriptY),
                in: cgContext
            )
        }
        if let subscriptNode {
            subscriptNode.draw(
                at: CGPoint(x: shiftedOrigin.x + scriptX, y: shiftedOrigin.y + subscriptY),
                in: cgContext
            )
        }
    }
}

private func layoutStack(
    base: MarkdownMathExpression,
    over: MarkdownMathExpression?,
    under: MarkdownMathExpression?,
    context: MarkdownMathLayoutContext
) -> MarkdownMathRenderNode {
    let baseNode = layout(base, context: context)
    guard over != nil || under != nil else { return baseNode }

    let annotationContext = context.child(fontScale: 0.68, displayMode: false)
    let overNode = over.map { layout($0, context: annotationContext) }
    let underNode = under.map { layout($0, context: annotationContext) }
    let gap = max(2, context.fontSize * 0.12)
    let width = max(baseNode.size.width, overNode?.size.width ?? 0, underNode?.size.width ?? 0)
    let overY: CGFloat = 0
    let baseY = (overNode?.size.height ?? 0) + (overNode == nil ? 0 : gap)
    let underY = baseY + baseNode.size.height + (underNode == nil ? 0 : gap)
    let height = underY + (underNode?.size.height ?? 0)
    let baseline = baseY + baseNode.baseline

    return MarkdownMathRenderNode(
        size: CGSize(width: width, height: height),
        baseline: baseline,
        alignmentAxis: baseY + baseNode.alignmentAxis
    ) { cgContext, origin in
        if let overNode {
            let x = (width - overNode.size.width) / 2
            overNode.draw(at: CGPoint(x: origin.x + x, y: origin.y + overY), in: cgContext)
        }
        let baseX = (width - baseNode.size.width) / 2
        baseNode.draw(at: CGPoint(x: origin.x + baseX, y: origin.y + baseY), in: cgContext)
        if let underNode {
            let x = (width - underNode.size.width) / 2
            underNode.draw(at: CGPoint(x: origin.x + x, y: origin.y + underY), in: cgContext)
        }
    }
}

private func layoutDelimited(
    left: MarkdownMathDelimiter,
    content: MarkdownMathExpression,
    right: MarkdownMathDelimiter,
    context: MarkdownMathLayoutContext
) -> MarkdownMathRenderNode {
    let contentNode = layout(content, context: context)
    let leftNode = delimiterNode(left, targetHeight: max(contentNode.size.height, context.fontSize), targetBaseline: contentNode.alignmentAxis, context: context)
    let rightNode = delimiterNode(right, targetHeight: max(contentNode.size.height, context.fontSize), targetBaseline: contentNode.alignmentAxis, context: context)
    return layoutSequence([.run(MarkdownMathRun(text: "", kind: .symbol))], context: context)
        .replacingWith(nodes: [leftNode, contentNode, rightNode])
}

private func delimiterNode(
    _ delimiter: MarkdownMathDelimiter,
    targetHeight: CGFloat,
    targetBaseline: CGFloat,
    context: MarkdownMathLayoutContext
) -> MarkdownMathRenderNode {
    switch delimiter {
    case .none:
        return MarkdownMathRenderNode.empty()
    case .singleBar:
        let strokeWidth = context.delimiterStrokeThickness
        let width = max(strokeWidth + 0.6, context.fontSize * 0.10)
        return MarkdownMathRenderNode(size: CGSize(width: width, height: targetHeight), baseline: targetBaseline, alignmentAxis: targetBaseline) { cgContext, origin in
            cgContext.saveGState()
            cgContext.setStrokeColor(context.style.textColor.cgColor)
            cgContext.setLineWidth(strokeWidth)
            cgContext.setLineCap(.round)
            let x = origin.x + width / 2
            cgContext.move(to: CGPoint(x: x, y: origin.y + strokeWidth / 2))
            cgContext.addLine(to: CGPoint(x: x, y: origin.y + targetHeight - strokeWidth / 2))
            cgContext.strokePath()
            cgContext.restoreGState()
        }
    case .doubleBar:
        let strokeWidth = context.delimiterStrokeThickness
        let gap = max(1.1, strokeWidth * 1.25)
        let totalWidth = strokeWidth * 2 + gap
        return MarkdownMathRenderNode(size: CGSize(width: totalWidth, height: targetHeight), baseline: targetBaseline, alignmentAxis: targetBaseline) { cgContext, origin in
            cgContext.saveGState()
            cgContext.setStrokeColor(context.style.textColor.cgColor)
            cgContext.setLineWidth(strokeWidth)
            cgContext.setLineCap(.round)
            let top = origin.y + strokeWidth / 2
            let bottom = origin.y + targetHeight - strokeWidth / 2
            let leftX = origin.x + strokeWidth / 2
            let rightX = origin.x + strokeWidth + gap + strokeWidth / 2
            cgContext.move(to: CGPoint(x: leftX, y: top))
            cgContext.addLine(to: CGPoint(x: leftX, y: bottom))
            cgContext.move(to: CGPoint(x: rightX, y: top))
            cgContext.addLine(to: CGPoint(x: rightX, y: bottom))
            cgContext.strokePath()
            cgContext.restoreGState()
        }
    case let .glyph(text):
        if let vectorNode = scalableDelimiterNode(
            text,
            targetHeight: targetHeight,
            targetBaseline: targetBaseline,
            context: context
        ) {
            return vectorNode
        }
        var fontSize = max(context.fontSize, targetHeight * 0.82)
        var font = mathSerifFont(size: fontSize, override: .roman)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: context.style.textColor
        ]
        var attributed = NSAttributedString(string: text, attributes: attributes)
        var size = measureAttributedText(attributed, width: .greatestFiniteMagnitude)
        while size.height < targetHeight * 0.9 && fontSize < context.fontSize * 4 {
            fontSize *= 1.12
            font = mathSerifFont(size: fontSize, override: .roman)
            attributes[.font] = font
            attributed = NSAttributedString(string: text, attributes: attributes)
            size = measureAttributedText(attributed, width: .greatestFiniteMagnitude)
        }
        let nodeHeight = max(targetHeight, size.height)
        let drawY = (nodeHeight - size.height) / 2
        return MarkdownMathRenderNode(
            size: CGSize(width: size.width, height: nodeHeight),
            baseline: min(nodeHeight, max(0, targetBaseline))
        ) { _, origin in
            attributed.draw(at: CGPoint(x: origin.x, y: origin.y + drawY))
        }
    }
}

private func scalableDelimiterNode(
    _ text: String,
    targetHeight: CGFloat,
    targetBaseline: CGFloat,
    context: MarkdownMathLayoutContext
) -> MarkdownMathRenderNode? {
    let strokeWidth = context.delimiterStrokeThickness
    let nodeHeight = max(targetHeight, context.fontSize)

    switch text {
    case "[":
        let width = max(context.fontSize * 0.28, nodeHeight * 0.12)
        return strokedDelimiterNode(
            width: width,
            height: nodeHeight,
            baseline: targetBaseline,
            lineWidth: strokeWidth,
            color: context.style.textColor
        ) { path, rect in
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
    case "]":
        let width = max(context.fontSize * 0.28, nodeHeight * 0.12)
        return strokedDelimiterNode(
            width: width,
            height: nodeHeight,
            baseline: targetBaseline,
            lineWidth: strokeWidth,
            color: context.style.textColor
        ) { path, rect in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
    case "(":
        let width = max(context.fontSize * 0.30, nodeHeight * 0.16)
        return strokedDelimiterNode(
            width: width,
            height: nodeHeight,
            baseline: targetBaseline,
            lineWidth: strokeWidth,
            color: context.style.textColor
        ) { path, rect in
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control1: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.18),
                control2: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.18)
            )
        }
    case ")":
        let width = max(context.fontSize * 0.30, nodeHeight * 0.16)
        return strokedDelimiterNode(
            width: width,
            height: nodeHeight,
            baseline: targetBaseline,
            lineWidth: strokeWidth,
            color: context.style.textColor
        ) { path, rect in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY),
                control1: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.18),
                control2: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.18)
            )
        }
    case "{":
        let width = max(context.fontSize * 0.34, nodeHeight * 0.20)
        return strokedDelimiterNode(
            width: width,
            height: nodeHeight,
            baseline: targetBaseline,
            lineWidth: strokeWidth,
            color: context.style.textColor
        ) { path, rect in
            let midY = rect.midY
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.38, y: midY - rect.height * 0.10),
                control1: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.04),
                control2: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.28)
            )
            path.addCurve(
                to: CGPoint(x: rect.minX, y: midY),
                control1: CGPoint(x: rect.minX + rect.width * 0.12, y: midY - rect.height * 0.04),
                control2: CGPoint(x: rect.minX, y: midY - rect.height * 0.02)
            )
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.38, y: midY + rect.height * 0.10),
                control1: CGPoint(x: rect.minX, y: midY + rect.height * 0.02),
                control2: CGPoint(x: rect.minX + rect.width * 0.12, y: midY + rect.height * 0.04)
            )
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control1: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.maxY - rect.height * 0.28),
                control2: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.maxY - rect.height * 0.04)
            )
        }
    case "}":
        let width = max(context.fontSize * 0.34, nodeHeight * 0.20)
        return strokedDelimiterNode(
            width: width,
            height: nodeHeight,
            baseline: targetBaseline,
            lineWidth: strokeWidth,
            color: context.style.textColor
        ) { path, rect in
            let midY = rect.midY
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addCurve(
                to: CGPoint(x: rect.maxX - rect.width * 0.38, y: midY - rect.height * 0.10),
                control1: CGPoint(x: rect.maxX - rect.width * 0.44, y: rect.minY + rect.height * 0.04),
                control2: CGPoint(x: rect.maxX - rect.width * 0.44, y: rect.minY + rect.height * 0.28)
            )
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: midY),
                control1: CGPoint(x: rect.maxX - rect.width * 0.12, y: midY - rect.height * 0.04),
                control2: CGPoint(x: rect.maxX, y: midY - rect.height * 0.02)
            )
            path.addCurve(
                to: CGPoint(x: rect.maxX - rect.width * 0.38, y: midY + rect.height * 0.10),
                control1: CGPoint(x: rect.maxX, y: midY + rect.height * 0.02),
                control2: CGPoint(x: rect.maxX - rect.width * 0.12, y: midY + rect.height * 0.04)
            )
            path.addCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY),
                control1: CGPoint(x: rect.maxX - rect.width * 0.44, y: rect.maxY - rect.height * 0.28),
                control2: CGPoint(x: rect.maxX - rect.width * 0.44, y: rect.maxY - rect.height * 0.04)
            )
        }
    case "⌈":
        let width = max(context.fontSize * 0.28, nodeHeight * 0.12)
        return strokedDelimiterNode(
            width: width,
            height: nodeHeight,
            baseline: targetBaseline,
            lineWidth: strokeWidth,
            color: context.style.textColor
        ) { path, rect in
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
    case "⌉":
        let width = max(context.fontSize * 0.28, nodeHeight * 0.12)
        return strokedDelimiterNode(
            width: width,
            height: nodeHeight,
            baseline: targetBaseline,
            lineWidth: strokeWidth,
            color: context.style.textColor
        ) { path, rect in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
    case "⌊":
        let width = max(context.fontSize * 0.28, nodeHeight * 0.12)
        return strokedDelimiterNode(
            width: width,
            height: nodeHeight,
            baseline: targetBaseline,
            lineWidth: strokeWidth,
            color: context.style.textColor
        ) { path, rect in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
    case "⌋":
        let width = max(context.fontSize * 0.28, nodeHeight * 0.12)
        return strokedDelimiterNode(
            width: width,
            height: nodeHeight,
            baseline: targetBaseline,
            lineWidth: strokeWidth,
            color: context.style.textColor
        ) { path, rect in
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
    case "⟨":
        let width = max(context.fontSize * 0.28, nodeHeight * 0.14)
        return strokedDelimiterNode(
            width: width,
            height: nodeHeight,
            baseline: targetBaseline,
            lineWidth: strokeWidth,
            color: context.style.textColor
        ) { path, rect in
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
    case "⟩":
        let width = max(context.fontSize * 0.28, nodeHeight * 0.14)
        return strokedDelimiterNode(
            width: width,
            height: nodeHeight,
            baseline: targetBaseline,
            lineWidth: strokeWidth,
            color: context.style.textColor
        ) { path, rect in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
    default:
        return nil
    }
}

private func strokedDelimiterNode(
    width: CGFloat,
    height: CGFloat,
    baseline: CGFloat,
    lineWidth: CGFloat,
    color: MarkdownPlatformColor,
    builder: @escaping (CGMutablePath, CGRect) -> Void
) -> MarkdownMathRenderNode {
    MarkdownMathRenderNode(size: CGSize(width: width, height: height), baseline: baseline, alignmentAxis: baseline) { cgContext, origin in
        let inset = lineWidth / 2
        let rect = CGRect(
            x: origin.x + inset,
            y: origin.y + inset,
            width: max(0, width - lineWidth),
            height: max(0, height - lineWidth)
        )
        let path = CGMutablePath()
        builder(path, rect)
        cgContext.saveGState()
        cgContext.setStrokeColor(color.cgColor)
        cgContext.setLineWidth(lineWidth)
        cgContext.setLineCap(.round)
        cgContext.setLineJoin(.round)
        cgContext.addPath(path)
        cgContext.strokePath()
        cgContext.restoreGState()
    }
}

private func layoutAccent(
    _ accent: MarkdownMathAccent,
    base: MarkdownMathExpression,
    context: MarkdownMathLayoutContext
) -> MarkdownMathRenderNode {
    let baseNode = layout(base, context: context)
    let accentHeight = max(3, context.fontSize * 0.22)
    let gap = max(1, context.fontSize * 0.08)
    let width = max(baseNode.size.width, context.fontSize * 0.42)
    let baseX = (width - baseNode.size.width) / 2
    let baseY = accentHeight + gap
    let height = baseY + baseNode.size.height
    let baseline = baseY + baseNode.baseline

    return MarkdownMathRenderNode(
        size: CGSize(width: width, height: height),
        baseline: baseline,
        alignmentAxis: baseY + baseNode.alignmentAxis
    ) { cgContext, origin in
        cgContext.setStrokeColor(context.style.textColor.cgColor)
        cgContext.setFillColor(context.style.textColor.cgColor)
        cgContext.setLineWidth(max(1, context.ruleThickness * 0.8))
        let rect = CGRect(x: origin.x, y: origin.y, width: width, height: accentHeight)
        switch accent {
        case .bar:
            let lineRect = CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: max(1, context.ruleThickness))
            cgContext.fill(lineRect.integral)
        case .hat:
            cgContext.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            cgContext.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            cgContext.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            cgContext.strokePath()
        case .tilde:
            let y = rect.midY
            cgContext.move(to: CGPoint(x: rect.minX, y: y))
            cgContext.addCurve(
                to: CGPoint(x: rect.maxX, y: y),
                control1: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY),
                control2: CGPoint(x: rect.minX + rect.width * 0.78, y: rect.maxY)
            )
            cgContext.strokePath()
        case .vec:
            let y = rect.midY
            cgContext.move(to: CGPoint(x: rect.minX, y: y))
            cgContext.addLine(to: CGPoint(x: rect.maxX - accentHeight * 0.35, y: y))
            cgContext.strokePath()
            cgContext.move(to: CGPoint(x: rect.maxX - accentHeight * 0.55, y: y - accentHeight * 0.22))
            cgContext.addLine(to: CGPoint(x: rect.maxX, y: y))
            cgContext.addLine(to: CGPoint(x: rect.maxX - accentHeight * 0.55, y: y + accentHeight * 0.22))
            cgContext.strokePath()
        case .leftVec:
            let y = rect.midY
            cgContext.move(to: CGPoint(x: rect.maxX, y: y))
            cgContext.addLine(to: CGPoint(x: rect.minX + accentHeight * 0.35, y: y))
            cgContext.strokePath()
            cgContext.move(to: CGPoint(x: rect.minX + accentHeight * 0.55, y: y - accentHeight * 0.22))
            cgContext.addLine(to: CGPoint(x: rect.minX, y: y))
            cgContext.addLine(to: CGPoint(x: rect.minX + accentHeight * 0.55, y: y + accentHeight * 0.22))
            cgContext.strokePath()
        case .doubleVec:
            let y = rect.midY
            cgContext.move(to: CGPoint(x: rect.minX + accentHeight * 0.5, y: y))
            cgContext.addLine(to: CGPoint(x: rect.maxX - accentHeight * 0.5, y: y))
            cgContext.strokePath()
            cgContext.move(to: CGPoint(x: rect.maxX - accentHeight * 0.7, y: y - accentHeight * 0.22))
            cgContext.addLine(to: CGPoint(x: rect.maxX, y: y))
            cgContext.addLine(to: CGPoint(x: rect.maxX - accentHeight * 0.7, y: y + accentHeight * 0.22))
            cgContext.strokePath()
            cgContext.move(to: CGPoint(x: rect.minX + accentHeight * 0.7, y: y - accentHeight * 0.22))
            cgContext.addLine(to: CGPoint(x: rect.minX, y: y))
            cgContext.addLine(to: CGPoint(x: rect.minX + accentHeight * 0.7, y: y + accentHeight * 0.22))
            cgContext.strokePath()
        case .dot:
            let dotSize = min(rect.height, rect.width)
            let dotRect = CGRect(x: rect.midX - dotSize / 2, y: rect.midY - dotSize / 2, width: dotSize, height: dotSize)
            cgContext.fillEllipse(in: dotRect)
        case .ddot:
            let dotSize = min(rect.height * 0.9, rect.width * 0.24)
            let leftRect = CGRect(x: rect.midX - dotSize * 1.4, y: rect.midY - dotSize / 2, width: dotSize, height: dotSize)
            let rightRect = CGRect(x: rect.midX + dotSize * 0.4, y: rect.midY - dotSize / 2, width: dotSize, height: dotSize)
            cgContext.fillEllipse(in: leftRect)
            cgContext.fillEllipse(in: rightRect)
        }
        baseNode.draw(at: CGPoint(x: origin.x + baseX, y: origin.y + baseY), in: cgContext)
    }
}

private func layoutLineDecoration(
    _ decoration: MarkdownMathLineDecoration,
    base: MarkdownMathExpression,
    context: MarkdownMathLayoutContext
) -> MarkdownMathRenderNode {
    let baseNode = layout(base, context: context)
    let lineThickness = max(1, context.ruleThickness)
    let gap = max(1, context.fontSize * 0.08)
    let width = baseNode.size.width
    let baseY = decoration == .overline ? lineThickness + gap : 0
    let height = decoration == .overline
        ? baseY + baseNode.size.height
        : baseNode.size.height + gap + lineThickness
    let baseline = decoration == .overline ? baseY + baseNode.baseline : baseNode.baseline

    return MarkdownMathRenderNode(
        size: CGSize(width: width, height: height),
        baseline: baseline,
        alignmentAxis: decoration == .overline ? baseY + baseNode.alignmentAxis : baseNode.alignmentAxis
    ) { cgContext, origin in
        baseNode.draw(at: CGPoint(x: origin.x, y: origin.y + baseY), in: cgContext)
        cgContext.setFillColor(context.style.textColor.cgColor)
        let lineY = decoration == .overline
            ? origin.y
            : origin.y + baseNode.size.height + gap
        let lineRect = CGRect(x: origin.x, y: lineY, width: width, height: lineThickness)
        cgContext.fill(lineRect.integral)
    }
}

private func layoutBoxed(
    _ base: MarkdownMathExpression,
    context: MarkdownMathLayoutContext
) -> MarkdownMathRenderNode {
    let baseNode = layout(base, context: context)
    let horizontalPadding = max(3, context.fontSize * 0.14)
    let verticalPadding = max(2, context.fontSize * 0.10)
    let strokeWidth = max(1, context.ruleThickness * 1.1)
    let width = baseNode.size.width + horizontalPadding * 2
    let height = baseNode.size.height + verticalPadding * 2
    let baseline = verticalPadding + baseNode.baseline

    return MarkdownMathRenderNode(
        size: CGSize(width: width, height: height),
        baseline: baseline,
        alignmentAxis: verticalPadding + baseNode.alignmentAxis
    ) { cgContext, origin in
        baseNode.draw(
            at: CGPoint(x: origin.x + horizontalPadding, y: origin.y + verticalPadding),
            in: cgContext
        )

        cgContext.saveGState()
        cgContext.setStrokeColor(context.style.textColor.cgColor)
        cgContext.setLineWidth(strokeWidth)
        let inset = strokeWidth / 2
        let rect = CGRect(
            x: origin.x + inset,
            y: origin.y + inset,
            width: max(0, width - strokeWidth),
            height: max(0, height - strokeWidth)
        )
        cgContext.stroke(rect.integral)
        cgContext.restoreGState()
    }
}

private func layoutBrace(
    _ position: MarkdownMathBracePosition,
    base: MarkdownMathExpression,
    context: MarkdownMathLayoutContext
) -> MarkdownMathRenderNode {
    let baseNode = layout(base, context: context)
    let braceHeight = max(7, context.fontSize * 0.34)
    let gap = max(1, context.fontSize * 0.08)
    let width = max(baseNode.size.width, context.fontSize * 0.9)
    let baseX = (width - baseNode.size.width) / 2
    let baseY = position == .over ? braceHeight + gap : 0
    let braceY = position == .over ? 0 : baseNode.size.height + gap
    let height = baseNode.size.height + braceHeight + gap
    let baseline = position == .over ? baseY + baseNode.baseline : baseNode.baseline

    return MarkdownMathRenderNode(
        size: CGSize(width: width, height: height),
        baseline: baseline,
        alignmentAxis: position == .over ? baseY + baseNode.alignmentAxis : baseNode.alignmentAxis
    ) { cgContext, origin in
        baseNode.draw(at: CGPoint(x: origin.x + baseX, y: origin.y + baseY), in: cgContext)
        drawBraceDecoration(
            in: CGRect(x: origin.x, y: origin.y + braceY, width: width, height: braceHeight),
            position: position,
            context: context,
            cgContext: cgContext
        )
    }
}

private func drawBraceDecoration(
    in rect: CGRect,
    position: MarkdownMathBracePosition,
    context: MarkdownMathLayoutContext,
    cgContext: CGContext
) {
    let width = max(rect.width, 6)
    let minX = rect.minX
    let maxX = rect.maxX
    let midX = rect.midX
    let topY = rect.minY
    let bottomY = rect.maxY
    let edgeY = position == .over ? bottomY : topY
    let cuspY = position == .over ? topY : bottomY
    let shoulderInset = width * 0.12
    let innerInset = width * 0.08

    let path = CGMutablePath()
    path.move(to: CGPoint(x: minX, y: edgeY))
    path.addCurve(
        to: CGPoint(x: midX - width * 0.14, y: edgeY),
        control1: CGPoint(x: minX + shoulderInset, y: edgeY),
        control2: CGPoint(x: minX + width * 0.22, y: cuspY)
    )
    path.addCurve(
        to: CGPoint(x: midX, y: cuspY),
        control1: CGPoint(x: midX - innerInset, y: edgeY),
        control2: CGPoint(x: midX - width * 0.04, y: cuspY)
    )
    path.addCurve(
        to: CGPoint(x: midX + width * 0.14, y: edgeY),
        control1: CGPoint(x: midX + width * 0.04, y: cuspY),
        control2: CGPoint(x: midX + innerInset, y: edgeY)
    )
    path.addCurve(
        to: CGPoint(x: maxX, y: edgeY),
        control1: CGPoint(x: maxX - width * 0.22, y: cuspY),
        control2: CGPoint(x: maxX - shoulderInset, y: edgeY)
    )

    cgContext.saveGState()
    cgContext.addPath(path)
    cgContext.setStrokeColor(context.style.textColor.cgColor)
    cgContext.setLineWidth(max(1, context.ruleThickness * 0.9))
    cgContext.setLineCap(.round)
    cgContext.setLineJoin(.round)
    cgContext.strokePath()
    cgContext.restoreGState()
}

private func layoutTable(
    _ descriptor: MarkdownMathTableDescriptor,
    context: MarkdownMathLayoutContext
) -> MarkdownMathRenderNode {
    let cellContext = context.child(
        fontScale: descriptor.compact ? 0.88 : 0.94,
        displayMode: descriptor.compact ? false : context.displayMode
    )
    let rowGap = max(4, cellContext.fontSize * 0.20)
    let columnGap = max(8, cellContext.fontSize * 0.26)
    let ruleThickness = max(1, context.ruleThickness)

    let columnCount = descriptor.rows.map(\.count).max() ?? 0
    guard columnCount > 0 else { return MarkdownMathRenderNode.empty() }

    let layoutRows = descriptor.rows.map { row in
        row.map { layout($0, context: cellContext) }
    }
    var columnWidths = Array(repeating: CGFloat(0), count: columnCount)
    var rowHeights: [CGFloat] = []
    var rowAlignmentAxes: [CGFloat] = []

    for row in layoutRows {
        var rowAxis: CGFloat = 0
        var rowDescent: CGFloat = 0
        for (columnIndex, cell) in row.enumerated() {
            columnWidths[columnIndex] = max(columnWidths[columnIndex], cell.size.width)
            rowAxis = max(rowAxis, cell.alignmentAxis)
            rowDescent = max(rowDescent, cell.size.height - cell.alignmentAxis)
        }
        rowAlignmentAxes.append(rowAxis)
        rowHeights.append(rowAxis + rowDescent)
    }

    let normalizedVerticalRules = Set(
        descriptor.verticalRules
            .map { max(0, min($0, columnCount)) }
    )
    let normalizedHorizontalRules = Set(
        descriptor.horizontalRules
            .map { max(0, min($0, layoutRows.count)) }
    )
    var columnOrigins = Array(repeating: CGFloat(0), count: columnCount)
    var cursorX: CGFloat = 0
    var verticalLineFrames: [CGRect] = []

    for columnIndex in 0...columnCount {
        if normalizedVerticalRules.contains(columnIndex) {
            verticalLineFrames.append(
                CGRect(x: cursorX, y: 0, width: ruleThickness, height: 0)
            )
            cursorX += ruleThickness
        }

        guard columnIndex < columnCount else { continue }
        columnOrigins[columnIndex] = cursorX
        cursorX += columnWidths[columnIndex]
        if columnIndex < columnCount - 1 {
            cursorX += columnGap
        }
    }

    let tableWidth = cursorX
    let tableHeight = rowHeights.reduce(0, +) + CGFloat(max(0, layoutRows.count - 1)) * rowGap
    var horizontalLineFrames: [CGRect] = []
    var cursorY: CGFloat = 0

    if normalizedHorizontalRules.contains(0) {
        horizontalLineFrames.append(CGRect(x: 0, y: 0, width: tableWidth, height: ruleThickness))
    }

    for rowIndex in layoutRows.indices {
        cursorY += rowHeights[rowIndex]
        if normalizedHorizontalRules.contains(rowIndex + 1) {
            let y: CGFloat
            if rowIndex == layoutRows.count - 1 {
                y = max(0, tableHeight - ruleThickness)
            } else {
                y = max(0, cursorY + (rowGap - ruleThickness) / 2)
            }
            horizontalLineFrames.append(CGRect(x: 0, y: y, width: tableWidth, height: ruleThickness))
        }
        if rowIndex < layoutRows.count - 1 {
            cursorY += rowGap
        }
    }

    let tableNode = MarkdownMathRenderNode(
        size: CGSize(width: tableWidth, height: tableHeight),
        baseline: tableHeight / 2
    ) { cgContext, origin in
        var y = origin.y
        for (rowIndex, row) in layoutRows.enumerated() {
            let rowAxis = rowAlignmentAxes[rowIndex]
            for columnIndex in 0..<columnCount {
                let cell = columnIndex < row.count ? row[columnIndex] : MarkdownMathRenderNode.empty()
                let alignment: MarkdownMathColumnAlignment
                if descriptor.layoutMode == .multline, columnCount == 1 {
                    switch rowIndex {
                    case 0:
                        alignment = layoutRows.count == 1 ? .center : .left
                    case layoutRows.count - 1:
                        alignment = .right
                    default:
                        alignment = .center
                    }
                } else {
                    alignment = descriptor.alignments.indices.contains(columnIndex)
                        ? descriptor.alignments[columnIndex]
                        : .center
                }
                let drawX: CGFloat
                switch alignment {
                case .left:
                    drawX = origin.x + columnOrigins[columnIndex]
                case .right:
                    drawX = origin.x + columnOrigins[columnIndex] + columnWidths[columnIndex] - cell.size.width
                case .center:
                    drawX = origin.x + columnOrigins[columnIndex] + (columnWidths[columnIndex] - cell.size.width) / 2
                }
                let drawY = y + rowAxis - cell.alignmentAxis
                cell.draw(at: CGPoint(x: drawX, y: drawY), in: cgContext)
            }
            y += rowHeights[rowIndex] + rowGap
        }

        if !verticalLineFrames.isEmpty {
            cgContext.saveGState()
            cgContext.setFillColor(context.style.textColor.cgColor)
            for frame in verticalLineFrames {
                let rect = CGRect(
                    x: origin.x + frame.minX,
                    y: origin.y,
                    width: frame.width,
                    height: tableHeight
                )
                cgContext.fill(rect.integral)
            }
            cgContext.restoreGState()
        }

        if !horizontalLineFrames.isEmpty {
            cgContext.saveGState()
            cgContext.setFillColor(context.style.textColor.cgColor)
            for frame in horizontalLineFrames {
                let rect = CGRect(
                    x: origin.x + frame.minX,
                    y: origin.y + frame.minY,
                    width: frame.width,
                    height: frame.height
                )
                cgContext.fill(rect.integral)
            }
            cgContext.restoreGState()
        }
    }

    if descriptor.leftDelimiter == .none, descriptor.rightDelimiter == .none {
        return tableNode
    }
    return layoutDelimited(
        left: descriptor.leftDelimiter,
        content: .table(
            MarkdownMathTableDescriptor(
                rows: descriptor.rows,
                alignments: descriptor.alignments,
                verticalRules: descriptor.verticalRules,
                horizontalRules: descriptor.horizontalRules,
                leftDelimiter: .none,
                rightDelimiter: .none,
                compact: descriptor.compact,
                layoutMode: descriptor.layoutMode
            )
        ),
        right: descriptor.rightDelimiter,
        context: context
    )
}

private func resolvedFont(
    for run: MarkdownMathRun,
    context: MarkdownMathLayoutContext
) -> MarkdownPlatformFont {
    if mathTextPrefersSystemFont(run.text) {
        let base = MarkdownPlatformFont.systemFont(ofSize: context.fontSize)
        return applyFontOverride(base, override: context.fontOverride == .text ? nil : context.fontOverride)
    }

    let override = context.fontOverride
    let effectiveKind: MarkdownMathRunKind = {
        if override == .text { return .text }
        return run.kind
    }()

    switch effectiveKind {
    case .text:
        let base = MarkdownPlatformFont.systemFont(ofSize: context.fontSize)
        return applyFontOverride(base, override: override)
    case .operatorName, .limitOperator, .symbol, .number:
        let base = mathSerifFont(size: context.fontSize, override: .roman)
        return applyFontOverride(base, override: override)
    case .largeOperator, .integralOperator:
        let base = mathSerifFont(size: context.fontSize * (context.displayMode ? 1.18 : 1.05), override: .roman)
        return applyFontOverride(base, override: override)
    case .variable:
        let baseOverride: MarkdownMathFontOverride = {
            switch override {
            case .roman, .bold, .boldItalic, .sansSerif, .monospaced, .text:
                return override ?? .italic
            default:
                return .italic
            }
        }()
        return mathSerifFont(size: context.fontSize, override: baseOverride)
    }
}

private func applyFontOverride(
    _ font: MarkdownPlatformFont,
    override: MarkdownMathFontOverride?
) -> MarkdownPlatformFont {
    guard let override else { return font }
    switch override {
    case .roman:
        return removeItalicTrait(font)
    case .bold:
        return boldFont(from: removeItalicTrait(font))
    case .italic:
        return italicFont(from: font)
    case .boldItalic:
        return italicFont(from: boldFont(from: font))
    case .sansSerif:
        #if os(iOS) || os(tvOS) || os(watchOS)
        return MarkdownPlatformFont.systemFont(ofSize: font.pointSize)
        #elseif os(macOS)
        return MarkdownPlatformFont.systemFont(ofSize: font.pointSize)
        #endif
    case .monospaced:
        #if os(iOS) || os(tvOS) || os(watchOS)
        return MarkdownPlatformFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
        #elseif os(macOS)
        return MarkdownPlatformFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
        #endif
    case .text:
        return font
    }
}

private func mathSerifFont(
    size: CGFloat,
    override: MarkdownMathFontOverride
) -> MarkdownPlatformFont {
    #if os(iOS) || os(tvOS) || os(watchOS)
    let base = MarkdownPlatformFont(name: "Times New Roman", size: size)
        ?? MarkdownPlatformFont.systemFont(ofSize: size)
    #elseif os(macOS)
    let base = MarkdownPlatformFont(name: "Times New Roman", size: size)
        ?? MarkdownPlatformFont.systemFont(ofSize: size)
    #endif
    return applyFontOverride(base, override: override)
}

private func fontAscender(_ font: MarkdownPlatformFont) -> CGFloat {
    #if os(iOS) || os(tvOS) || os(watchOS)
    return ceil(font.ascender)
    #elseif os(macOS)
    return ceil(font.ascender)
    #endif
}

private func measuredRelationCenterOffset(for font: MarkdownPlatformFont) -> CGFloat {
    let attributed = NSAttributedString(string: "=", attributes: [.font: font])
    let size = measureAttributedText(attributed, width: .greatestFiniteMagnitude)
    return max(1.5, fontAscender(font) - size.height / 2)
}

private func opticalAlignmentAxis(
    for run: MarkdownMathRun,
    attributed _: NSAttributedString,
    font: MarkdownPlatformFont,
    size: CGSize,
    context: MarkdownMathLayoutContext
) -> CGFloat {
    switch run.kind {
    case .symbol, .largeOperator, .integralOperator, .limitOperator:
        return size.height / 2
    case .operatorName, .number, .variable, .text:
        return max(0, fontAscender(font) - context.mathAxisOffset)
    }
}

private func removeItalicTrait(_ font: MarkdownPlatformFont) -> MarkdownPlatformFont {
    #if os(iOS) || os(tvOS) || os(watchOS)
    let traits = font.fontDescriptor.symbolicTraits.subtracting(.traitItalic)
    guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
    return MarkdownPlatformFont(descriptor: descriptor, size: font.pointSize)
    #elseif os(macOS)
    let traits = font.fontDescriptor.symbolicTraits.subtracting(.italic)
    let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
    return MarkdownPlatformFont(descriptor: descriptor, size: font.pointSize) ?? font
    #endif
}

private func mathTextPrefersSystemFont(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x3040...0x30FF, 0xAC00...0xD7AF, 0x1D538...0x1D56B:
            return true
        default:
            return false
        }
    }
}

private extension MarkdownMathRenderNode {
    func replacingWith(nodes: [MarkdownMathRenderNode]) -> MarkdownMathRenderNode {
        let alignmentAxis = nodes.map(\.alignmentAxis).max() ?? 0
        let descent = nodes.map { $0.size.height - $0.alignmentAxis }.max() ?? 0
        let height = alignmentAxis + descent
        let baseline = nodes.map { alignmentAxis + ($0.baseline - $0.alignmentAxis) }.max() ?? alignmentAxis
        var x: CGFloat = 0
        let offsets = nodes.map { node -> CGPoint in
            let point = CGPoint(x: x, y: alignmentAxis - node.alignmentAxis)
            x += node.size.width
            return point
        }
        return MarkdownMathRenderNode(
            size: CGSize(width: x, height: height),
            baseline: baseline,
            alignmentAxis: alignmentAxis
        ) { cgContext, origin in
            for (node, offset) in zip(nodes, offsets) {
                node.draw(at: CGPoint(x: origin.x + offset.x, y: origin.y + offset.y), in: cgContext)
            }
        }
    }
}

private extension Character {
    var isLetter: Bool {
        unicodeScalars.allSatisfy(\.properties.isAlphabetic)
    }

    var isNumber: Bool {
        unicodeScalars.allSatisfy { $0.properties.numericType != nil }
    }

    var isWhitespace: Bool {
        unicodeScalars.allSatisfy(\.properties.isWhitespace)
    }
}

private func mathColorsEqual(_ lhs: MarkdownPlatformColor, _ rhs: MarkdownPlatformColor) -> Bool {
    #if os(iOS) || os(tvOS) || os(watchOS)
    var leftRed: CGFloat = 0
    var leftGreen: CGFloat = 0
    var leftBlue: CGFloat = 0
    var leftAlpha: CGFloat = 0
    var rightRed: CGFloat = 0
    var rightGreen: CGFloat = 0
    var rightBlue: CGFloat = 0
    var rightAlpha: CGFloat = 0
    guard lhs.getRed(&leftRed, green: &leftGreen, blue: &leftBlue, alpha: &leftAlpha),
          rhs.getRed(&rightRed, green: &rightGreen, blue: &rightBlue, alpha: &rightAlpha)
    else {
        return lhs == rhs
    }
    return abs(leftRed - rightRed) <= 0.001 &&
        abs(leftGreen - rightGreen) <= 0.001 &&
        abs(leftBlue - rightBlue) <= 0.001 &&
        abs(leftAlpha - rightAlpha) <= 0.001
    #elseif os(macOS)
    let left = lhs.usingColorSpace(.sRGB) ?? lhs
    let right = rhs.usingColorSpace(.sRGB) ?? rhs
    return abs(left.redComponent - right.redComponent) <= 0.001 &&
        abs(left.greenComponent - right.greenComponent) <= 0.001 &&
        abs(left.blueComponent - right.blueComponent) <= 0.001 &&
        abs(left.alphaComponent - right.alphaComponent) <= 0.001
    #endif
}

private func mathFontsEqual(_ lhs: MarkdownPlatformFont, _ rhs: MarkdownPlatformFont) -> Bool {
    abs(lhs.pointSize - rhs.pointSize) <= 0.01 && lhs.fontName == rhs.fontName
}
