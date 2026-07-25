import CoreGraphics
import Testing
@testable import VoiceChatRaTeX

struct VoiceChatRaTeXSmokeTests {
    @Test func reportsUpstreamWasmVersion() {
        #expect(VoiceChatRaTeXVersion.upstream == "0.1.13")
    }

    @Test func rendersSimpleInlineFormula() {
        let formula = VoiceChatRaTeXEngine.shared.render(
            latex: #"x^2 + y^2"#,
            displayMode: false,
            fontSize: 16,
            color: VoiceChatRaTeXColor(red: 0.1, green: 0.2, blue: 0.3)
        )

        #expect(formula != nil)
        #expect((formula?.width ?? 0) > 0)
        #expect((formula?.totalHeight ?? 0) > 0)
    }

    @Test func asynchronouslyCachesAnImmutableFormulaForAnExactConfiguration() async {
        let configuration = VoiceChatRaTeXRenderConfiguration(
            latex: #"\frac{a}{b} + \sqrt{x}"#,
            displayMode: true,
            fontSize: 19,
            color: VoiceChatRaTeXColor(red: 0.2, green: 0.3, blue: 0.4)
        )

        let first = await VoiceChatRaTeXEngine.shared.renderAsynchronously(configuration)
        let second = await VoiceChatRaTeXEngine.shared.renderAsynchronously(configuration)

        #expect(first != nil)
        #expect(first === second)
    }

    @Test func asynchronousRenderingKeepsConfigurationDimensionsIndependent() async {
        let base = VoiceChatRaTeXRenderConfiguration(
            latex: #"x^2"#,
            displayMode: false,
            fontSize: 14,
            color: VoiceChatRaTeXColor(red: 0, green: 0, blue: 0)
        )
        let larger = VoiceChatRaTeXRenderConfiguration(
            latex: base.latex,
            displayMode: base.displayMode,
            fontSize: 28,
            color: base.color
        )

        let smallFormula = await VoiceChatRaTeXEngine.shared.renderAsynchronously(base)
        let largeFormula = await VoiceChatRaTeXEngine.shared.renderAsynchronously(larger)

        #expect(smallFormula != nil)
        #expect(largeFormula != nil)
        #expect((largeFormula?.width ?? 0) == (smallFormula?.width ?? 0) * 2)
        #expect((largeFormula?.totalHeight ?? 0) == (smallFormula?.totalHeight ?? 0) * 2)
    }

    @Test func rejectsOversizedLatexBeforeRendering() {
        let oversizedLatex = String(repeating: "x", count: VoiceChatRaTeXRenderLimits.maxLatexUTF8Bytes + 1)
        let formula = VoiceChatRaTeXEngine.shared.render(
            latex: oversizedLatex,
            displayMode: true,
            fontSize: 16,
            color: VoiceChatRaTeXColor(red: 0, green: 0, blue: 0)
        )

        #expect(formula == nil)
    }

    @Test func clampsColorChannels() {
        let color = VoiceChatRaTeXColor(red: -1, green: 0.5, blue: 2, alpha: 3)

        #expect(color.red == 0)
        #expect(color.green == 0.5)
        #expect(color.blue == 1)
        #expect(color.alpha == 1)
    }

    @Test func encodesWasmColorsAsCSSRGBA() {
        let color = VoiceChatRaTeXColor(red: 0, green: 0.5, blue: 1, alpha: 0.25)

        #expect(color.cssHex == "#0080FF40")
    }
}
