//
//  CompactExcalidrawBottomToolbarContent.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/07.
//

#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

import ChocofordUI
import SFSafeSymbols
import UIKit

struct CompactExcalidrawBottomToolbarContent: ToolbarContent {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass

    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var toolState: ToolState
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var aiChatState: AIChatState
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
                        CompactAIChatToolbarAttachmentMenu()
                        Spacer(minLength: 0)
                        compactAIChatToolbarInput
                        Spacer(minLength: 0)
                        compactAIChatToolbarCloseButton
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

    private var compactAIChatConversationIDBinding: Binding<String?> {
        Binding(
            get: { fileState.aiChatConversationID },
            set: { fileState.aiChatConversationID = $0 }
        )
    }

    @ViewBuilder
    private var compactAIChatToolbarInput: some View {
        PromptInputView(
            conversationID: compactAIChatConversationIDBinding,
            pendingQueue: $aiChatState.pendingQueue,
            style: .compactIOSToolbarText
        )
        .disabled(fileState.isAIChatConversationLoading || fileState.currentActiveFileIsInTrash)
    }

    @ViewBuilder
    private var compactAIChatToolbarCloseButton: some View {
        Button {
            layoutState.exitCompactAIChatToolbar()
        } label: {
            Label(.localizable(.generalButtonClose), systemSymbol: .xmark)
                .labelStyle(.iconOnly)
                .font(.system(size: 16))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localizable: .generalButtonClose))
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

    private func toggleCompactAIChatPresentation() {
        if layoutState.isCompactAIChatToolbarPresented {
            layoutState.exitCompactAIChatToolbar()
        } else if canPresentCompactAIChatToolbarInput {
            if !toolState.inDragMode {
                toolState.setActivedTool(.hand)
            }
            layoutState.enterCompactAIChatToolbar()
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

struct CompactExcalidrawBottomToolbarStateModifier: ViewModifier {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass

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
}

private struct CompactAIChatToolbarAttachmentMenu: View {
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var aiChatState: AIChatState

    @State private var isImagePickerPresented = false

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
                Label(.localizable(.aiChatInputAttachmentMenuItemImage), systemSymbol: .photo)
            }
        } label: {
            Label(.localizable(.aiChatInputAttachmentMenuItemImage), systemSymbol: .plus)
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
    }

    @MainActor
    private func handleImagePickerResult(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        let images = urls.compactMap { pendingImage(from: $0) }
        aiChatState.requestAppendDraftImages(images, draftKey: promptDraftKey)
    }

    private func pendingImage(from url: URL) -> PendingPastedImage? {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data)
        else { return nil }
        return PendingPastedImage(id: UUID(), image: image)
    }
}
#endif
