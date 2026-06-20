//
//  MathInputLibrary.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/19.
//

import Foundation

extension MathSnippetSection {
    static let editorSections: [MathSnippetSection] = [
        .init(
            title: String(localizable: .toolbarLatexMathSnippetSectionStructure),
            snippets: [
                .init(display: "a⁄b", latex: "\\frac{a}{b}"),
                .init(display: "xⁿ", latex: "x^{n}"),
                .init(display: "xₙ", latex: "x_{n}"),
                .init(display: "√x", latex: "\\sqrt{x}"),
                .init(display: "ⁿ√x", latex: "\\sqrt[n]{x}"),
                .init(display: "( )", latex: "\\left( x \\right)")
            ]
        ),
        .init(
            title: String(localizable: .toolbarLatexMathSnippetSectionOperators),
            snippets: [
                .init(display: "±", latex: "\\pm"),
                .init(display: "×", latex: "\\times"),
                .init(display: "÷", latex: "\\div"),
                .init(display: "·", latex: "\\cdot"),
                .init(display: "≤", latex: "\\le"),
                .init(display: "≥", latex: "\\ge"),
                .init(display: "≠", latex: "\\ne"),
                .init(display: "≈", latex: "\\approx")
            ]
        ),
        .init(
            title: String(localizable: .toolbarLatexMathSnippetSectionCalculus),
            snippets: [
                .init(display: "∫", latex: "\\int_a^b f(x)\\,dx"),
                .init(display: "∑", latex: "\\sum_{i=1}^{n} i"),
                .init(display: "∏", latex: "\\prod_{i=1}^{n} i"),
                .init(display: "lim", latex: "\\lim_{x \\to 0} f(x)"),
                .init(display: "d⁄dx", latex: "\\frac{d}{dx} f(x)"),
                .init(display: "∂⁄∂x", latex: "\\frac{\\partial}{\\partial x} f(x, y)"),
                .init(display: "∞", latex: "\\infty")
            ]
        ),
        .init(
            title: String(localizable: .toolbarLatexMathSnippetSectionGreek),
            snippets: [
                .init(display: "α", latex: "\\alpha"),
                .init(display: "β", latex: "\\beta"),
                .init(display: "γ", latex: "\\gamma"),
                .init(display: "δ", latex: "\\delta"),
                .init(display: "θ", latex: "\\theta"),
                .init(display: "λ", latex: "\\lambda"),
                .init(display: "π", latex: "\\pi"),
                .init(display: "σ", latex: "\\sigma"),
                .init(display: "ω", latex: "\\omega"),
                .init(display: "Δ", latex: "\\Delta"),
                .init(display: "Σ", latex: "\\Sigma")
            ]
        ),
        .init(
            title: String(localizable: .toolbarLatexMathSnippetSectionTrig),
            minimumItemWidth: 64,
            snippets: [
                .init(display: "sin", latex: "\\sin(x)"),
                .init(display: "cos", latex: "\\cos(x)"),
                .init(display: "tan", latex: "\\tan(x)"),
                .init(display: "log", latex: "\\log(x)"),
                .init(display: "ln", latex: "\\ln(x)")
            ]
        ),
        .init(
            title: String(localizable: .toolbarLatexMathSnippetSectionLayout),
            minimumItemWidth: 104,
            snippets: [
                .init(display: "cases", latex: "\\begin{cases} a, & x > 0 \\\\ b, & x \\le 0 \\end{cases}"),
                .init(display: "matrix", latex: "\\begin{bmatrix} a & b \\\\ c & d \\end{bmatrix}"),
                .init(display: "→v", latex: "\\vec{v}"),
                .init(display: "x̂", latex: "\\hat{x}"),
                .init(display: "x̄", latex: "\\bar{x}"),
                .init(display: "ẋ", latex: "\\dot{x}")
            ]
        )
    ]
}

extension MathTemplate {
    static let equationTemplates: [MathTemplate] = [
        .init(title: "Quadratic Formula", category: "Algebra", latex: "x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}"),
        .init(title: "Euler Identity", category: "Complex Numbers", latex: "e^{i\\pi} + 1 = 0"),
        .init(title: "Binomial Theorem", category: "Algebra", latex: "(x + y)^n = \\sum_{k=0}^{n} \\binom{n}{k} x^{n-k} y^k"),
        .init(title: "Pythagorean Theorem", category: "Geometry", latex: "a^2 + b^2 = c^2"),
        .init(title: "Slope Formula", category: "Coordinate Geometry", latex: "m = \\frac{y_2 - y_1}{x_2 - x_1}"),
        .init(title: "Distance Formula", category: "Coordinate Geometry", latex: "d = \\sqrt{(x_2 - x_1)^2 + (y_2 - y_1)^2}"),
        .init(title: "2x2 Matrix", category: "Linear Algebra", latex: "\\begin{bmatrix} a & b \\\\ c & d \\end{bmatrix}"),
        .init(title: "Determinant", category: "Linear Algebra", latex: "\\det(A) = ad - bc"),
        .init(title: "Cases", category: "Layout", latex: "f(x) = \\begin{cases} x^2, & x \\ge 0 \\\\ -x, & x < 0 \\end{cases}"),
        .init(title: "Derivative", category: "Calculus", latex: "\\frac{d}{dx} f(x) = \\lim_{h \\to 0} \\frac{f(x+h)-f(x)}{h}"),
        .init(title: "Integral", category: "Calculus", latex: "\\int_a^b f(x)\\,dx = F(b) - F(a)"),
        .init(title: "Taylor Series", category: "Calculus", latex: "f(x) = \\sum_{n=0}^{\\infty} \\frac{f^{(n)}(a)}{n!}(x-a)^n"),
        .init(title: "Bayes Theorem", category: "Probability", latex: "P(A \\mid B) = \\frac{P(B \\mid A)P(A)}{P(B)}"),
        .init(title: "Normal Distribution", category: "Statistics", latex: "f(x) = \\frac{1}{\\sigma\\sqrt{2\\pi}} e^{-\\frac{1}{2}\\left(\\frac{x-\\mu}{\\sigma}\\right)^2}"),
        .init(title: "Vector Norm", category: "Linear Algebra", latex: "\\lVert \\vec{v} \\rVert = \\sqrt{v_1^2 + v_2^2 + \\cdots + v_n^2}"),
        .init(title: "Gradient", category: "Vector Calculus", latex: "\\nabla f = \\left\\langle \\frac{\\partial f}{\\partial x}, \\frac{\\partial f}{\\partial y}, \\frac{\\partial f}{\\partial z} \\right\\rangle")
    ]

    static let functionTemplates: [MathTemplate] = [
        .init(title: "Sine Function", category: "Trigonometry", latex: "f(x) = \\sin(x)"),
        .init(title: "Cosine Function", category: "Trigonometry", latex: "f(x) = \\cos(x)"),
        .init(title: "Tangent Function", category: "Trigonometry", latex: "f(x) = \\tan(x)"),
        .init(title: "Linear Function", category: "Algebra", latex: "f(x) = 2x + 1"),
        .init(title: "Quadratic Function", category: "Algebra", latex: "f(x) = x^2 - 3x + 2"),
        .init(title: "Cubic Function", category: "Algebra", latex: "f(x) = 0.2x^3 - x"),
        .init(title: "Exponential Function", category: "Algebra", latex: "f(x) = exp(0.5x)"),
        .init(title: "Logarithmic Function", category: "Algebra", latex: "f(x) = log(x)"),
        .init(title: "Absolute Value", category: "Algebra", latex: "f(x) = abs(x)"),
        .init(title: "Square Root", category: "Algebra", latex: "f(x) = sqrt(x)")
    ]

    static let geometryTemplates: [MathTemplate] = [
        .init(title: "Circle Area", category: "Geometry", latex: "A = \\pi r^2"),
        .init(title: "Circle Circumference", category: "Geometry", latex: "C = 2\\pi r"),
        .init(title: "Triangle Area", category: "Geometry", latex: "A = \\frac{1}{2}bh"),
        .init(title: "Rectangle Area", category: "Geometry", latex: "A = lw"),
        .init(title: "Trapezoid Area", category: "Geometry", latex: "A = \\frac{1}{2}(b_1 + b_2)h"),
        .init(title: "Heron's Formula", category: "Geometry", latex: "A = \\sqrt{s(s-a)(s-b)(s-c)}"),
        .init(title: "Law of Cosines", category: "Trigonometry", latex: "c^2 = a^2 + b^2 - 2ab\\cos(C)"),
        .init(title: "Law of Sines", category: "Trigonometry", latex: "\\frac{a}{\\sin A} = \\frac{b}{\\sin B} = \\frac{c}{\\sin C}"),
        .init(title: "Circle Equation", category: "Coordinate Geometry", latex: "(x-h)^2 + (y-k)^2 = r^2"),
        .init(title: "Line Equation", category: "Coordinate Geometry", latex: "y - y_1 = m(x - x_1)"),
        .init(title: "Sphere Volume", category: "Solid Geometry", latex: "V = \\frac{4}{3}\\pi r^3"),
        .init(title: "Cylinder Volume", category: "Solid Geometry", latex: "V = \\pi r^2 h"),
        .init(title: "Cone Volume", category: "Solid Geometry", latex: "V = \\frac{1}{3}\\pi r^2 h"),
        .init(title: "Angle Sum", category: "Geometry", latex: "\\sum \\theta = (n - 2)180^\\circ")
    ]
}
