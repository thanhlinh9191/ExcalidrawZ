//
//  PromptInputView+CompactIOSIsland.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/05.
//

#if os(iOS)
import SwiftUI
import PhotosUI
import ChocofordUI
import SFSafeSymbols
import UIKit

extension PromptInputView {
    private var iOSIslandCircleControlLength: CGFloat { 44 }
    private var iOSIslandInlineControlLength: CGFloat { 34 }
    private var iOSIslandPrimaryActionLength: CGFloat { 42 }
    private var iOSIslandPrimaryActionIconLength: CGFloat { 18 }
    private var iOSIslandExpandedInputMinHeight: CGFloat { 44 }
    private var iOSIslandInputMaxHeight: CGFloat { 168 }
    private var iOSIslandFullscreenInputMinHeight: CGFloat { 220 }
    private var iOSIslandFullscreenInputMaxHeight: CGFloat { 520 }

    @ViewBuilder
    var iOSIslandInputContent: some View {
        let isExpanded = iOSIslandInputIsExpanded
        let isFullscreen = isIOSIslandFullscreenInputPresented
        let inputIsExpanded = isExpanded || isFullscreen

        VStack(alignment: .trailing, spacing: 5) {
            if !isFullscreen, !isExpanded {
                iOSIslandInlineSettings
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(alignment: .bottom, spacing: 7) {
                if !isFullscreen {
                    VStack(spacing: 7) {
                        if isExpanded {
                            iOSIslandSettingsMenu
                                .transition(.opacity.combined(with: .scale))
                        }

                        iOSIslandAttachmentMenu
                    }
                    .transition(.opacity.combined(with: .scale))
                }

                iOSIslandTextInputSurface(
                    isExpanded: inputIsExpanded,
                    minHeight: iOSIslandInputMinHeight(
                        isExpanded: isExpanded,
                        isFullscreen: isFullscreen
                    ),
                    maxTextAreaHeight: iOSIslandTextAreaMaxHeight(
                        isExpanded: inputIsExpanded,
                        isFullscreen: isFullscreen
                    ),
                    showsExpandButton: isExpanded && iOSIslandTextAreaIsOverflowing,
                    showsCollapseButton: isFullscreen,
                    tracksInlineHeight: !isFullscreen
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(.smooth(duration: 0.25), value: isIOSIslandFullscreenInputPresented)
    }

    var iOSIslandInputIsExpanded: Bool {
        return draftHasImages
            || (draftHasContent && !iOSIslandTextAreaIsSingleLine)
    }

    @ViewBuilder
    private func iOSIslandTextInputSurface(
        isExpanded: Bool,
        minHeight: CGFloat,
        maxTextAreaHeight: CGFloat,
        showsExpandButton: Bool,
        showsCollapseButton: Bool,
        tracksInlineHeight: Bool
    ) -> some View {
        let chromeHeight = iOSIslandInputChromeHeight(
            isExpanded: isExpanded,
            minHeight: minHeight,
            tracksInlineHeight: tracksInlineHeight
        )

        PromptDraftInputField(
            draftKey: promptDraftKey,
            draftState: promptDraftState,
            showsAttachments: true,
            sendRequestToken: draftSendRequestToken,
            maxTextAreaHeight: maxTextAreaHeight,
            textInsets: iOSIslandTextInsets(isExpanded: isExpanded),
            linesOverflow: $iOSIslandTextAreaIsOverflowing,
            onTextAreaSingleLineChanged: { isSingleLine in
                iOSIslandTextAreaIsSingleLine = isSingleLine
                if isSingleLine {
                    iOSIslandDraftFieldHeight = 0
                    iOSIslandTextAreaIsOverflowing = false
                }
            },
            focus: $isInputFocused,
            autofocus: focusOnAppear,
            onSubmit: { text, images in
                submitCompactIOSIslandDraft(prompt: text, pastedImages: images)
            },
            onPaste: handlePastedItem,
            onSummaryChange: { hasContent, hasImages in
                updateDraftSummary(hasContent: hasContent, hasImages: hasImages)
            }
        )
        .id(ObjectIdentifier(promptDraftState))
        .transaction { transaction in
            transaction.animation = nil
        }
        .modifier(IOSIslandDraftHeightReader(
            isEnabled: tracksInlineHeight,
            height: $iOSIslandDraftFieldHeight
        ))
        .frame(
            minHeight: minHeight,
            alignment: isExpanded ? .bottom : .center
        )
        .frame(maxHeight: chromeHeight, alignment: isExpanded ? .bottom : .center)
        .frame(maxWidth: .infinity, alignment: .bottom)
        .background(alignment: .bottom) {
            iOSIslandTextInputBackground(isExpanded: isExpanded)
                .frame(height: chromeHeight)
                .animation(.smooth(duration: 0.18), value: chromeHeight)
        }
        .clipShape(iOSIslandTextInputShape(isExpanded: isExpanded))
        .overlay(alignment: isExpanded ? .bottomTrailing : .trailing) {
            iOSIslandPrimaryActionButton
                .padding(.trailing, 2)
                .padding(.bottom, isExpanded ? 8 : 0)
        }
        .overlay(alignment: .topTrailing) {
            if showsCollapseButton {
                iOSIslandCollapseFullscreenButton
                    .padding(.top, 6)
                    .padding(.trailing, 6)
                    .transition(.opacity.combined(with: .scale))
            } else if showsExpandButton {
                iOSIslandExpandFullscreenButton
                    .padding(.top, 6)
                    .padding(.trailing, 6)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .contentShape(iOSIslandTextInputShape(isExpanded: isExpanded))
        .matchedGeometryEffect(id: "iOSIslandTextInputSurface", in: iOSIslandInputNamespace)
    }

    private func iOSIslandInputMinHeight(isExpanded: Bool, isFullscreen: Bool) -> CGFloat {
        if isFullscreen {
            return iOSIslandFullscreenInputMinHeight
        }

        return isExpanded ? iOSIslandExpandedInputMinHeight : iOSIslandCircleControlLength
    }

    private func iOSIslandInputChromeHeight(
        isExpanded: Bool,
        minHeight: CGFloat,
        tracksInlineHeight: Bool
    ) -> CGFloat {
        guard tracksInlineHeight, iOSIslandDraftFieldHeight > 0 else {
            return minHeight
        }

        return max(minHeight, iOSIslandDraftFieldHeight)
    }

    private func iOSIslandTextAreaMaxHeight(isExpanded: Bool, isFullscreen: Bool = false) -> CGFloat {
        if isFullscreen {
            return iOSIslandFullscreenInputMaxHeight
        }

        return isExpanded ? iOSIslandInputMaxHeight : iOSIslandCircleControlLength
    }

    private func iOSIslandTextInsets(isExpanded: Bool) -> EdgeInsets {
        EdgeInsets(
            top: isExpanded ? 16 : 10,
            leading: 24,
            bottom: isExpanded ? 16 : 10,
            trailing: iOSIslandPrimaryActionLength + 14
        )
    }

    @ViewBuilder
    private var iOSIslandExpandFullscreenButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) {
                isIOSIslandFullscreenInputPresented = true
            }
            refocusIOSIslandInput()
        } label: {
            iOSIslandCircleLabel(length: 32) {
                Image(systemSymbol: .arrowUpLeftAndArrowDownRight)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iOSIslandCollapseFullscreenButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) {
                if iOSIslandTextAreaIsSingleLine {
                    iOSIslandDraftFieldHeight = 0
                }
                isIOSIslandFullscreenInputPresented = false
            }
            refocusIOSIslandInput()
        } label: {
            iOSIslandCircleLabel(length: iOSIslandInlineControlLength) {
                Image(systemSymbol: .arrowDownRightAndArrowUpLeft)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
    }

    private func refocusIOSIslandInput() {
        isInputFocused = true
        Task { @MainActor in
            await Task.yield()
            isInputFocused = true
        }
    }

    @MainActor
    private func submitCompactIOSIslandDraft(
        prompt: String,
        pastedImages: [PendingPastedImage]
    ) -> Bool {
        let didSubmit = submitDraft(prompt: prompt, pastedImages: pastedImages)
        if didSubmit {
            onSuccessfulSubmit?()
            if dismissKeyboardOnSuccessfulSubmit {
                isInputFocused = false
            }
        }
        return didSubmit
    }

    @ViewBuilder
    private func iOSIslandTextInputBackground(isExpanded: Bool) -> some View {
        let shape = iOSIslandTextInputShape(isExpanded: isExpanded)

        if #available(iOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
        } else {
            shape
                .fill(.regularMaterial)
        }
    }

    private func iOSIslandTextInputShape(isExpanded: Bool) -> AnyShape {
        if isExpanded {
            AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            AnyShape(Capsule())
        }
    }

    @ViewBuilder
    var iOSIslandAttachmentMenu: some View {
        AIChatAttachmentMenu(
            canInsertImages: canInsertImages,
            isFileImporterPresented: $isImagePickerPresented,
            selectedPhotoPickerItems: $iOSSelectedPhotoPickerItems,
            isPhotoLibraryPickerPresented: $isIOSPhotoLibraryPickerPresented,
            isCameraPickerPresented: $isIOSCameraPickerPresented,
            onBeginPickerPresentation: {
                beginIOSAttachmentPickerPresentation()
            },
            onFilePickerDismiss: {
                finishIOSAttachmentPickerPresentation()
            },
            onPhotoPickerDismiss: {
                finishIOSAttachmentPickerPresentation()
            },
            onCameraPickerDismiss: {
                finishIOSAttachmentPickerPresentation()
            },
            onImagesPicked: appendAttachmentImages,
            onImageInputUnavailable: showImageInputUnavailableToast
        ) {
            iOSIslandCircleLabel {
                Image(systemSymbol: .plus)
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    var iOSIslandInlineSettings: some View {
        HStack(spacing: 5) {
            iOSIslandFileAccessButton

            iOSIslandModelPicker

            if showsCompactIOSFullChatButton {
                iOSIslandFullChatButton
            }

            if isInputFocused {
                iOSIslandDismissKeyboardButton
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.smooth(duration: 0.18), value: isInputFocused)
    }

    @ViewBuilder
    var iOSIslandPrimaryActionButton: some View {
        Button {
            if primaryActionIsStop {
                cancelCurrentGeneration()
            } else {
                draftSendRequestToken += 1
            }
        } label: {
            if #available(iOS 17.0, *) {
                Image(systemSymbol: primaryActionIsStop ? .stopFill : .arrowUp)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(
                        width: iOSIslandPrimaryActionIconLength,
                        height: iOSIslandPrimaryActionIconLength
                    )
                    .contentTransition(.symbolEffect(.replace))
            } else {
                Image(systemSymbol: primaryActionIsStop ? .stopFill : .arrowUp)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(
                        width: iOSIslandPrimaryActionIconLength,
                        height: iOSIslandPrimaryActionIconLength
                    )
            }
        }
        .modernButtonStyle(style: .glassProminent, size: .regular, shape: .circle)
        .frame(
            width: iOSIslandPrimaryActionLength,
            height: iOSIslandPrimaryActionLength
        )
        .clipShape(Circle())
        .contentShape(Circle())
        .disabled(!primaryActionIsStop && !hasInputText)
    }

    @ViewBuilder
    var iOSIslandFileAccessButton: some View {
        Button {
            toggleAIFileAccess()
        } label: {
            iOSIslandCircleLabel(length: iOSIslandInlineControlLength) {
                Image(systemSymbol: activeFileAccessAllowsAI ? .eye : .eyeSlash)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .foregroundStyle(activeFileAccessAllowsAI ? .primary : .secondary)
        .tint(activeFileAccessAllowsAI ? .accentColor : .secondary.opacity(0.75))
        .buttonStyle(.plain)
        .disabled(!hasActiveFileForAIAccessControl || !canToggleAIFileAccess)
        .modifier(FeatureDiscoveryTipModifier(
            kind: .aiFileVisibility,
            isEnabled: hasActiveFileForAIAccessControl && canToggleAIFileAccess
        ))
    }

    @ViewBuilder
    var iOSIslandModelPicker: some View {
        Menu {
            modelTierPickerButtons()
        } label: {
            iOSIslandCircleLabel(length: iOSIslandInlineControlLength) {
                Text(iOSIslandModelPickerTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .monospaced()
            }
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .disabled(modelPickerTiers.isEmpty)
    }

    @MainActor
    var iOSIslandModelPickerTitle: String {
        activeModelProfileOption?.tier.iOSIslandShortLabel ?? "..."
    }

    @ViewBuilder
    var iOSIslandFullChatButton: some View {
        Button {
            enterIOSIslandFullChat()
        } label: {
            iOSIslandCircleLabel(length: iOSIslandInlineControlLength) {
                Image(systemSymbol: .rectangleExpandVertical)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
        .help(.localizable(.aiChatButtonFullscreen))
        .accessibilityLabel(Text(localizable: .aiChatButtonFullscreen))
    }

    @ViewBuilder
    var iOSIslandDismissKeyboardButton: some View {
        Button {
            isInputFocused = false
        } label: {
            iOSIslandCircleLabel(length: iOSIslandInlineControlLength) {
                Image(systemSymbol: .keyboardChevronCompactDown)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
    }

    private func enterIOSIslandFullChat() {
        isInputFocused = false
        isIOSIslandFullscreenInputPresented = false
        layoutState.presentCompactAIChatFullChat()
    }

    @ViewBuilder
    private func iOSIslandCircleLabel<Content: View>(
        length: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let resolvedLength = length ?? iOSIslandCircleControlLength

        content()
            .frame(
                width: resolvedLength,
                height: resolvedLength
            )
            .background {
                iOSIslandCircleBackground
            }
            .clipShape(Circle())
            .contentShape(Circle())
    }

    @ViewBuilder
    private var iOSIslandCircleBackground: some View {
        if #available(iOS 26.0, *) {
            Circle()
                .fill(.clear)
                .glassEffect(.regular, in: Circle())
        } else {
            Circle()
                .fill(.regularMaterial)
        }
    }

    @ViewBuilder
    var iOSIslandSettingsMenu: some View {
        Menu {
            if showsIOSCompactContextMenuItem {
                Button {
                    compactCurrentContext()
                } label: {
                    if #available(iOS 18.0, *) {
                        Label(.localizable(.aiChatButtonCompactContext), systemSymbol: .arrowTrianglehead2ClockwiseRotate90)
                    } else {
                        Label(.localizable(.aiChatButtonCompactContext), systemSymbol: .arrowTriangle2Circlepath)
                    }
                }
                .disabled(isCompactingContext)
            }

            Button {
                toggleAIFileAccess()
            } label: {
                Label(
                    .localizable(.aiChatButtonAIVisibility),
                    systemSymbol: activeFileAccessAllowsAI ? .eye : .eyeSlash
                )
            }
            .help(fileAccessHelpText)
            .disabled(!hasActiveFileForAIAccessControl || !canToggleAIFileAccess)

            Menu {
                modelTierPickerButtons()
            } label: {
                Text(modelPickerTitle)
            }

            if showsCompactIOSFullChatButton {
                Button {
                    enterIOSIslandFullChat()
                } label: {
                    Label(.localizable(.aiChatButtonFullscreen), systemSymbol: .rectangleExpandVertical)
                }
            }

#if DEBUG
            Button {
                generateDebugChatContext()
            } label: {
                Label("Debug Context", systemSymbol: .ladybug)
            }
#endif
        } label: {
            iOSIslandCircleLabel {
                Image(systemSymbol: .listBullet)
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .labelStyle(.iconOnly)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }

    @MainActor
    private var showsIOSCompactContextMenuItem: Bool {
        guard let conversationID,
              let cap = activeModelContextWindowTokens,
              cap > 0
        else { return false }
        let used = llmState.estimatedTokenUsage(in: conversationID)
        return Double(used) / Double(cap) > 0.5
    }

    @MainActor
    private func beginIOSAttachmentPickerPresentation() {
        layoutState.isCompactAIChatAttachmentPickerPresented = true
        isInputFocused = true
    }

    @MainActor
    private func finishIOSAttachmentPickerPresentation(refocus: Bool = true) {
        guard layoutState.isCompactAIChatAttachmentPickerPresented else { return }
        layoutState.isCompactAIChatAttachmentPickerPresented = false
        guard refocus else { return }
        refocusIOSIslandInput()
    }

}

private struct IOSIslandDraftHeightReader: ViewModifier {
    let isEnabled: Bool
    @Binding var height: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.readHeight($height)
        } else {
            content
        }
    }
}

private extension ExcalidrawModelTier {
    var iOSIslandShortLabel: String {
        switch self {
            case .low:
                return "L"
            case .medium:
                return "M"
            case .high:
                return "H"
            case .extraHigh:
                return "X"
        }
    }
}
#endif
