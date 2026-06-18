//
//  MathInputSheetView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/4/25.
//

import SwiftUI
import Logging

import ChocofordUI
import MathJaxSwift

enum LatexMathSVGRenderer {
    static func renderSVG(from input: String, foregroundColor: String? = nil) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MathInputError.emptyInput
        }
        let mathjax = try MathJax()
        let svg = try mathjax.tex2svg(trimmed)
        guard let foregroundColor else {
            return svg
        }
        return applyForegroundColor(foregroundColor, to: svg)
    }

    private static func applyForegroundColor(_ color: String, to svg: String) -> String {
        var svg = svg
        svg = svg.replacingOccurrences(of: #"fill="currentColor""#, with: #"fill="\#(color)""#)
        svg = svg.replacingOccurrences(of: #"stroke="currentColor""#, with: #"stroke="\#(color)""#)

        guard let svgStart = svg.range(of: "<svg"),
              let tagEnd = svg[svgStart.upperBound...].firstIndex(of: ">") else {
            return svg
        }

        let tagRange = svgStart.lowerBound...tagEnd
        var tag = String(svg[tagRange])
        if let styleRange = tag.range(of: #"style="[^"]*""#, options: .regularExpression) {
            let styleAttribute = String(tag[styleRange])
            let style = styleAttribute
                .dropFirst(#"style=""#.count)
                .dropLast()
                .replacingOccurrences(
                    of: #"(^|;)\s*(color|fill)\s*:\s*[^;]*;?"#,
                    with: "$1",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let separator = style.isEmpty ? "" : " "
            tag.replaceSubrange(styleRange, with: #"style="color: \#(color); fill: \#(color);\#(separator)\#(style)""#)
        } else {
            tag.insert(contentsOf: #" style="color: \#(color); fill: \#(color);""#, at: tag.index(before: tag.endIndex))
        }

        if let fillRange = tag.range(of: #"\sfill="[^"]*""#, options: .regularExpression) {
            tag.replaceSubrange(fillRange, with: #" fill="\#(color)""#)
        } else {
            tag.insert(contentsOf: #" fill="\#(color)""#, at: tag.index(before: tag.endIndex))
        }

        svg.replaceSubrange(tagRange, with: tag)
        return svg
    }

    static func debugPrintSVGBeforeInsert(_ svg: String, source: String) {
#if DEBUG
        print(
            """
            [LatexMathSVGRenderer] MathJax SVG before insert (\(source)):
            \(svg)
            """
        )
#endif
    }
}

private enum MathInputError: LocalizedError {
    case emptyInput

    var errorDescription: String? {
        "Enter a LaTeX math expression."
    }
}

struct MathInputSheetViewModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var appPreference: AppPreference
    @EnvironmentObject private var fileState: FileState

    @Binding var isPresented: Bool
    @State private var resolvedCanvasColorScheme: ColorScheme?

    private var fallbackCanvasColorScheme: ColorScheme {
        appPreference.excalidrawAppearance.colorScheme ?? colorScheme
    }

    private var canvasColorScheme: ColorScheme {
        resolvedCanvasColorScheme ?? fallbackCanvasColorScheme
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                MathInputSheetView(canvasColorScheme: canvasColorScheme) { svg in
                    LatexMathSVGRenderer.debugPrintSVGBeforeInsert(svg, source: "toolbar")
                    guard let data = svg.data(using: .utf8) else { return }
                    Task {
                        do {
                            try await fileState.excalidrawWebCoordinator?.loadImageToExcalidrawCanvas(
                                imageData: data,
                                type: "svg+xml"
                            )
                        } catch {
                            alertToast(error)
                        }
                    }
                }
                .swiftyAlert(logs: true)
                .task {
                    await refreshCanvasColorScheme()
                }
            }
    }

    private func refreshCanvasColorScheme() async {
        guard let coordinator = fileState.excalidrawWebCoordinator,
              let isDark = try? await coordinator.getIsDark() else {
            resolvedCanvasColorScheme = fallbackCanvasColorScheme
            return
        }
        resolvedCanvasColorScheme = isDark ? .dark : .light
    }
}

struct MathInputSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alertToast) private var alertToast
    
    let logger = Logger(label: "MathInputSheetView")

    var canvasColorScheme: ColorScheme
    var onInsert: (_ svg: String) -> Void
    
    @State private var inputText = ""
    @State private var selectedSVGColor = "#1e1e1e"
    
    @State private var svgContent: String?
    @State private var previewSVGURL: URL?
    
    @State private var error: Error?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 8) {
                Text(.localizable(.toolbarLatexMath))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("e^{i\\pi}+1=0", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(.localizable(.settingsExcalidrawDrawingSettingsStrokeTitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ColorButtonGroup(
                    colors: ColorPalette.strokeQuickPicks,
                    selectedColor: selectedSVGColor
                ) { color in
                    selectedSVGColor = color
                    generatePreview(input: inputText)
                }
                .environment(\.colorScheme, canvasColorScheme)
            }

            previewArea

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text(.localizable(.generalButtonCancel))
                }
                Button {
                    if let svgContent {
                        onInsert(svgContent)
                        dismiss()
                    }
                } label: {
                    Text(.localizable(.toolbarLatexMathButtonInsert))
                }
                .modernButtonStyle(style: .borderedProminent)
                .disabled(svgContent == nil)
            }
            .modernButtonStyle(size: .large, shape: .modern)
        }
        .padding(20)
#if os(macOS)
        .frame(width: 460)
#endif
        .onChange(of: inputText, debounce: 0.2) { newValue in
            generatePreview(input: newValue)
        }
        .watch(value: canvasColorScheme) { _ in
            generatePreview(input: inputText)
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(.localizable(.toolbarLatexMathInsertSheetTitle))
                .font(.title2.weight(.semibold))
            Spacer()
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(previewBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(canvasColorScheme == .dark ? 0.18 : 0.1))
                }

            previewContent
        }
        .frame(height: 132)
    }

    @ViewBuilder
    private var previewContent: some View {
        if let error {
            Text(errorDescription(for: error))
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.red)
                .padding()
        } else if let previewSVGURL {
            if canvasColorScheme == .light {
                SVGPreviewView(svgURL: previewSVGURL)
            } else {
                SVGPreviewView(svgURL: previewSVGURL)
                    .colorInvert()
                    .hueRotation(.degrees(180))
            }
        } else {
            Text(.localizable(.toolbarLatexMathInsertSheetPreviewTitle))
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var previewBackground: Color {
        canvasColorScheme == .dark ? Color(red: 0.08, green: 0.08, blue: 0.08) : .white
    }
    
    private func generatePreview(input: String) {
        logger.debug("[MathInputSheetView] generatePreview for \(input)")
        self.error = nil
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self.svgContent = nil
            self.previewSVGURL = nil
            return
        }

        do {
            let svg = try LatexMathSVGRenderer.renderSVG(
                from: input,
                foregroundColor: selectedSVGColor
            )
            let tempDir = FileManager.default.temporaryDirectory
            let svgFilename = "\(UUID()).svg"
            
            let svgURL = tempDir.appendingPathComponent(svgFilename, conformingTo: .svg)
            try svg.data(using: .utf8)?.write(to: svgURL)
            
            self.svgContent = svg
            self.previewSVGURL = svgURL
        }
        catch {
            logger.error("[MathInputSheetView] error: \(error)")
            self.error = error
            self.svgContent = nil
            self.previewSVGURL = nil
        }
    }

    private func errorDescription(for error: Error) -> String {
        if let error = error as? LocalizedError {
            return error.errorDescription ?? error.localizedDescription
        } else if let error = error as? any CustomStringConvertible {
            return error.description
        } else {
            return error.localizedDescription
        }
    }
}

#Preview {
    MathInputSheetView(canvasColorScheme: .dark) { _ in
        
    }
}
