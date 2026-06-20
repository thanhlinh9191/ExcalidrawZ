//
//  MathFunctionPlotWebRenderer.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/19.
//

import Foundation
import WebKit

@MainActor
final class MathFunctionPlotWebRenderer: NSObject {
    static let shared = MathFunctionPlotWebRenderer()

    private var webView: WKWebView?
    private var isReady = false
    private var preparationTask: Task<Void, Error>?
    private var loadContinuation: CheckedContinuation<Void, Error>?

    private override init() {
        super.init()
    }

    func render(_ request: MathFunctionPlotRenderRequest) async throws -> MathRenderedSVG {
        try await prepareWebView()

        let requestData = try JSONEncoder().encode(request.normalizedForFunctionPlot())
        guard let requestJSONString = String(data: requestData, encoding: .utf8) else {
            throw MathFunctionPlotRenderError.invalidRequest
        }

        let script = """
        window.ExcalidrawZMathRenderer.renderFunctionPlot(\(requestJSONString))
        """

        guard let result = try await evaluateJavaScript(script) as? [String: Any],
              let svg = result["svg"] as? String else {
            throw MathFunctionPlotRenderError.invalidRenderResult
        }

        return MathRenderedSVG(
            source: request.source,
            svg: svg,
            renderer: "function-plot",
            width: number(from: result["width"]) ?? request.width,
            height: number(from: result["height"]) ?? request.height
        )
    }

    private func prepareWebView() async throws {
        if isReady {
            return
        }

        if let preparationTask {
            try await preparationTask.value
            return
        }

        let task = Task { @MainActor in
            try await loadRuntime()
        }
        preparationTask = task
        defer { preparationTask = nil }
        try await task.value
    }

    private func loadRuntime() async throws {
        if webView == nil {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let webView = WKWebView(frame: .init(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
            webView.navigationDelegate = self
            self.webView = webView
        }

        guard let runtimeURL = functionPlotRuntimeURL,
              let webView else {
            throw MathFunctionPlotRenderError.missingFunctionPlotRuntime
        }

        try await withCheckedThrowingContinuation { continuation in
            loadContinuation = continuation
            webView.loadHTMLString(
                Self.runtimeHTML(scriptName: runtimeURL.lastPathComponent),
                baseURL: runtimeURL.deletingLastPathComponent()
            )
        }

        isReady = true
    }

    private var functionPlotRuntimeURL: URL? {
        Bundle.main.url(
            forResource: "function-plot-1.25.4",
            withExtension: "js",
            subdirectory: "MathRendering"
        )
        ?? Bundle.main.url(
            forResource: "function-plot-1.25.4",
            withExtension: "js"
        )
    }

    private func evaluateJavaScript(_ script: String) async throws -> Any? {
        guard let webView else {
            throw MathFunctionPlotRenderError.webViewUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: MathFunctionPlotRenderError.renderFailed(Self.renderErrorDescription(from: error)))
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    private static func renderErrorDescription(from error: Error) -> String {
        let nsError = error as NSError
        if let message = nsError.userInfo["WKJavaScriptExceptionMessage"] as? String,
           !message.isEmpty {
            return message
        }
        return error.localizedDescription
    }

    private func number(from value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        return nil
    }

    private static func runtimeHTML(scriptName: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                html, body {
                    width: 100%;
                    height: 100%;
                    margin: 0;
                    padding: 0;
                    overflow: hidden;
                    background: transparent;
                }
                #plot {
                    width: 1px;
                    height: 1px;
                    position: absolute;
                    left: 0;
                    top: 0;
                }
            </style>
            <script src="\(scriptName)"></script>
        </head>
        <body>
            <div id="plot"></div>
            <script>
                window.ExcalidrawZMathRenderer = {
                    renderFunctionPlot(request) {
                        if (typeof window.functionPlot !== "function") {
                            throw new Error("function-plot runtime is unavailable.");
                        }

                        const container = document.getElementById("plot");
                        container.innerHTML = "";

                        const width = Math.max(120, Number(request.width) || 720);
                        const height = Math.max(120, Number(request.height) || 720);
                        container.style.width = `${width}px`;
                        container.style.height = `${height}px`;

                        const expressions = (request.expressions || [])
                            .map((expression) => ({
                                fn: expression.expression,
                                color: expression.colorHex,
                                graphType: "polyline",
                                sampler: "builtIn"
                            }))
                            .filter((expression) => expression.fn);

                        if (expressions.length === 0) {
                            throw new Error("Enter at least one function.");
                        }

                        window.functionPlot({
                            target: "#plot",
                            width,
                            height,
                            grid: Boolean(request.showGrid),
                            disableZoom: true,
                            xAxis: {
                                domain: [Number(request.xMin), Number(request.xMax)],
                                label: request.xLabel || "x"
                            },
                            yAxis: {
                                domain: [Number(request.yMin), Number(request.yMax)],
                                label: request.yLabel || "y"
                            },
                            data: expressions
                        });

                        const svg = container.querySelector("svg");
                        if (!svg) {
                            throw new Error("function-plot did not produce an SVG.");
                        }

                        this.prepareSVG(svg, request, width, height);
                        return {
                            svg: new XMLSerializer().serializeToString(svg),
                            width,
                            height
                        };
                    },

                    prepareSVG(svg, request, width, height) {
                        const svgNS = "http://www.w3.org/2000/svg";
                        const backgroundColor = request.backgroundColor || "transparent";
                        const darkBackground = this.isDarkColor(backgroundColor)
                            || (backgroundColor === "transparent" && Boolean(request.usesDarkPresentation));
                        const axisColor = darkBackground ? "#f1f3f5" : "#343a40";
                        const textColor = darkBackground ? "#f8f9fa" : "#212529";
                        const gridColor = darkBackground ? "#495057" : "#d0d7de";
                        const tickFontSize = Math.max(14, Math.round(width * 0.029));
                        const labelFontSize = Math.max(16, Math.round(width * 0.034));
                        const axisStrokeWidth = Math.max(1.4, width * 0.003);
                        const gridStrokeWidth = Math.max(0.8, width * 0.0018);
                        const graphStrokeWidth = Math.max(2.2, width * 0.0048);

                        svg.setAttribute("xmlns", svgNS);
                        svg.setAttribute("width", String(width));
                        svg.setAttribute("height", String(height));
                        svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
                        svg.setAttribute("role", "img");

                        if (backgroundColor !== "transparent") {
                            const background = document.createElementNS(svgNS, "rect");
                            background.setAttribute("x", "0");
                            background.setAttribute("y", "0");
                            background.setAttribute("width", String(width));
                            background.setAttribute("height", String(height));
                            background.setAttribute("fill", backgroundColor);
                            svg.insertBefore(background, svg.firstChild);
                        }

                        const style = document.createElementNS(svgNS, "style");
                        style.textContent = `
                            text { fill: ${textColor}; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; font-size: ${tickFontSize}px; font-weight: 500; }
                            .axis path, .axis line { stroke: ${axisColor}; stroke-width: ${axisStrokeWidth}; fill: none; }
                            .grid line { stroke: ${gridColor}; stroke-width: ${gridStrokeWidth}; stroke-opacity: 0.92; }
                            .graph path { fill: none; stroke-width: ${graphStrokeWidth}; }
                        `;
                        svg.insertBefore(style, svg.firstChild);

                        svg.querySelectorAll("text").forEach((node) => {
                            node.setAttribute("fill", textColor);
                            node.setAttribute("font-family", "-apple-system, BlinkMacSystemFont, SF Pro Text, sans-serif");
                            node.setAttribute("font-size", String(tickFontSize));
                            node.setAttribute("font-weight", "500");
                        });

                        svg.querySelectorAll(".axis-label, .x.axis text:last-child, .y.axis text:last-child").forEach((node) => {
                            node.setAttribute("font-size", String(labelFontSize));
                            node.setAttribute("font-weight", "600");
                        });

                        svg.querySelectorAll(".axis path, .axis line").forEach((node) => {
                            node.setAttribute("stroke", axisColor);
                            node.setAttribute("stroke-width", String(axisStrokeWidth));
                            node.setAttribute("fill", "none");
                        });

                        svg.querySelectorAll(".grid line").forEach((node) => {
                            node.setAttribute("stroke", gridColor);
                            node.setAttribute("stroke-width", String(gridStrokeWidth));
                        });

                        svg.querySelectorAll(".graph path, .graph line").forEach((node) => {
                            node.setAttribute("stroke-width", String(graphStrokeWidth));
                            node.setAttribute("fill", "none");
                        });
                    },

                    isDarkColor(color) {
                        if (!color || color === "transparent" || !color.startsWith("#")) {
                            return false;
                        }
                        const hex = color.slice(1);
                        const normalized = hex.length === 3
                            ? hex.split("").map((part) => part + part).join("")
                            : hex.slice(0, 6);
                        const value = Number.parseInt(normalized, 16);
                        if (!Number.isFinite(value)) {
                            return false;
                        }
                        const red = (value >> 16) & 255;
                        const green = (value >> 8) & 255;
                        const blue = value & 255;
                        return (0.2126 * red + 0.7152 * green + 0.0722 * blue) < 128;
                    }
                };
            </script>
        </body>
        </html>
        """
    }
}

extension MathFunctionPlotWebRenderer: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            loadContinuation?.resume(returning: ())
            loadContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            loadContinuation?.resume(throwing: error)
            loadContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            loadContinuation?.resume(throwing: error)
            loadContinuation = nil
        }
    }
}

private enum MathFunctionPlotRenderError: LocalizedError {
    case invalidRequest
    case invalidRenderResult
    case missingFunctionPlotRuntime
    case webViewUnavailable
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
            case .invalidRequest:
                "Function plot request could not be encoded."
            case .invalidRenderResult:
                "Function plot renderer returned an invalid result."
            case .missingFunctionPlotRuntime:
                "Function plot runtime is missing from the app bundle."
            case .webViewUnavailable:
                "Function plot renderer is unavailable."
            case .renderFailed(let message):
                "Function plot failed: \(message)"
        }
    }
}
