//
//  RichMarkdownView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

@preconcurrency import Foundation
import SwiftUI
import Markdown

struct RichMarkdownView: View {
    let markdown: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sizeCategory) private var sizeCategory

    var body: some View {
        MarkdownTextView(markdown: markdown, colorScheme: colorScheme, sizeCategory: sizeCategory)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
private enum RichMarkdownPreviewSamples {
    static let smoke = #"""
    Inline: $\dfrac{a}{b}$, $\sqrt{1+x^2}$, $\sqrt[3]{1+x^2}$, $\left\{x \middle| x>0\right\}$, $\binom{n}{k}$.

    \[
    \begin{align}
    y&=\frac{1}{1+x}\\
    z&=\sum_{\begin{subarray}{c}1\le i\le n\\i\text{ odd}\end{subarray}} i
    \end{align}
    \]

    \[
    \sqrt[n]{a^2+b^2}
    \]

    \[
    A=\begin{pmatrix}
    1 & 2 \\
    3 & 4
    \end{pmatrix},
    \qquad
    f(x)=\begin{cases}
    x^2, & x\ge 0 \\
    -x, & x<0
    \end{cases}
    \]

    \[
    \begin{array}{|r|c|l|}
    \hline
    \alpha & \beta & \gamma \\
    \hline
    1 & 0 & -1 \\
    \hline
    \end{array}
    \]

    \[
    \overbrace{a+b+\cdots+z}^{26\text{ terms}}
    \xrightarrow[\ n\to\infty\ ]{\text{dominated}}
    \underline{\limsup_{n\to\infty} x_n}
    \]

    \[
    \begin{gathered}
    \operatorname*{argmax}_{x\in\mathbb{R}^n}\mathcal{L}(x)\\
    \left\|Ax-b\right\|_2 \le \varepsilon,\quad \mathfrak{g}\subset\mathbb{C}
    \end{gathered}
    \]

    \[
    \begin{multline}
    a_1+\cdots+a_n+b_1+\cdots+b_n\\
    = c_1+\cdots+c_n
    \end{multline}
    \]
    """#

    static let alignmentGallery = #"""
    Alignment environments:

    \[
    \begin{align}
    f(x)&=x^3+2x^2-1\\
    f'(x)&=3x^2+4x\\
    \int_0^1 f(x)\,dx&=\frac{11}{6}
    \end{align}
    \]

    \[
    \begin{alignedat}{2}
    x_1&=a+b+c, &\qquad y_1&=\sqrt{1+t^2}\\
    x_2&=\frac{1}{1+t}, & y_2&=\sum_{k=1}^{n} k
    \end{alignedat}
    \]

    \[
    \begin{split}
    \mathcal{L}(x)
    &= \sum_{i=1}^{n} (Ax-b)_i^2 \\
    &= \left\|Ax-b\right\|_2^2 + \lambda \left\|x\right\|_1
    \end{split}
    \]

    \[
    \begin{gathered}
    \lim_{n\to\infty} a_n = 0\\
    \operatorname*{argmax}_{x\in\mathbb{R}^m}\mathcal{J}(x)
    \end{gathered}
    \]

    \[
    \begin{multline}
    a_1+a_2+\cdots+a_n+b_1+b_2+\cdots+b_n+c_1+c_2+\cdots+c_n\\
    = d_1+d_2+\cdots+d_n
    \end{multline}
    \]
    """#

    static let delimiterAndMatrixGallery = #"""
    Delimiters, matrices, and piecewise forms:

    Inline:
    $\langle x,y\rangle$,
    $\lvert x\rvert \le \lVert A\rVert$,
    $\lceil \frac{n}{2} \rceil$,
    $\lfloor \frac{n-1}{2} \rfloor$,
    $\lbrace a,b,c \rbrace$.

    \[
    \left\langle \frac{x+y}{2}, z \right\rangle
    = \left\lVert \begin{bmatrix}x\\y\end{bmatrix} \right\rVert_2
    \]

    \[
    A=\begin{pmatrix}
    1 & 2 & 3 \\
    4 & 5 & 6 \\
    7 & 8 & 9
    \end{pmatrix},
    \quad
    B=\begin{Bmatrix}
    a & b \\
    c & d
    \end{Bmatrix}
    \]

    \[
    C=\begin{array}{|r|c|l|}
    \hline
    \alpha & \beta & \gamma \\
    \hline
    1 & 0 & -1 \\
    10 & 20 & 300 \\
    \hline
    \end{array}
    \]

    \[
    f(x)=\begin{cases}
    \dfrac{x^2-1}{x-1}, & x\ne 1 \\
    2, & x=1
    \end{cases}
    \]
    """#

    static let markdownLayoutGallery = #"""
    Mixed Markdown layout:

    Here is an inline formula: when $\sum_{k=1}^{n} k = \frac{n(n+1)}{2}$, write
    $\overbrace{x_1+\cdots+x_n}^{n\text{ terms}}$,
    and also allow a wider annotated arrow like $\xrightarrow[\ n\to\infty\ ]{\text{dominated}}$.

    - Block formulas inside lists should keep reasonable scaling and centering:

      \[
      \begin{aligned}
      p(x)&=\prod_{i=1}^{m}(x-\lambda_i)\\
      p'(x)&=\sum_{j=1}^{m}\prod_{i\ne j}(x-\lambda_i)
      \end{aligned}
      \]

    - The second item tests matrices and braces:

      \[
      \left\{
      \begin{aligned}
      u_t-\Delta u &= 0\\
      u|_{\partial\Omega} &= 0
      \end{aligned}
      \right.
      \]

    Also test a long formula block in a narrow layout:

    \[
    \begin{gathered}
    \int_{\Omega} \nabla u \cdot \nabla v \, dx = \lambda \int_{\Omega} uv \, dx\\
    \Pr(X\mid Y) = \frac{\Pr(Y\mid X)\Pr(X)}{\Pr(Y)}
    \end{gathered}
    \]

    Regular text after the table should not inherit the centered formula styling, and this final sentence should return to natural left alignment.
    """#
}

#Preview {
    RichMarkdownView(markdown: """
    # Rich Markdown

    This view renders **Markdown** with inline `code`, lists, and tables.

    - Item 1
    - Item 2

    > Block quote

    ```swift
    struct Hello { let value = 42 }
    ```
    """)
    .padding()
    .background(AppBackgroundView())
    .frame(maxWidth: 520)
}

#Preview("Markdown Smoke", traits: .sizeThatFitsLayout) {
    RichMarkdownView(markdown: RichMarkdownPreviewSamples.smoke)
        .padding(20)
        .background(AppBackgroundView())
        .frame(width: 520, alignment: .leading)
}

#Preview("Math Alignment Gallery", traits: .sizeThatFitsLayout) {
    RichMarkdownView(markdown: RichMarkdownPreviewSamples.alignmentGallery)
        .padding(20)
        .background(AppBackgroundView())
        .frame(width: 560, alignment: .leading)
}

#Preview("Delimiters And Matrices", traits: .sizeThatFitsLayout) {
    RichMarkdownView(markdown: RichMarkdownPreviewSamples.delimiterAndMatrixGallery)
        .padding(20)
        .background(AppBackgroundView())
        .frame(width: 560, alignment: .leading)
}

#Preview("Markdown Math Layout Narrow", traits: .sizeThatFitsLayout) {
    RichMarkdownView(markdown: RichMarkdownPreviewSamples.markdownLayoutGallery)
        .padding(20)
        .background(AppBackgroundView())
        .frame(width: 420, alignment: .leading)
}
#endif
