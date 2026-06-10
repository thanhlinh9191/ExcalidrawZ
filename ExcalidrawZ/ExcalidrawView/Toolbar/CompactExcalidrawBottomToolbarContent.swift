//
//  CompactExcalidrawBottomToolbarContent.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/07.
//

#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

import ChocofordUI
import LLMKit
import SFSafeSymbols
import UIKit

struct CompactExcalidrawBottomToolbarContent: ToolbarContent {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass

    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var toolState: ToolState
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var aiChatState: AIChatState
    @EnvironmentObject private var llmState: LLMStateObject
    @ObservedObject private var aiChatPreferences = AIChatPreferences.shared

    private var activeCoordinator: ExcalidrawCanvasView.Coordinator? {
        switch fileState.currentActiveFile {
            case .collaborationFile:
                fileState.excalidrawCollaborationWebCoordinator ?? toolState.excalidrawWebCoordinator
            default:
                fileState.excalidrawWebCoordinator ?? toolState.excalidrawWebCoordinator
        }
    }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            if fileState.currentActiveFile != nil {
                if toolState.inDragMode {
                    if layoutState.isCompactAIChatToolbarPresented,
                       canPresentCompactAIChatToolbarInput {
                        // AI Chat
                        if compactAIChatIsReplying {
                            Spacer(minLength: 0)
                        } else {
                            compactAIChatToolbarAttachmentMenu
                            Spacer(minLength: 0)
                            compactAIChatToolbarPlaceholder
                                .frame(maxWidth: .infinity)
                            Spacer(minLength: 0)
                        }
                        if !compactAIChatIsReplying || compactAIChatShowsStopButton {
                            compactAIChatToolbarCloseButton
                                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        }
                    } else {
                        compactDragModeControls
                    }
                } else if let activatedTool = toolState.activatedTool, activatedTool != .cursor {
                    activeToolControls(activatedTool)
                } else {
                    cursorToolControls
                }
            }
        }
    }

    @ViewBuilder
    private func activeToolControls(_ activatedTool: ExcalidrawTool) -> some View {
        Text(activatedTool.localization)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
        Button {
            if activatedTool == .arrow {
                Task {
                    try? await toolState.excalidrawWebCoordinator?.toggleToolbarAction(key: "\u{1B}")
                }
            }
            toolState.setActivedTool(.cursor)
        } label: {
            Label(.localizable(.generalButtonCancel), systemSymbol: .checkmark)
        }
        .modernButtonStyle(style: .glassProminent, shape: .circle)
    }

    @ViewBuilder
    private var cursorToolControls: some View {
        HStack(spacing: 20) {
            Button {
                toolState.setActivedTool(.freedraw)
            } label: {
                Label(.localizable(.toolbarDraw), systemSymbol: .pencilAndOutline)
            }

            Spacer()

            Menu {
                shapeAndToolMenuItems
            } label: {
                if toolState.activatedTool == .cursor {
                    Label(.localizable(.toolbarShapesAndTools), systemSymbol: .squareOnCircle)
                } else {
                    activeShape()
                        .foregroundStyle(Color.accentColor)
                }
            }
            .menuOrder(.fixed)

            Spacer()

            ExcalidrawToolbarMoreToolsMenu()

            Spacer()

            if toolState.activatedTool == .cursor {
                if let activeCoordinator {
                    CursorModeTrailingButton(coordinator: activeCoordinator) {
                        toolState.setActivedTool(.hand)
                    }
                } else {
                    Button {
                        toolState.setActivedTool(.hand)
                    } label: {
                        Text(.localizable(.generalButtonDone))
                    }
                }
            } else {
                Button {
                    toolState.setActivedTool(.cursor)
                } label: {
                    Text(.localizable(.generalButtonCancel))
                }
            }
        }
    }

    @ViewBuilder
    private var compactDragModeControls: some View {
        compactStatusBar
        
        Spacer(minLength: 0)

        ViewThatFits(in: .horizontal) {
            compactExpandedInspectorControls
            compactCollapsedInspectorControls
        }

        Spacer(minLength: 0)
        
        compactEditButton
    }

    @ViewBuilder
    private var compactExpandedInspectorControls: some View {
        HStack(spacing: 8) {
            compactInspectorTabButton(
                tab: .preference,
                icon: .sliderHorizontal3,
                title: String(localizable: .canvasPreferencesTitle)
            )
            compactInspectorTabButton(
                tab: .search,
                icon: .magnifyingglass,
                title: String(localizable: .searchButtonTitle)
            )
            .keyboardShortcut("f", modifiers: .command)
            compactInspectorTabButton(
                tab: .library,
                icon: .book,
                title: String(localizable: .librariesTitle)
            )
            compactInspectorTabButton(
                tab: .history,
                icon: .clockArrowCirclepath,
                title: String(localizable: .checkpoints)
            )
            compactInspectorTabButton(
                tab: .aiChat,
                icon: .sparkles,
                title: "AI Chat",
                action: toggleCompactAIChatPresentation
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var compactCollapsedInspectorControls: some View {
        HStack(spacing: 20) {
            compactInspectorTabButton(
                tab: .library,
                icon: .book,
                title: String(localizable: .librariesTitle)
            )
            compactInspectorTabButton(
                tab: .aiChat,
                icon: .sparkles,
                title: "AI Chat",
                action: toggleCompactAIChatPresentation
            )
            compactInspectorTabsMenu()
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var compactStatusBar: some View {
        if let activeFile = fileState.currentActiveFile {
            FileICloudSyncStatusIndicator(file: activeFile)
                .frame(width: 28, height: 28)
        }
    }

    @ViewBuilder
    private var compactAIChatToolbarAttachmentMenu: some View {
        CompactAIChatToolbarAttachmentMenu {
            layoutState.enterCompactAIChatInputEditing()
        }
    }

    @ViewBuilder
    private var compactAIChatToolbarPlaceholder: some View {
        CompactAIChatToolbarPlaceholderButton(draftState: compactAIChatDraftState) {
            layoutState.enterCompactAIChatInputEditing()
        }
    }

    @ViewBuilder
    private var compactAIChatToolbarCloseButton: some View {
        Button {
            if compactAIChatShowsStopButton {
                stopCompactAIChatGeneration()
            } else {
                layoutState.exitCompactAIChatToolbar()
            }
        } label: {
            ZStack {
                if compactAIChatShowsStopButton {
                    Image(systemSymbol: .stopFill)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                } else {
                    Image(systemSymbol: .xmark)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
                .font(.system(size: 16, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .foregroundStyle(compactAIChatShowsStopButton ? Color.accentColor : Color.primary)
        .buttonStyle(.plain)
        .help(compactAIChatToolbarTrailingTitle)
        .animation(.smooth(duration: 0.2), value: compactAIChatShowsStopButton)
    }

    @ViewBuilder
    private var compactEditButton: some View {
        Button {
            if case .file(let file) = fileState.currentActiveFile, file.inTrash {
                layoutState.isResotreAlertIsPresented.toggle()
            } else {
                toolState.setActivedTool(.cursor)
            }
        } label: {
            Label(.localizable(.toolbarEdit), systemSymbol: .pencil)
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
        }
        .modernButtonStyle(style: .glassProminent, size: .small, shape: .circle)
        .help(String(localizable: .toolbarEdit))
    }

    @ViewBuilder
    private func compactInspectorTabButton(
        tab: LayoutState.InspectorTab,
        icon: SFSymbol,
        title: String,
        action: (() -> Void)? = nil
    ) -> some View {
        let isDisabled = compactInspectorTabIsDisabled(tab)
        let isActive = compactInspectorTabIsActive(tab)

        Button {
            guard !isDisabled else { return }
            if let action {
                action()
            } else {
                layoutState.toggleInspector(tab)
            }
        } label: {
            Label(title, systemSymbol: icon)
                .labelStyle(.iconOnly)
                .font(.system(size: 16))
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .help(title)
        .opacity(isDisabled && !isActive ? 0.55 : 1)
        .allowsHitTesting(!isDisabled)
    }

    @ViewBuilder
    private func compactInspectorTabsMenu() -> some View {
        Menu {
            compactInspectorTabMenuButton(
                tab: .preference,
                icon: .sliderHorizontal3,
                title: String(localizable: .canvasPreferencesTitle)
            )
            compactInspectorTabMenuButton(
                tab: .search,
                icon: .magnifyingglass,
                title: String(localizable: .searchButtonTitle)
            )
            .keyboardShortcut("f", modifiers: .command)
            compactInspectorTabMenuButton(
                tab: .history,
                icon: .clockArrowCirclepath,
                title: String(localizable: .checkpoints)
            )
        } label: {
            Label(.localizable(.generalButtonMore), systemSymbol: .ellipsis)
                .labelStyle(.iconOnly)
                .font(.system(size: 16))
                .foregroundStyle(compactCollapsedInspectorTabsContainActive ? Color.accentColor : Color.primary)
        }
        .fixedSize()
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help(String(localizable: .generalButtonMore))
        .menuOrder(.fixed)
    }

    @ViewBuilder
    private func compactInspectorTabMenuButton(
        tab: LayoutState.InspectorTab,
        icon: SFSymbol,
        title: String
    ) -> some View {
        let isDisabled = compactInspectorTabIsDisabled(tab)
        Button {
            guard !isDisabled else { return }
            layoutState.toggleInspector(tab)
        } label: {
            Label(title, systemSymbol: icon)
        }
        .disabled(isDisabled)
    }

    private var compactCollapsedInspectorTabsContainActive: Bool {
        [LayoutState.InspectorTab.preference, .search, .history].contains { tab in
            compactInspectorTabIsActive(tab)
        }
    }

    private func compactInspectorTabIsDisabled(_ tab: LayoutState.InspectorTab) -> Bool {
        switch tab {
            case .history:
                return fileState.currentActiveFile == nil
            default:
                return false
        }
    }

    private func compactInspectorTabIsActive(_ tab: LayoutState.InspectorTab) -> Bool {
        if tab == .aiChat, layoutState.isCompactAIChatToolbarPresented {
            return true
        }
        if tab == .aiChat, layoutState.isAIChatIslandMode {
            return true
        }
        return layoutState.isInspectorPresented && layoutState.activeInspectorTab == tab
    }

    private var canPresentCompactAIChatToolbarInput: Bool {
        containerHorizontalSizeClass == .compact &&
            AIChatAvailability.isAvailable &&
            aiChatPreferences.isAIEnabled &&
            !fileState.currentActiveFileIsInTrash
    }

    private var compactAIChatDraftState: AIChatPromptDraftState {
        aiChatState.promptDraftState(
            conversationID: fileState.aiChatConversationID,
            fileScope: fileState.currentActiveFile?.aiConversationFileScope
        )
    }

    private var compactAIChatIsGenerating: Bool {
        guard let conversationID = fileState.aiChatConversationID else { return false }
        return llmState.isRunning(conversationID: conversationID)
    }

    private var compactAIChatIsReplying: Bool {
        compactAIChatIsGenerating || layoutState.isCompactAIChatReplyTickerVisible
    }

    private var compactAIChatShowsStopButton: Bool {
        compactAIChatIsGenerating || layoutState.isCompactAIChatReplyStartPending
    }

    private var compactAIChatToolbarTrailingTitle: String {
        compactAIChatShowsStopButton ? "Stop AI generation" : String(localizable: .generalButtonClose)
    }

    private func stopCompactAIChatGeneration() {
        let wasGenerating = compactAIChatIsGenerating
        layoutState.isCompactAIChatReplyStartPending = false
        guard let conversationID = fileState.aiChatConversationID else {
            layoutState.isCompactAIChatReplyTickerVisible = false
            return
        }
        llmState.cancelGeneration(conversationID: conversationID)
        aiChatState.markGenerationCancelled(conversationID: conversationID)
        if !wasGenerating {
            layoutState.isCompactAIChatReplyTickerVisible = false
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            aiChatState.pendingQueue.removeAll()
        }
    }

    private func toggleCompactAIChatPresentation() {
        if layoutState.isCompactAIChatToolbarPresented {
            layoutState.exitCompactAIChatToolbar()
        } else if canPresentCompactAIChatToolbarInput {
            if !toolState.inDragMode {
                toolState.setActivedTool(.hand)
            }
            layoutState.enterCompactAIChatInputEditing()
        } else if layoutState.isAIChatIslandMode {
            layoutState.isAIChatIslandMode = false
        } else {
            layoutState.toggleInspector(.aiChat)
        }
    }

    @ViewBuilder
    private var shapeAndToolMenuItems: some View {
        Button {
            toolState.setActivedTool(.rectangle)
        } label: {
            Label(.localizable(.toolbarRectangle), systemSymbol: .rectangle)
        }
        Button {
            toolState.setActivedTool(.diamond)
        } label: {
            Label(.localizable(.toolbarDiamond), systemSymbol: .diamond)
        }
        Button {
            toolState.setActivedTool(.ellipse)
        } label: {
            Label(.localizable(.toolbarEllipse), systemSymbol: .circle)
        }
        Button {
            toolState.setActivedTool(.arrow)
        } label: {
            Label(.localizable(.toolbarArrow), systemSymbol: .lineDiagonalArrow)
        }
        Button {
            toolState.setActivedTool(.line)
        } label: {
            Label(.localizable(.toolbarLine), systemSymbol: .lineDiagonal)
        }
        Button {
            toolState.setActivedTool(.text)
        } label: {
            Label(.localizable(.toolbarText), systemSymbol: .characterTextbox)
        }
        Button {
            toolState.setActivedTool(.image)
        } label: {
            Label(.localizable(.toolbarInsertImage), systemSymbol: .photoOnRectangle)
        }

        Divider()

        Button {
            toolState.setActivedTool(.eraser)
        } label: {
            if #available(iOS 16.0, *) {
                Label(.localizable(.toolbarEraser), systemSymbol: .eraser)
            } else {
                Label(.localizable(.toolbarEraser), systemSymbol: .pencilSlash)
            }
        }
        Button {
            toolState.setActivedTool(.laser)
        } label: {
            Label(.localizable(.toolbarLaser), systemSymbol: .cursorarrowRays)
        }
        Button {
            toolState.setActivedTool(.frame)
        } label: {
            Label(.localizable(.toolbarFrame), systemSymbol: .grid)
        }
        Button {
            toolState.setActivedTool(.webEmbed)
        } label: {
            Label(.localizable(.toolbarWebEmbed), systemSymbol: .chevronLeftForwardslashChevronRight)
        }
        Button {
            toolState.setActivedTool(.magicFrame)
        } label: {
            Label(.localizable(.toolbarMagicFrame), systemSymbol: .wandAndStarsInverse)
        }
    }

    @ViewBuilder
    private func activeShape() -> some View {
        switch toolState.activatedTool {
            case .rectangle:
                Label(.localizable(.toolbarRectangle), systemSymbol: .rectangle)
            case .diamond:
                Label(.localizable(.toolbarDiamond), systemSymbol: .diamond)
            case .ellipse:
                Label(.localizable(.toolbarEllipse), systemSymbol: .ellipsis)
            case .arrow:
                Label(.localizable(.toolbarArrow), systemSymbol: .lineDiagonalArrow)
            case .line:
                Label(.localizable(.toolbarLine), systemSymbol: .lineDiagonal)
            default:
                Label(.localizable(.toolbarShapes), systemSymbol: .squareOnCircle)
        }
    }
}

private struct CompactAIChatToolbarPlaceholderButton: View {
    @ObservedObject var draftState: AIChatPromptDraftState

    let onBeginEditing: () -> Void

    private var displayText: String {
        let text = draftState.text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? String(localizable: .aiChatInputPlaceholder) : text
    }

    var body: some View {
        Button {
            onBeginEditing()
        } label: {
            Label {
                Text(displayText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } icon: {
                Image(systemSymbol: .sparkles)
            }
            .labelStyle(.titleAndIcon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help("AI Chat")
    }
}

struct CompactExcalidrawBottomToolbarStateModifier: ViewModifier {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) private var alertToast

    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var toolState: ToolState
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var lockedContentState: LockedContentStateStore
    @ObservedObject private var aiChatPreferences = AIChatPreferences.shared

    private var canPresentCompactAIChatToolbarInput: Bool {
        containerHorizontalSizeClass == .compact &&
            lockedContentState.activeFileLockState != .locked &&
            fileState.currentActiveFile != nil &&
            AIChatAvailability.isAvailable &&
            aiChatPreferences.isAIEnabled &&
            !fileState.currentActiveFileIsInTrash
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: toolState.activatedTool, debounce: 0.05) { newValue in
                guard containerHorizontalSizeClass == .compact else { return }
                syncActiveTool(newValue)
            }
            .watch(value: toolState.inDragMode) { inDragMode in
                guard !inDragMode else { return }
                layoutState.exitCompactAIChatToolbar()
            }
            .watch(value: fileState.currentActiveFile?.id) { _ in
                layoutState.exitCompactAIChatToolbar()
            }
            .watch(value: lockedContentState.activeFileLockState) { lockState in
                guard lockState == .locked else { return }
                layoutState.exitCompactAIChatToolbar()
            }
            .watch(value: canPresentCompactAIChatToolbarInput) { canPresent in
                guard !canPresent else { return }
                layoutState.exitCompactAIChatToolbar()
            }
            .watch(value: layoutState.isCompactAIChatToolbarPresented) { isPresented in
                guard isPresented else { return }
                guard canPresentCompactAIChatToolbarInput else {
                    layoutState.exitCompactAIChatToolbar()
                    return
                }
                if !toolState.inDragMode {
                    toolState.setActivedTool(.hand)
                }
            }
    }

    private func syncActiveTool(_ newValue: ExcalidrawTool?) {
        if newValue == nil {
            toolState.setActivedTool(.cursor)
        }

        guard let tool = newValue else { return }
        let webCoordinator = toolState.excalidrawWebCoordinator

        guard tool != webCoordinator?.lastTool else { return }
        Task {
            do {
                try await toolState.toggleTool(tool)
            } catch {
                alertToast(error)
            }
        }
    }
}

private struct CompactAIChatToolbarAttachmentMenu: View {
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var aiChatState: AIChatState

    @State private var isImagePickerPresented = false
    @State private var selectedPhotoPickerItems: [PhotosPickerItem] = []
    @State private var isCameraPickerPresented = false

    let onAttachImages: () -> Void

    private var promptDraftKey: String {
        aiChatState.promptDraftKey(
            conversationID: fileState.aiChatConversationID,
            fileScope: fileState.currentActiveFile?.aiConversationFileScope
        )
    }

    var body: some View {
        Menu {
            Button {
                isImagePickerPresented = true
            } label: {
                Label(.localizable(.exportSheetButtonFile), systemSymbol: .doc)
            }

            PhotosPicker(
                selection: $selectedPhotoPickerItems,
                matching: .images
            ) {
                Label(.localizable(.aiChatInputAttachmentMenuItemPhotoLibrary), systemSymbol: .photoOnRectangle)
            }

            Button {
                isCameraPickerPresented = true
            } label: {
                Label(.localizable(.aiChatInputAttachmentMenuItemCamera), systemSymbol: .camera)
            }
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
        } label: {
            Label(.localizable(.aiChatInputAttachmentMenuButtonAdd), systemSymbol: .plus)
                .labelStyle(.iconOnly)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(fileState.isAIChatConversationLoading || fileState.currentActiveFileIsInTrash)
        .fileImporter(
            isPresented: $isImagePickerPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            handleImagePickerResult(result)
        }
        .sheet(isPresented: $isCameraPickerPresented) {
            AIChatCameraImagePicker { image in
                handleCameraImage(image)
            }
            .ignoresSafeArea()
        }
        .watch(value: selectedPhotoPickerItems.map(\.itemIdentifier)) { _ in
            handlePhotoPickerItems(selectedPhotoPickerItems)
        }
    }

    @MainActor
    private func handleImagePickerResult(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        let images = urls.compactMap { AIChatAttachmentImageImporter.pendingImage(from: $0) }
        appendImages(images)
    }

    @MainActor
    private func handlePhotoPickerItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            let images = await AIChatAttachmentImageImporter.pendingImages(from: items)
            await MainActor.run {
                selectedPhotoPickerItems = []
                appendImages(images)
            }
        }
    }

    @MainActor
    private func handleCameraImage(_ image: UIImage?) {
        guard let image else { return }
        appendImages([
            AIChatAttachmentImageImporter.pendingImage(from: image)
        ])
    }

    @MainActor
    private func appendImages(_ images: [PendingPastedImage]) {
        guard !images.isEmpty else { return }
        aiChatState.requestAppendDraftImages(images, draftKey: promptDraftKey)
        onAttachImages()
    }
}
#endif
