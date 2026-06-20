//
//  MathRenderService.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/19.
//

import Foundation

@MainActor
final class MathRenderService {
    static let shared = MathRenderService()

    private init() {}

    /// Owns math rendering before the result is handed to ExcalidrawCore for insertion.
    /// MathInput, AI tools, and MCP tools should depend on this service instead of a
    /// concrete MathJax or function-plot runtime.
    func render(_ request: MathRenderRequest) async throws -> MathRenderedSVG {
        switch request {
            case .latex(let request):
                return try await renderLatex(request)
            case .functionPlot(let request):
                return try await MathFunctionPlotWebRenderer.shared.render(request)
        }
    }

    func renderLatex(
        _ latex: String,
        foregroundColor: String? = nil
    ) async throws -> MathRenderedSVG {
        try await renderLatex(
            MathLatexRenderRequest(
                latex: latex,
                foregroundColor: foregroundColor
            )
        )
    }

    private func renderLatex(_ request: MathLatexRenderRequest) async throws -> MathRenderedSVG {
        try await LatexMathWebRenderer.shared.render(request)
    }
}

enum MathRenderRequest: Hashable, Sendable {
    case latex(MathLatexRenderRequest)
    case functionPlot(MathFunctionPlotRenderRequest)
}

struct MathLatexRenderRequest: Hashable, Sendable {
    var latex: String
    var foregroundColor: String?
}

struct MathFunctionPlotRenderRequest: Codable, Hashable, Sendable {
    var expressions: [MathFunctionPlotExpression]
    var width: Double
    var height: Double
    var xMin: Double
    var xMax: Double
    var yMin: Double
    var yMax: Double
    var xLabel: String
    var yLabel: String
    var showGrid: Bool
    var backgroundColor: String?
    var usesDarkPresentation: Bool

    var source: String {
        expressions
            .map(\.expression)
            .joined(separator: "\n")
    }

    func normalizedForFunctionPlot() -> MathFunctionPlotRenderRequest {
        var request = self
        request.expressions = expressions.map {
            MathFunctionPlotExpression(
                expression: $0.expression.normalizedFunctionPlotExpression,
                colorHex: $0.colorHex
            )
        }
        return request
    }
}

struct MathFunctionPlotExpression: Codable, Hashable, Sendable {
    var expression: String
    var colorHex: String
}

private extension String {
    var normalizedFunctionPlotExpression: String {
        var expression = trimmingCharacters(in: .whitespacesAndNewlines)

        if let equalsIndex = expression.firstIndex(of: "=") {
            let leftSide = expression[..<equalsIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if leftSide == "y" || leftSide.hasSuffix("(x)") {
                expression = String(expression[expression.index(after: equalsIndex)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let replacements: [(String, String)] = [
            (#"\left"#, ""),
            (#"\right"#, ""),
            (#"\sin"#, "sin"),
            (#"\cos"#, "cos"),
            (#"\tan"#, "tan"),
            (#"\log"#, "log"),
            (#"\ln"#, "log"),
            (#"\exp"#, "exp"),
            (#"\sqrt"#, "sqrt"),
            (#"\pi"#, "PI"),
            (#"\cdot"#, "*"),
            (#"\times"#, "*"),
            (#"\div"#, "/")
        ]

        for replacement in replacements {
            expression = expression.replacingOccurrences(of: replacement.0, with: replacement.1)
        }

        let regularExpressionOptions: String.CompareOptions = [.regularExpression]
        expression = expression.replacingOccurrences(
            of: #"\^\{([^{}]+)\}"#,
            with: "^($1)",
            options: regularExpressionOptions
        )
        expression = expression.replacingOccurrences(
            of: #"sqrt\{([^{}]+)\}"#,
            with: "sqrt($1)",
            options: regularExpressionOptions
        )
        expression = expression.replacingOccurrences(
            of: #"(\d|\))\s*x\b"#,
            with: "$1*x",
            options: regularExpressionOptions
        )
        expression = expression.replacingOccurrences(
            of: #"(\d|\))\s*(PI)\b"#,
            with: "$1*$2",
            options: regularExpressionOptions
        )
        expression = expression.replacingOccurrences(
            of: #"(\d|\)|x)\s*\("#,
            with: "$1*(",
            options: regularExpressionOptions
        )

        return expression
    }
}
