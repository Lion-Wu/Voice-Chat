#if os(visionOS)
import UIKit

/// The view-backed compatibility surface used only on visionOS, where the
/// official RaTeX Apple package does not yet publish a supported product.
/// iOS and macOS use RaTeX.RaTeXView directly.
@MainActor
public final class VoiceChatRaTeXView: UIView {
    public var latex: String {
        get { configuration.latex }
        set {
            configure(
                latex: newValue,
                fontSize: configuration.fontSize,
                displayMode: configuration.displayMode,
                color: configuration.color
            )
        }
    }

    public var fontSize: CGFloat {
        get { configuration.fontSize }
        set {
            configure(
                latex: configuration.latex,
                fontSize: newValue,
                displayMode: configuration.displayMode,
                color: configuration.color
            )
        }
    }

    public var displayMode: Bool {
        get { configuration.displayMode }
        set {
            configure(
                latex: configuration.latex,
                fontSize: configuration.fontSize,
                displayMode: newValue,
                color: configuration.color
            )
        }
    }

    public var color: UIColor {
        get { configuration.color }
        set {
            configure(
                latex: configuration.latex,
                fontSize: configuration.fontSize,
                displayMode: configuration.displayMode,
                color: newValue
            )
        }
    }

    public private(set) var mathAscent: CGFloat = 0
    public private(set) var mathDescent: CGFloat = 0
    public var onLayout: (@MainActor (CGFloat, CGFloat) -> Void)?

    private var configuration = Configuration()
    private var formula: VoiceChatRaTeXFormula?
    private var requestedRenderConfiguration: VoiceChatRaTeXRenderConfiguration?
    private var renderTask: Task<Void, Never>?
    private var renderSequence: UInt64 = 0
    private let baselineMarker = UIView()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        renderTask?.cancel()
    }

    public func configure(
        latex: String,
        fontSize: CGFloat,
        displayMode: Bool,
        color: UIColor
    ) {
        let updated = Configuration(
            latex: latex,
            fontSize: fontSize,
            displayMode: displayMode,
            color: color
        )
        guard !configuration.isEquivalent(to: updated) else { return }

        configuration = updated
        scheduleRender()
    }

    public override var forFirstBaselineLayout: UIView {
        baselineMarker
    }

    public override var forLastBaselineLayout: UIView {
        baselineMarker
    }

    public override var intrinsicContentSize: CGSize {
        guard let formula else { return .zero }
        return CGSize(width: ceil(formula.width), height: ceil(formula.totalHeight))
    }

    public override func draw(_ rect: CGRect) {
        guard let formula, let context = UIGraphicsGetCurrentContext() else { return }

        // RaTeX's display-list contract and UIKit both use a top-left origin
        // with Y increasing downward. The renderer performs the sole CoreText
        // glyph-axis conversion, matching RaTeX 0.1.13's Apple renderer.
        formula.draw(in: context)
    }

    private func setup() {
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        baselineMarker.isHidden = true
        baselineMarker.isUserInteractionEnabled = false
        addSubview(baselineMarker)
        registerForAppearanceChanges()
    }

    private func registerForAppearanceChanges() {
        if #available(iOS 17.0, visionOS 1.0, *) {
            registerForTraitChanges([
                UITraitUserInterfaceStyle.self,
                UITraitUserInterfaceIdiom.self,
                UITraitDisplayGamut.self,
                UITraitAccessibilityContrast.self,
                UITraitUserInterfaceLevel.self
            ]) {
                (view: VoiceChatRaTeXView, _) in
                view.scheduleRender()
            }
        }
    }

    private func scheduleRender() {
        let request = VoiceChatRaTeXRenderConfiguration(
            latex: configuration.latex,
            displayMode: configuration.displayMode,
            fontSize: configuration.fontSize,
            color: resolvedColor(configuration.color)
        )
        guard request != requestedRenderConfiguration else { return }

        requestedRenderConfiguration = request
        renderSequence &+= 1
        let sequence = renderSequence
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            let formula = await VoiceChatRaTeXEngine.shared.renderAsynchronously(request)
            guard !Task.isCancelled else { return }
            self?.commit(
                formula,
                for: request,
                sequence: sequence
            )
        }
    }

    private func commit(
        _ formula: VoiceChatRaTeXFormula?,
        for request: VoiceChatRaTeXRenderConfiguration,
        sequence: UInt64
    ) {
        guard sequence == renderSequence,
              request == requestedRenderConfiguration else {
            return
        }

        self.formula = formula
        renderTask = nil
        mathAscent = formula?.height ?? 0
        mathDescent = formula?.depth ?? 0
        baselineMarker.frame = CGRect(
            x: 0,
            y: mathAscent,
            width: 1,
            height: 0
        )
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
        onLayout?(mathAscent, formula?.totalHeight ?? 0)
    }

    private func resolvedColor(_ color: UIColor) -> VoiceChatRaTeXColor {
        let resolved = color.resolvedColor(with: traitCollection)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return VoiceChatRaTeXColor(red: 0, green: 0, blue: 0, alpha: 1)
        }
        return VoiceChatRaTeXColor(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            alpha: Double(alpha)
        )
    }

    private struct Configuration {
        var latex = ""
        var fontSize: CGFloat = 17
        var displayMode = false
        var color = UIColor.label

        func isEquivalent(to other: Configuration) -> Bool {
            latex == other.latex &&
                fontSize == other.fontSize &&
                displayMode == other.displayMode &&
                color.isEqual(other.color)
        }
    }
}
#endif
