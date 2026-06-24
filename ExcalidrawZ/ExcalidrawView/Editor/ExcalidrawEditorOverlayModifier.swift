//
//  ExcalidrawEditorOverlayModifier.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/27.
//

import SwiftUI

import ChocofordUI

/// Layers loading / empty / recover overlays on top of an `ExcalidrawCanvasView`.
struct ExcalidrawEditorOverlayModifier: ViewModifier {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.alertToast) var alertToast
    @Environment(\.containerHorizontalSizeClass) var containerHorizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    @EnvironmentObject var layoutState: LayoutState
    @EnvironmentObject private var fileState: FileState

    @Binding var loadingState: ExcalidrawCanvasView.LoadingState
    var hasFile: Bool

    @State private var isLoadingOverlayPresented = false
    @State private var isProgressViewPresented = false
    @State private var isSelectFilePlaceholderPresented = false
    @State private var progressPresentationTask: Task<Void, Never>?
    @State private var loadingOverlayDismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        ZStack(alignment: .center) {
            content
                .opacity(isLoadingOverlayPresented ? 0 : 1)
                .opacity(hasFile ? 1 : 0)
                .watch(value: loadingState, initial: true) { _, newVal in
                    updateProgressPresentation(for: newVal)
                }

            if containerHorizontalSizeClass != .compact {
                selectFilePlaceholderView()
            }

            if !hasFile {
                emptyFilePlaceholderview()
            }

            if isLoadingOverlayPresented {
                loadingOverlayBackground

                if isProgressViewPresented {
                    loadingIndicatorView
                }
            } else if case .file(let file) = fileState.currentActiveFile, file.inTrash {
                recoverOverlayView
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .transition(.opacity)
        .animation(.default, value: isProgressViewPresented)
        .onDisappear {
            progressPresentationTask?.cancel()
            progressPresentationTask = nil
            loadingOverlayDismissTask?.cancel()
            loadingOverlayDismissTask = nil
        }
    }

    private var loadingIndicatorView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
            Text(.localizable(.webViewLoadingText))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            if #available(macOS 26.0, iOS 26.0, *) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.clear, in: .rect(cornerRadius: 16))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
    }

    @ViewBuilder
    private var loadingOverlayBackground: some View {
        if let image = loadingCoverImage {
            Image(platformImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            fallbackLoadingOverlayBackground
        }
    }

    private var loadingCoverImage: PlatformImage? {
        guard hasFile,
              let activeFile = fileState.currentActiveFile else {
            return nil
        }
        return FileItemPreviewCache.shared.getPreviewCache(
            forID: activeFile.id,
            colorScheme: colorScheme
        )
    }

    @ViewBuilder
    private var fallbackLoadingOverlayBackground: some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            Rectangle()
                .fill(.windowBackground)
        } else {
            Rectangle()
                .fill(Color.windowBackgroundColor)
        }
    }

    private func updateProgressPresentation(for loadingState: ExcalidrawCanvasView.LoadingState) {
        progressPresentationTask?.cancel()
        progressPresentationTask = nil
        loadingOverlayDismissTask?.cancel()
        loadingOverlayDismissTask = nil

        guard loadingState == .loading else {
            if isProgressViewPresented {
                loadingOverlayDismissTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    guard !Task.isCancelled else { return }
                    isProgressViewPresented = false
                    isLoadingOverlayPresented = false
                    loadingOverlayDismissTask = nil
                }
            } else {
                isLoadingOverlayPresented = false
            }
            return
        }

        isLoadingOverlayPresented = true
        progressPresentationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            isProgressViewPresented = true
            progressPresentationTask = nil
        }
    }

    @ViewBuilder
    private var recoverOverlayView: some View {
        Rectangle()
            .opacity(0)
            .contentShape(Rectangle())
            .onTapGesture {
                layoutState.isResotreAlertIsPresented.toggle()
            }
            .alert(
                String(localizable: .deletedFileRecoverAlertTitle),
                isPresented: $layoutState.isResotreAlertIsPresented
            ) {
                Button(role: .cancel) {
                    layoutState.isResotreAlertIsPresented.toggle()
                } label: {
                    Text(.localizable(.deletedFileRecoverAlertButtonCancel))
                }

                Button(role: {
                    if #available(iOS 26.0, macOS 26.0, *) {
                        return .confirm
                    } else {
                        return .none
                    }
                }()) {
                    if case .file(let currentFile) = fileState.currentActiveFile {
                        Task {
                            let context = viewContext
                            do {
                                try await fileState
                                    .recoverFile(fileID: currentFile.objectID, context: context)
                            } catch {
                                alertToast(error)
                            }
                        }
                    }
                } label: {
                    Text(.localizable(.deletedFileRecoverAlertButtonRecover))
                }
                .modernButtonStyle(style: .glassProminent)
            } message: {
                Text(.localizable(.deletedFileRecoverAlertMessage))
            }
    }

    @ViewBuilder
    private func selectFilePlaceholderView() -> some View {
        ZStack {
            if isSelectFilePlaceholderPresented {
                if #available(macOS 14.0, iOS 17.0, *) {
                    Rectangle()
                        .fill(.windowBackground)
                } else {
                    Rectangle()
                        .fill(Color.windowBackgroundColor)
                }
                ProgressView()
            }
        }
        .onChange(of: fileState.currentActiveFile == nil, debounce: 0.1) { newValue in
            isSelectFilePlaceholderPresented = newValue
        }
    }

    @ViewBuilder
    private func emptyFilePlaceholderview() -> some View {
        ZStack {
            if isSelectFilePlaceholderPresented {
                ZStack {
                    if #available(macOS 14.0, iOS 17.0, *) {
                        Rectangle()
                            .fill(.windowBackground)
                    } else {
                        Rectangle()
                            .fill(Color.windowBackgroundColor)
                    }

                    Text(.localizable(.excalidrawWebViewPlaceholderSelectFile))
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
                .transition(
                    .asymmetric(
                        insertion: .identity,
                        removal: .opacity.animation(.smooth.delay(0.2))
                    )
                )
            }
        }
        .animation(.default, value: isSelectFilePlaceholderPresented)
        .onChange(of: fileState.currentActiveFile == nil, debounce: 0.1) { newValue in
            isSelectFilePlaceholderPresented = newValue
        }
        .contentShape(Rectangle())
    }
}

extension View {
    /// Adds the editor's loading / empty / recover overlays around an `ExcalidrawCanvasView`.
    func excalidrawEditorOverlays(
        loadingState: Binding<ExcalidrawCanvasView.LoadingState>,
        hasFile: Bool
    ) -> some View {
        modifier(ExcalidrawEditorOverlayModifier(
            loadingState: loadingState,
            hasFile: hasFile
        ))
    }
}
