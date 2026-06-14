import CoreGraphics
import Testing
@testable import VoiceChatRaTeX

struct VoiceChatRaTeXSmokeTests {
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
}
