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
    struct RenderedSVG: Hashable {
        let latex: String
        let svg: String
        let width: Double?
        let height: Double?

        var mathImageParams: ExcalidrawCore.MathImageParams {
            ExcalidrawCore.MathImageParams(
                svg: svg,
                latex: latex,
                renderer: "mathjax",
                width: width,
                height: height
            )
        }
    }

    static func render(from input: String, foregroundColor: String? = nil) throws -> RenderedSVG {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let svg = try renderSVG(from: trimmed, foregroundColor: foregroundColor)
        let size = intrinsicSize(from: svg)
        return RenderedSVG(
            latex: trimmed,
            svg: svg,
            width: size.width,
            height: size.height
        )
    }

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

    private static func intrinsicSize(from svg: String) -> (width: Double?, height: Double?) {
        (
            width: numericSVGLength(attribute: "width", in: svg),
            height: numericSVGLength(attribute: "height", in: svg)
        )
    }

    private static func numericSVGLength(attribute: String, in svg: String) -> Double? {
        let pattern = #"\b\#(attribute)="([0-9]+(?:\.[0-9]+)?)(px)?""#
        guard let range = svg.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let match = String(svg[range])
        let valuePattern = #""([0-9]+(?:\.[0-9]+)?)(px)?""#
        guard let valueRange = match.range(of: valuePattern, options: .regularExpression) else {
            return nil
        }
        let value = match[valueRange]
            .dropFirst()
            .dropLast(match[valueRange].hasSuffix(#"px""#) ? 3 : 1)
        return Double(String(value))
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
                MathInputSheetView(canvasColorScheme: canvasColorScheme) { renderedSVG in
                    LatexMathSVGRenderer.debugPrintSVGBeforeInsert(renderedSVG.svg, source: "toolbar")
                    Task {
                        do {
                            try await fileState.excalidrawWebCoordinator?.insertMathImage(
                                params: renderedSVG.mathImageParams,
                                options: .init(
                                    position: .auto,
                                    focus: .enabled(true),
                                    captureUpdate: .immediately
                                )
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

struct MathImageEditSheetViewModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appPreference: AppPreference

    @ObservedObject var coordinator: ExcalidrawCore
    var onError: (Error) -> Void

    @State private var resolvedCanvasColorScheme: ColorScheme?

    private var fallbackCanvasColorScheme: ColorScheme {
        appPreference.excalidrawAppearance.colorScheme ?? colorScheme
    }

    private var canvasColorScheme: ColorScheme {
        resolvedCanvasColorScheme ?? fallbackCanvasColorScheme
    }

    private var editRequest: Binding<ExcalidrawCore.MathImageEditRequest?> {
        Binding {
            coordinator.mathImageEditRequest
        } set: { newValue in
            if newValue == nil {
                coordinator.clearMathImageEditRequest()
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: editRequest) { request in
                MathInputSheetView(
                    canvasColorScheme: canvasColorScheme,
                    mode: .edit,
                    initialLatex: request.initialLatex,
                    initialSVGColor: request.preferredSVGColor ?? "#1e1e1e"
                ) { renderedSVG in
                    LatexMathSVGRenderer.debugPrintSVGBeforeInsert(renderedSVG.svg, source: "edit_math")
                    Task {
                        do {
                            try await coordinator.updateMathImage(
                                elementId: request.elementId,
                                params: renderedSVG.mathImageParams,
                                options: .init(
                                    focus: .enabled(true),
                                    captureUpdate: .immediately
                                )
                            )
                            coordinator.clearMathImageEditRequest()
                        } catch {
                            onError(error)
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
        guard let isDark = try? await coordinator.getIsDark() else {
            resolvedCanvasColorScheme = fallbackCanvasColorScheme
            return
        }
        resolvedCanvasColorScheme = isDark ? .dark : .light
    }
}

enum MathInputSheetMode {
    case insert
    case edit
}

struct MathInputSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alertToast) private var alertToast
    
    let logger = Logger(label: "MathInputSheetView")

    var canvasColorScheme: ColorScheme
    var mode: MathInputSheetMode
    var onCommit: (_ renderedSVG: LatexMathSVGRenderer.RenderedSVG) -> Void
    
    @State private var inputText: String
    @State private var selectedSVGColor: String
    
    @State private var svgContent: LatexMathSVGRenderer.RenderedSVG?
    @State private var previewSVGURL: URL?
    
    @State private var error: Error?

    init(
        canvasColorScheme: ColorScheme,
        mode: MathInputSheetMode = .insert,
        initialLatex: String = "",
        initialSVGColor: String = "#1e1e1e",
        onCommit: @escaping (_ renderedSVG: LatexMathSVGRenderer.RenderedSVG) -> Void
    ) {
        self.canvasColorScheme = canvasColorScheme
        self.mode = mode
        self.onCommit = onCommit
        self._inputText = State(initialValue: initialLatex)
        self._selectedSVGColor = State(initialValue: initialSVGColor)
    }
    
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
                        onCommit(svgContent)
                        dismiss()
                    }
                } label: {
                    commitButtonLabel
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
        .onAppear {
            generatePreview(input: inputText)
        }
        .watch(value: canvasColorScheme) { _ in
            generatePreview(input: inputText)
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            titleLabel
                .font(.title2.weight(.semibold))
            Spacer()
        }
    }

    @ViewBuilder
    private var titleLabel: some View {
        switch mode {
            case .insert:
                Text(.localizable(.toolbarLatexMathInsertSheetTitle))
            case .edit:
                Text(.localizable(.toolbarEdit)) + Text(" ") + Text(.localizable(.toolbarLatexMath))
        }
    }

    @ViewBuilder
    private var commitButtonLabel: some View {
        switch mode {
            case .insert:
                Text(.localizable(.toolbarLatexMathButtonInsert))
            case .edit:
                Text(.localizable(.generalButtonSave))
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
            let renderedSVG = try LatexMathSVGRenderer.render(
                from: input,
                foregroundColor: selectedSVGColor
            )
            let tempDir = FileManager.default.temporaryDirectory
            let svgFilename = "\(UUID()).svg"
            
            let svgURL = tempDir.appendingPathComponent(svgFilename, conformingTo: .svg)
            try renderedSVG.svg.data(using: .utf8)?.write(to: svgURL)
            
            self.svgContent = renderedSVG
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
