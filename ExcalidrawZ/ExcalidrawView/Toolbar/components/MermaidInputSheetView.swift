//
//  MermaidInputSheetView.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/03.
//

import SwiftUI
import ChocofordUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct MermaidInputSheetViewModifier: ViewModifier {
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState

    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                MermaidInputSheetView { definition in
                    do {
                        var options = ExcalidrawCore.MermaidInsertOptions()
                        options.focus = .enabled(true)
                        guard let coordinator = activeCoordinator else {
                            throw MermaidInputSheetError.noActiveCanvas
                        }
                        _ = try await coordinator.insertFromMermaid(definition, options: options)
                    } catch {
                        alertToast(error)
                        throw error
                    }
                }
            }
    }

    private var activeCoordinator: ExcalidrawCanvasView.Coordinator? {
        switch fileState.currentActiveFile {
            case .collaborationFile:
                fileState.excalidrawCollaborationWebCoordinator
            default:
                fileState.excalidrawWebCoordinator
        }
    }
}

struct MermaidInputSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var onInsert: (_ definition: String) async throws -> Void

    @State private var inputText = ""
    @State private var selectedPage: MermaidInputSheetPage = .input
    @State private var previewState: MermaidPreviewState = .idle
    @State private var previewImage: Image?
    @State private var previewTask: Task<Void, Never>?
    @State private var isInserting = false

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(.localizable(.toolbarMermaid))
                    .font(.title.bold())
                Spacer()
            }

            Picker("", selection: $selectedPage) {
                Text(.localizable(.mermaidInputSheetInputTab))
                    .tag(MermaidInputSheetPage.input)
                Text(.localizable(.mermaidInputSheetPreviewTab))
                    .tag(MermaidInputSheetPage.preview)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch selectedPage {
                    case .input:
                        inputEditor
                    case .preview:
                        previewContent
                }
            }
            .frame(minHeight: contentHeight)

            HStack {
                Spacer()
                Button {
                    previewTask?.cancel()
                    dismiss()
                } label: {
                    Text(.localizable(.generalButtonCancel))
                }
                Button {
                    insertMermaid()
                } label: {
                    if isInserting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(.localizable(.toolbarLatexMathButtonInsert))
                    }
                }
                .disabled(trimmedInput.isEmpty || isInserting || previewState == .loading)
                .modernButtonStyle(style: .borderedProminent)
            }
            .modernButtonStyle(size: .large, shape: .modern)
        }
        .padding()
        .watch(value: selectedPage) { newValue in
            if newValue == .preview {
                schedulePreview()
            }
        }
        .onChange(of: trimmedInput, debounce: 0.35) { _ in
            guard selectedPage == .preview else {
                previewState = .idle
                previewImage = nil
                return
            }
            schedulePreview()
        }
        .onDisappear {
            previewTask?.cancel()
        }
    }

    private var contentHeight: CGFloat {
        #if os(iOS)
        320
        #else
        280
        #endif
    }

    private var inputEditor: some View {
        TextEditor(text: $inputText)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollContentBackground(.hidden)
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            }
            .overlay(alignment: .topLeading) {
                if inputText.isEmpty {
                    Text(.localizable(.mermaidInputSheetPlaceholder))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
    }

    private var previewContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white)

            switch previewState {
                case .idle:
                    Text(.localizable(.mermaidInputSheetPreviewEmpty))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                case .loading:
                    ProgressView()
                        .controlSize(.regular)
                case .loaded:
                    if let previewImage {
                        previewImage
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(12)
                    } else {
                        Text(.localizable(.mermaidInputSheetPreviewUnavailable))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                case .failed(let message):
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
    }

    private func schedulePreview() {
        previewTask?.cancel()

        let definition = trimmedInput
        guard !definition.isEmpty else {
            previewState = .idle
            previewImage = nil
            return
        }

        previewState = .loading
        previewTask = Task {
            guard !Task.isCancelled else { return }
            await renderPreview(definition)
        }
    }

    @MainActor
    private func renderPreview(_ definition: String) async {
        do {
            let data = try await MermaidPreviewRenderer.renderPNGData(definition)
            guard !Task.isCancelled, definition == trimmedInput else { return }
            if let image = MermaidPreviewRenderer.image(from: data) {
                previewImage = image
                previewState = .loaded
            } else {
                previewImage = nil
                previewState = .loaded
            }
        } catch {
            guard !Task.isCancelled, definition == trimmedInput else { return }
            previewImage = nil
            previewState = .failed(error.localizedDescription)
        }
    }

    private func insertMermaid() {
        let definition = trimmedInput
        guard !definition.isEmpty, !isInserting else { return }
        isInserting = true
        Task { @MainActor in
            do {
                try await onInsert(definition)
                previewTask?.cancel()
                dismiss()
            } catch {
                isInserting = false
            }
        }
    }
}

#Preview {
    MermaidInputSheetView { _ in }
}

private enum MermaidInputSheetPage: Hashable {
    case input
    case preview
}

private enum MermaidPreviewState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

private enum MermaidInputSheetError: LocalizedError {
    case noActiveCanvas

    var errorDescription: String? {
        switch self {
            case .noActiveCanvas:
                String(localizable: .mermaidInputSheetNoActiveCanvasError)
        }
    }
}

private enum MermaidPreviewRenderer {
    @MainActor
    static func renderPNGData(_ definition: String) async throws -> Data {
        let coordinator = try await AIProposalSandbox.readyCoordinator()
        let result = try await coordinator.convertMermaidToExcalidraw(definition)
        let elements = try decodeElements(from: result.elements)
        let files = try decodeFiles(from: result.files)
        return try await coordinator.exportElementsToPNGData(
            elements: elements,
            files: files.isEmpty ? nil : files,
            colorScheme: .light
        )
    }

    @MainActor
    static func image(from data: Data) -> Image? {
        #if os(macOS)
        guard let platformImage = NSImage(data: data) else { return nil }
        return Image(nsImage: platformImage)
        #else
        guard let platformImage = UIImage(data: data) else { return nil }
        return Image(uiImage: platformImage)
        #endif
    }

    private static func decodeElements(
        from values: [ExcalidrawCore.JSONValue]
    ) throws -> [ExcalidrawElement] {
        let data = try JSONEncoder().encode(values)
        return try JSONDecoder().decode([ExcalidrawElement].self, from: data)
    }

    private static func decodeFiles(
        from values: [String: ExcalidrawCore.JSONValue]
    ) throws -> [String: ExcalidrawFile.ResourceFile] {
        let data = try JSONEncoder().encode(values)
        return try JSONDecoder().decode([String: ExcalidrawFile.ResourceFile].self, from: data)
    }
}
