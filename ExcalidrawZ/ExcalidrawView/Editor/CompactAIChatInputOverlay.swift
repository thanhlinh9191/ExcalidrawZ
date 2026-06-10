//
//  CompactAIChatInputOverlay.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/07.
//

#if os(iOS)
import SwiftUI
import ChocofordUI
import UIKit
import LLMCore
import LLMKit
import SFSafeSymbols

private enum CompactAIChatOverlayMetrics {
    static let horizontalPadding: CGFloat = 12
    static let toolbarBottomPadding: CGFloat = 13
    static let toolbarControlLength: CGFloat = 80
    static let tickerHeight: CGFloat = 46
    static let tickerFullscreenButtonLength: CGFloat = 38
    static let draftAttachmentsBottomPadding: CGFloat = toolbarBottomPadding + tickerHeight + 8
    static let tickerAppearDelay: Duration = .milliseconds(140)
    static let tickerCollapseDuration: Duration = .milliseconds(360)
}

struct CompactAIChatInputOverlay: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass

    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var aiChatState: AIChatState
    @ObservedObject private var aiChatPreferences = AIChatPreferences.shared

    @State private var keyboardHeight: CGFloat = 0
    @State private var keyboardAnimationDuration: TimeInterval = 0.25

    private var isCompactIOS: Bool {
        containerHorizontalSizeClass == .compact
    }

    private var isVisible: Bool {
        isCompactIOS &&
            layoutState.isCompactAIChatToolbarPresented &&
            layoutState.isCompactAIChatInputEditing &&
            AIChatAvailability.isAvailable &&
            aiChatPreferences.isAIEnabled &&
            !fileState.currentActiveFileIsInTrash
    }

    private var conversationIDBinding: Binding<String?> {
        Binding(
            get: { fileState.aiChatConversationID },
            set: { fileState.aiChatConversationID = $0 }
        )
    }

    var body: some View {
        if isVisible {
            PromptInputView(
                conversationID: conversationIDBinding,
                pendingQueue: $aiChatState.pendingQueue,
                style: .compactIOSIsland,
                focusOnAppear: true,
                dismissKeyboardOnSuccessfulSubmit: true,
                onSuccessfulSubmit: {
                    guard layoutState.isCompactAIChatToolbarPresented else { return }
                    withAnimation(.smooth(duration: 0.18)) {
                        layoutState.isCompactAIChatReplyTickerVisible = true
                        layoutState.isCompactAIChatReplyStartPending = true
                    }
                }
            )
            .disabled(fileState.isAIChatConversationLoading || fileState.currentActiveFileIsInTrash)
            .padding(.horizontal, CompactAIChatOverlayMetrics.horizontalPadding)
            .padding(.bottom, bottomPadding)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeOut(duration: keyboardAnimationDuration), value: keyboardHeight)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                updateKeyboardHeight(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
                updateKeyboardHeight(notification, isHiding: true)
            }
        }
    }

    private var bottomPadding: CGFloat {
        keyboardHeight > 0 ? keyboardHeight + 8 : CompactAIChatOverlayMetrics.toolbarBottomPadding
    }

    private func updateKeyboardHeight(_ notification: Notification, isHiding: Bool = false) {
        if let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval {
            keyboardAnimationDuration = duration
        }

        if isHiding {
            keyboardHeight = 0
            guard !layoutState.isCompactAIChatAttachmentPickerPresented else {
                return
            }
            layoutState.exitCompactAIChatInputEditing()
            return
        }

        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            keyboardHeight = 0
            return
        }

        let screenHeight = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.height }
            .first ?? UIScreen.main.bounds.height
        keyboardHeight = max(0, screenHeight - frame.minY)
    }
}

struct CompactAIChatGeneratingOverlay: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass

    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var llmState: LLMStateObject
    @EnvironmentObject private var aiChatState: AIChatState
    @ObservedObject private var aiChatPreferences = AIChatPreferences.shared
    @State private var renderedReplyText: String?
    @State private var isTickerPresented = false
    @State private var isTickerCollapsing = false
    @State private var tickerPresentationTask: Task<Void, Never>?

    private var isCompactIOS: Bool {
        containerHorizontalSizeClass == .compact
    }

    private var canShowTicker: Bool {
        isCompactIOS &&
            layoutState.isCompactAIChatToolbarPresented &&
            !layoutState.isCompactAIChatInputEditing &&
            AIChatAvailability.isAvailable &&
            aiChatPreferences.isAIEnabled &&
            !fileState.currentActiveFileIsInTrash
    }

    private var compactAIChatIsGenerating: Bool {
        guard let conversationID = fileState.aiChatConversationID else { return false }
        return llmState.isRunning(conversationID: conversationID)
    }

    private var trailingPadding: CGFloat {
        compactAIChatShouldReserveStopSpace ? CompactAIChatOverlayMetrics.toolbarControlLength : 0
    }

    private var compactAIChatShouldReserveStopSpace: Bool {
        compactAIChatIsGenerating || layoutState.isCompactAIChatReplyStartPending
    }

    private var pendingReplyFailureID: UUID? {
        guard layoutState.isCompactAIChatReplyStartPending,
              !compactAIChatIsGenerating,
              let transientError = aiChatState.transientError
        else {
            return nil
        }

        if let conversationID = fileState.aiChatConversationID,
           transientError.conversationID != conversationID {
            return nil
        }

        return transientError.id
    }

    var body: some View {
        if canShowTicker {
            generatingTicker
                .frame(maxWidth: .infinity, alignment: .bottom)
                .allowsHitTesting(true)
        }
    }

    @ViewBuilder
    private var generatingTicker: some View {
        AIChatReplyTickerHost(onReplyTextChange: updateReplyTickerVisibility) { replyText in
            let text = renderedReplyText ?? replyText
            if text != nil || layoutState.isCompactAIChatReplyStartPending {
                CompactAIChatReplyTickerView(
                    text: text,
                    isPending: layoutState.isCompactAIChatReplyStartPending,
                    onTapTicker: {
                        layoutState.enterCompactAIChatInputEditing()
                    },
                    onOpenFullChat: {
                        layoutState.presentCompactAIChatFullChat()
                    }
                )
                .scaleEffect(
                    x: tickerScaleX,
                    y: tickerScaleY,
                    anchor: tickerScaleAnchor
                )
                .opacity(isTickerPresented || !isTickerCollapsing ? 1 : 0)
                .padding(.trailing, trailingPadding)
                .padding(.horizontal, CompactAIChatOverlayMetrics.horizontalPadding)
                .padding(.bottom, CompactAIChatOverlayMetrics.toolbarBottomPadding)
                .safeAreaPadding(.bottom)
                .animation(.smooth(duration: 0.24), value: compactAIChatShouldReserveStopSpace)
                .allowsHitTesting(isTickerPresented)
            }
        }
        .watch(value: pendingReplyFailureID) { _, failureID in
            guard failureID != nil else { return }
            dismissPendingReplyTicker()
        }
    }

    private func updateReplyTickerVisibility(_ replyText: String?) {
        Task { @MainActor in
            handleReplyTickerVisibility(replyText)
        }
    }

    @MainActor
    private func handleReplyTickerVisibility(_ replyText: String?) {
        tickerPresentationTask?.cancel()

        if let replyText {
            isTickerCollapsing = false
            renderedReplyText = replyText
            if !layoutState.isCompactAIChatReplyTickerVisible {
                withAnimation(.smooth(duration: 0.18)) {
                    layoutState.isCompactAIChatReplyTickerVisible = true
                }
            }
            layoutState.isCompactAIChatReplyStartPending = false

            guard !isTickerPresented else { return }
            tickerPresentationTask = Task { @MainActor in
                try? await Task.sleep(for: CompactAIChatOverlayMetrics.tickerAppearDelay)
                guard !Task.isCancelled else { return }
                withAnimation(.smooth(duration: 0.24)) {
                    isTickerPresented = true
                }
            }
            return
        }

        if layoutState.isCompactAIChatReplyStartPending {
            if pendingReplyFailureID != nil {
                dismissPendingReplyTicker()
                return
            }
            isTickerCollapsing = false
            guard !isTickerPresented else { return }
            tickerPresentationTask = Task { @MainActor in
                try? await Task.sleep(for: CompactAIChatOverlayMetrics.tickerAppearDelay)
                guard !Task.isCancelled else { return }
                withAnimation(.smooth(duration: 0.24)) {
                    isTickerPresented = true
                }
            }
            return
        }

        guard renderedReplyText != nil || isTickerPresented else { return }

        withAnimation(.bouncy(duration: 0.36, extraBounce: 0.18)) {
            isTickerCollapsing = true
            isTickerPresented = false
        }
        tickerPresentationTask = Task { @MainActor in
            try? await Task.sleep(for: CompactAIChatOverlayMetrics.tickerCollapseDuration)
            guard !Task.isCancelled else { return }
            renderedReplyText = nil
            withAnimation(.smooth(duration: 0.2)) {
                layoutState.isCompactAIChatReplyTickerVisible = false
                layoutState.isCompactAIChatReplyStartPending = false
            }
        }
    }

    @MainActor
    private func dismissPendingReplyTicker() {
        tickerPresentationTask?.cancel()
        renderedReplyText = nil
        isTickerCollapsing = false
        withAnimation(.smooth(duration: 0.18)) {
            isTickerPresented = false
            layoutState.isCompactAIChatReplyTickerVisible = false
            layoutState.isCompactAIChatReplyStartPending = false
        }
    }

    private var tickerScaleX: CGFloat {
        guard !isTickerPresented else { return 1 }
        return isTickerCollapsing ? 0.18 : 0.01
    }

    private var tickerScaleY: CGFloat {
        guard !isTickerPresented else { return 1 }
        return isTickerCollapsing ? 0.18 : 1
    }

    private var tickerScaleAnchor: UnitPoint {
        isTickerCollapsing ? .center : .leading
    }

}

struct CompactAIChatDraftAttachmentsOverlay: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass

    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var aiChatState: AIChatState
    @ObservedObject private var aiChatPreferences = AIChatPreferences.shared

    private var isCompactIOS: Bool {
        containerHorizontalSizeClass == .compact
    }

    private var canShowDraftAttachments: Bool {
        isCompactIOS &&
            layoutState.isCompactAIChatToolbarPresented &&
            !layoutState.isCompactAIChatInputEditing &&
            !layoutState.isCompactAIChatReplyTickerVisible &&
            !layoutState.isCompactAIChatReplyStartPending &&
            AIChatAvailability.isAvailable &&
            aiChatPreferences.isAIEnabled &&
            !fileState.currentActiveFileIsInTrash
    }

    private var draftState: AIChatPromptDraftState {
        aiChatState.promptDraftState(
            conversationID: fileState.aiChatConversationID,
            fileScope: fileState.currentActiveFile?.aiConversationFileScope
        )
    }

    var body: some View {
        if canShowDraftAttachments {
            HStack(spacing: 0) {
                CompactAIChatDraftAttachmentStrip(draftState: draftState) {
                    layoutState.enterCompactAIChatInputEditing()
                }

                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, CompactAIChatOverlayMetrics.horizontalPadding)
            .padding(.bottom, CompactAIChatOverlayMetrics.draftAttachmentsBottomPadding)
            .safeAreaPadding(.bottom)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.smooth(duration: 0.18), value: draftState.images.count)
        }
    }
}

struct CompactAIChatProposalOverlay: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass

    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var llmState: LLMStateObject
    @ObservedObject private var aiChatPreferences = AIChatPreferences.shared

    private var isCompactIOS: Bool {
        containerHorizontalSizeClass == .compact
    }

    private var canShowProposalSurface: Bool {
        isCompactIOS &&
            layoutState.isCompactAIChatToolbarPresented &&
            AIChatAvailability.isAvailable &&
            aiChatPreferences.isAIEnabled &&
            !fileState.currentActiveFileIsInTrash
    }

    private var conversation: Conversation? {
        llmState.conversations.value?
            .first { $0.id == fileState.aiChatConversationID }
    }

    private var conversationMessageCount: Int {
        conversation?.messages.count ?? 0
    }

    var body: some View {
        if canShowProposalSurface {
            proposalStack
                .padding(.horizontal, CompactAIChatOverlayMetrics.horizontalPadding)
                .padding(.bottom, CompactAIChatOverlayMetrics.toolbarBottomPadding)
                .safeAreaPadding(.bottom)
                .opacity(layoutState.isCompactAIChatInputEditing ? 0 : 1)
                .allowsHitTesting(!layoutState.isCompactAIChatInputEditing)
                .animation(
                    .easeInOut(duration: 0.18),
                    value: layoutState.isCompactAIChatInputEditing
                )
        }
    }

    private var proposalStack: some View {
        Color.clear
            .frame(height: CompactAIChatOverlayMetrics.tickerHeight)
            .allowsHitTesting(false)
            .modifier(AIChatIslandProposalModifier(
                conversationID: fileState.aiChatConversationID,
                conversation: conversation,
                conversationMessageCount: conversationMessageCount,
                islandWidth: nil
            ))
            .frame(maxWidth: 360)
    }
}

private struct CompactAIChatDraftAttachmentStrip: View {
    @ObservedObject var draftState: AIChatPromptDraftState

    let onTap: () -> Void

    private var visibleImages: [PendingPastedImage] {
        Array(draftState.images.prefix(4))
    }

    private var remainingCount: Int {
        max(0, draftState.images.count - visibleImages.count)
    }

    var body: some View {
        if !draftState.images.isEmpty {
            Button(action: onTap) {
                HStack(spacing: 6) {
                    ForEach(visibleImages) { image in
                        CompactAIChatDraftAttachmentThumbnail(image: image)
                    }

                    if remainingCount > 0 {
                        Text("+\(remainingCount)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 34)
                            .background {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(.thinMaterial)
                            }
                    }
                }
                .padding(6)
                .background {
                    attachmentStripBackground
                }
                .clipShape(Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Attached images")
        }
    }

    @ViewBuilder
    private var attachmentStripBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: Capsule())
        } else {
            Capsule()
                .fill(.regularMaterial)
        }
    }
}

private struct CompactAIChatDraftAttachmentThumbnail: View {
    let image: PendingPastedImage

    var body: some View {
        Image(uiImage: image.image)
            .resizable()
            .scaledToFill()
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 0.5)
            }
    }
}

private struct CompactAIChatReplyTickerView: View {
    let text: String?
    let isPending: Bool
    let onTapTicker: () -> Void
    let onOpenFullChat: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onTapTicker) {
                tickerContent
                    .frame(
                        maxWidth: .infinity,
                        minHeight: CompactAIChatOverlayMetrics.tickerHeight,
                        maxHeight: CompactAIChatOverlayMetrics.tickerHeight
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("AI Chat")

            fullscreenButton
                .padding(.trailing, 4)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: CompactAIChatOverlayMetrics.tickerHeight,
            maxHeight: CompactAIChatOverlayMetrics.tickerHeight
        )
        .background {
            tickerBackground
            if text == nil, isPending {
                tickerGlow
            }
        }
        .clipShape(Capsule())
        .contentShape(Capsule())
        .animation(.smooth(duration: 0.18), value: text != nil)
        .animation(.smooth(duration: 0.18), value: isPending)
    }

    @ViewBuilder
    private var tickerContent: some View {
        if let text {
            ReplyTickerView(text: text)
                .transition(.opacity)
        } else if isPending {
            Color.clear
                .frame(maxWidth: .infinity)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var fullscreenButton: some View {
        Button(action: onOpenFullChat) {
            Image(systemSymbol: .rectangleExpandVertical)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 16, height: 16)
        }
        .modernButtonStyle(style: .glassProminent, size: .regular, shape: .circle)
        .frame(
            width: CompactAIChatOverlayMetrics.tickerFullscreenButtonLength,
            height: CompactAIChatOverlayMetrics.tickerFullscreenButtonLength
        )
        .clipShape(Circle())
        .contentShape(Circle())
        .help(.localizable(.aiChatButtonFullscreen))
        .accessibilityLabel(Text(localizable: .aiChatButtonFullscreen))
    }

    @ViewBuilder
    private var tickerBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: Capsule())
        } else {
            Capsule()
                .fill(.regularMaterial)
        }
    }

    @ViewBuilder
    private var tickerGlow: some View {
        Capsule()
            .fill(AIAppearancePalette.thinkingGradient)
            .blur(radius: 20)
            .opacity(0.55)
    }
}
#endif
