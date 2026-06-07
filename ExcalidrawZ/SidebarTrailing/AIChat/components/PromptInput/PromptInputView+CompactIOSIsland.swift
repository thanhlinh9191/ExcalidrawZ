//
//  PromptInputView+CompactIOSIsland.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/05.
//

#if os(iOS)
import SwiftUI
import ChocofordUI
import SFSafeSymbols

extension PromptInputView {
    private var iOSIslandCircleControlLength: CGFloat { 40 }
    private var iOSIslandInlineControlLength: CGFloat { 34 }
    private var iOSIslandPrimaryActionLength: CGFloat { 36 }
    private var iOSIslandPrimaryActionIconLength: CGFloat { 16 }
    private var iOSIslandExpandedInputMinHeight: CGFloat { 44 }
    private var iOSIslandInputMaxHeight: CGFloat { 168 }

    @ViewBuilder
    var iOSIslandInputContent: some View {
        let isExpanded = iOSIslandInputIsExpanded

        VStack(alignment: .trailing, spacing: 5) {
            if !isExpanded {
                iOSIslandInlineSettings
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(alignment: .bottom, spacing: 7) {
                VStack(spacing: 7) {
                    if isExpanded {
                        iOSIslandSettingsMenu
                            .transition(.opacity.combined(with: .scale))
                    }

                    iOSIslandAttachmentMenu
                }

                iOSIslandTextInputSurface(isExpanded: isExpanded)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(.smooth(duration: 0.2), value: isExpanded)
    }

    var iOSIslandInputIsExpanded: Bool {
        let hasWrappedText = draftHasContent && iOSIslandDraftFieldHeight > 48

        return draftHasImages
            || promptDraftState.text.contains("\n")
            || hasWrappedText
    }

    @ViewBuilder
    var iOSToolbarTextInputContent: some View {
        let isExpanded = iOSIslandInputIsExpanded

        iOSToolbarTextInputSurface(isExpanded: isExpanded)
        .frame(alignment: .bottom)
        .animation(.smooth(duration: 0.2), value: isExpanded)
    }

    @ViewBuilder
    private func iOSToolbarTextInputSurface(isExpanded: Bool) -> some View {
        PromptDraftInputField(
            draftKey: promptDraftKey,
            draftState: promptDraftState,
            showsAttachments: true,
            sendRequestToken: draftSendRequestToken,
            focus: $isInputFocused,
            onSubmit: { text, images in
                submitDraft(prompt: text, pastedImages: images)
            },
            onPaste: handlePastedItem,
            onSummaryChange: { hasContent, hasImages in
                updateDraftSummary(hasContent: hasContent, hasImages: hasImages)
            }
        )
        .id(ObjectIdentifier(promptDraftState))
        .readHeight($iOSIslandDraftFieldHeight)
        .padding(.leading, 2)
        .padding(.trailing, 42)
        .padding(.vertical, isExpanded ? 6 : 0)
        .frame(
            minHeight: isExpanded ? iOSIslandExpandedInputMinHeight : iOSIslandCircleControlLength,
            maxHeight: isExpanded ? iOSIslandInputMaxHeight : iOSIslandCircleControlLength,
            alignment: isExpanded ? .bottom : .center
        )
        .overlay(alignment: isExpanded ? .bottomTrailing : .trailing) {
            iOSToolbarPrimaryActionButton
                .padding(.trailing, 0)
        }
    }

    @ViewBuilder
    private func iOSIslandTextInputSurface(isExpanded: Bool) -> some View {
        PromptDraftInputField(
            draftKey: promptDraftKey,
            draftState: promptDraftState,
            showsAttachments: true,
            sendRequestToken: draftSendRequestToken,
            focus: $isInputFocused,
            onSubmit: { text, images in
                submitDraft(prompt: text, pastedImages: images)
            },
            onPaste: handlePastedItem,
            onSummaryChange: { hasContent, hasImages in
                updateDraftSummary(hasContent: hasContent, hasImages: hasImages)
            }
        )
        .id(ObjectIdentifier(promptDraftState))
        .readHeight($iOSIslandDraftFieldHeight)
        .padding(.leading, 12)
        .padding(.trailing, 44)
        .padding(.vertical, isExpanded ? 8 : 2)
        .frame(
            minHeight: isExpanded ? iOSIslandExpandedInputMinHeight : iOSIslandCircleControlLength,
            maxHeight: isExpanded ? iOSIslandInputMaxHeight : iOSIslandCircleControlLength,
            alignment: isExpanded ? .bottom : .center
        )
        .frame(maxWidth: .infinity, alignment: .bottom)
        .background {
            iOSIslandTextInputBackground(isExpanded: isExpanded)
        }
        .clipShape(iOSIslandTextInputShape(isExpanded: isExpanded))
        .overlay {
            iOSIslandTextInputShape(isExpanded: isExpanded)
                .stroke(.separator.opacity(0.55), lineWidth: 0.7)
        }
        .overlay(alignment: isExpanded ? .bottomTrailing : .trailing) {
            iOSIslandPrimaryActionButton
                .padding(.trailing, 2)
                .padding(.bottom, isExpanded ? 2 : 0)
        }
        .contentShape(iOSIslandTextInputShape(isExpanded: isExpanded))
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
        Menu {
            Button {
                isImagePickerPresented = true
            } label: {
                Label(.localizable(.aiChatInputAttachmentMenuItemImage), systemSymbol: .photo)
            }
            .disabled(!canInsertImages)
        } label: {
            iOSIslandCircleLabel {
                Image(systemSymbol: .plus)
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .labelStyle(.iconOnly)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fileImporter(
            isPresented: $isImagePickerPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            handleImagePickerResult(result)
        }
    }

    @ViewBuilder
    var iOSIslandInlineSettings: some View {
        HStack(spacing: 5) {
            iOSIslandFileAccessButton

            iOSIslandModelPicker

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
                    .font(.system(size: 12, weight: .semibold))
                    .frame(
                        width: iOSIslandPrimaryActionIconLength,
                        height: iOSIslandPrimaryActionIconLength
                    )
                    .contentTransition(.symbolEffect(.replace))
            } else {
                Image(systemSymbol: primaryActionIsStop ? .stopFill : .arrowUp)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(
                        width: iOSIslandPrimaryActionIconLength,
                        height: iOSIslandPrimaryActionIconLength
                    )
            }
        }
        .modernButtonStyle(style: .glassProminent, size: .small, shape: .circle)
        .frame(
            width: iOSIslandPrimaryActionLength,
            height: iOSIslandPrimaryActionLength
        )
        .clipShape(Circle())
        .contentShape(Circle())
        .disabled(!primaryActionIsStop && !hasInputText)
    }

    @ViewBuilder
    var iOSToolbarPrimaryActionButton: some View {
        Button {
            if primaryActionIsStop {
                cancelCurrentGeneration()
            } else {
                draftSendRequestToken += 1
            }
        } label: {
            if #available(iOS 17.0, *) {
                Image(systemSymbol: primaryActionIsStop ? .stopFill : .arrowUp)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentTransition(.symbolEffect(.replace))
            } else {
                Image(systemSymbol: primaryActionIsStop ? .stopFill : .arrowUp)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            primaryActionIsStop || hasInputText
            ? AnyShapeStyle(Color.white)
            : AnyShapeStyle(Color.secondary)
        )
        .background {
            Circle()
                .fill(
                    primaryActionIsStop || hasInputText
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(.regularMaterial)
                )
        }
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
                Text(activeTierForModelPicker.iOSIslandShortLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .monospaced()
            }
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .disabled(modelPickerTiers.isEmpty)
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
            .overlay {
                Circle()
                    .stroke(.separator.opacity(0.55), lineWidth: 0.7)
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
            Button {
                compactCurrentContext()
            } label: {
                if #available(iOS 18.0, *) {
                    Label(.localizable(.aiChatContextUsageTitle), systemSymbol: .arrowTrianglehead2ClockwiseRotate90)
                } else {
                    Label(.localizable(.aiChatContextUsageTitle), systemSymbol: .arrowTriangle2Circlepath)
                }
            }
            .disabled(conversationID == nil || isCompactingContext)

            Button {
                toggleAIFileAccess()
            } label: {
                Label(
                    fileAccessHelpText,
                    systemSymbol: activeFileAccessAllowsAI ? .eye : .eyeSlash
                )
            }
            .disabled(!hasActiveFileForAIAccessControl || !canToggleAIFileAccess)

            Menu {
                modelTierPickerButtons()
            } label: {
                Text(activeModel.excalidrawTierName)
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
