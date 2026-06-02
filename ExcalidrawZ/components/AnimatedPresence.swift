//
//  AnimatedPresence.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/01.
//

import SwiftUI

struct AnimatedPresence<Value: Equatable, Content: View>: View {
    let value: Value?
    var animation: Animation = .easeInOut(duration: 0.22)
    var contentAnimation: Animation = .easeInOut(duration: 0.16)
    var contentTransition: AnimatedPresenceContentTransition = .fadeWithContainer
    var contentTransitionDelay: Duration = .milliseconds(140)
    var removalAnimation: Animation? = nil
    var removalDelay: Duration = .milliseconds(240)
    @ViewBuilder var content: (Value) -> Content

    @State private var displayedValue: Value?
    @State private var measuredHeight: CGFloat = 0
    @State private var visibleHeight: CGFloat = 0
    @State private var contentOpacity: CGFloat = 0
    @State private var contentTransitionTask: Task<Void, Never>?
    @State private var removalTask: Task<Void, Never>?

    private var progress: CGFloat {
        measuredHeight > 0 ? min(max(visibleHeight / measuredHeight, 0), 1) : 0
    }

    private var renderedContentOpacity: CGFloat {
        switch contentTransition {
            case .clipped:
                1
            case .fadeWithContainer:
                progress
            case .deferredOpacity:
                contentOpacity
        }
    }

    var body: some View {
        AnimatedPresenceHeightLayout(visibleHeight: visibleHeight) {
            if let displayedValue {
                content(displayedValue)
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(
                                    key: AnimatedPresenceHeightKey.self,
                                    value: proxy.size.height
                                )
                        }
                    }
                    .opacity(renderedContentOpacity)
            }
        }
        .modifier(AnimatedPresenceClipModifier(isClipped: contentTransition == .clipped))
        .allowsHitTesting(value != nil && progress > 0.95)
        .layoutValue(key: AnimatedPresenceProgressKey.self, value: progress)
        .onAppear {
            updatePresence(value)
        }
        .animatedPresenceOnChange(of: value) { newValue in
            updatePresence(newValue)
        }
        .onPreferenceChange(AnimatedPresenceHeightKey.self) { newHeight in
            measuredHeight = newHeight
            guard value != nil else { return }
            withAnimation(animation) {
                visibleHeight = newHeight
            }
            scheduleDeferredContentAppearanceIfNeeded()
        }
        .onDisappear {
            contentTransitionTask?.cancel()
            removalTask?.cancel()
        }
    }

    private func updatePresence(_ newValue: Value?) {
        contentTransitionTask?.cancel()
        removalTask?.cancel()

        if let newValue {
            displayedValue = newValue
            prepareContentForInsertion()
            withAnimation(animation) {
                visibleHeight = measuredHeight
            }
            scheduleDeferredContentAppearanceIfNeeded()
            return
        }

        if contentTransition == .deferredOpacity {
            withAnimation(contentAnimation) {
                contentOpacity = 0
            }

            contentTransitionTask = Task { @MainActor in
                try? await Task.sleep(for: contentTransitionDelay)
                guard !Task.isCancelled, value == nil else { return }
                collapseContainerAndScheduleRemoval()
            }
            return
        }

        collapseContainerAndScheduleRemoval()
    }

    private func prepareContentForInsertion() {
        switch contentTransition {
            case .clipped, .fadeWithContainer:
                contentOpacity = 1
            case .deferredOpacity:
                contentOpacity = 0
        }
    }

    private func scheduleDeferredContentAppearanceIfNeeded() {
        guard contentTransition == .deferredOpacity,
              value != nil,
              displayedValue != nil,
              measuredHeight > 0 else {
            return
        }

        contentTransitionTask?.cancel()
        contentTransitionTask = Task { @MainActor in
            try? await Task.sleep(for: contentTransitionDelay)
            guard !Task.isCancelled, value != nil else { return }
            withAnimation(contentAnimation) {
                contentOpacity = 1
            }
        }
    }

    private func collapseContainerAndScheduleRemoval() {
        withAnimation(removalAnimation ?? animation) {
            visibleHeight = 0
        }

        removalTask = Task { @MainActor in
            try? await Task.sleep(for: removalDelay)
            guard !Task.isCancelled, value == nil else { return }
            displayedValue = nil
            measuredHeight = 0
            contentOpacity = 0
        }
    }
}

enum AnimatedPresenceContentTransition {
    /// Accordion style: parent height changes and content is clipped to the
    /// visible bounds.
    case clipped
    /// Parent height and content opacity follow the same progress.
    case fadeWithContainer
    /// Parent height animates first, then content performs its own opacity
    /// transition. On removal, content fades out before the height collapses.
    case deferredOpacity
}

private struct AnimatedPresenceClipModifier: ViewModifier {
    let isClipped: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isClipped {
            content.clipped()
        } else {
            content
        }
    }
}

private extension View {
    @ViewBuilder
    func animatedPresenceOnChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value) { newValue in
                action(newValue)
            }
        }
    }
}

private struct AnimatedPresenceHeightLayout: Layout {
    var visibleHeight: CGFloat

    var animatableData: CGFloat {
        get { visibleHeight }
        set { visibleHeight = newValue }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let idealSize = subview.sizeThatFits(
            ProposedViewSize(width: proposal.width, height: nil)
        )
        return CGSize(width: idealSize.width, height: max(0, visibleHeight))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        let idealSize = subview.sizeThatFits(
            ProposedViewSize(width: bounds.width, height: nil)
        )
        subview.place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: bounds.width, height: idealSize.height)
        )
    }
}

private struct AnimatedPresenceHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct AnimatedPresenceProgressKey: LayoutValueKey {
    static let defaultValue: CGFloat? = nil
}

struct CollapsibleSpacingVStack<Content: View>: View {
    var alignment: HorizontalAlignment = .center
    var spacing: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        CollapsibleSpacingVStackLayout(alignment: alignment, spacing: spacing) {
            content()
        }
    }
}

private struct CollapsibleSpacingVStackLayout: Layout {
    var alignment: HorizontalAlignment
    var spacing: CGFloat?

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard !subviews.isEmpty else { return .zero }

        let sizes = measuredSizes(for: subviews, proposal: proposal)
        let progressValues = subviews.map(presenceProgress)
        var width: CGFloat = 0
        var height: CGFloat = 0

        for index in subviews.indices {
            width = max(width, sizes[index].width)
            height += sizes[index].height

            if index < subviews.count - 1 {
                height += collapsedSpacing(
                    after: index,
                    subviews: subviews,
                    progressValues: progressValues
                )
            }
        }

        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard !subviews.isEmpty else { return }

        let sizes = measuredSizes(for: subviews, proposal: proposal)
        let progressValues = subviews.map(presenceProgress)
        var y = bounds.minY

        for index in subviews.indices {
            let size = sizes[index]
            let x = xPosition(for: size.width, in: bounds)
            subviews[index].place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            y += size.height
            if index < subviews.count - 1 {
                y += collapsedSpacing(
                    after: index,
                    subviews: subviews,
                    progressValues: progressValues
                )
            }
        }
    }

    private func measuredSizes(for subviews: Subviews, proposal: ProposedViewSize) -> [CGSize] {
        subviews.map { subview in
            subview.sizeThatFits(
                ProposedViewSize(width: proposal.width, height: nil)
            )
        }
    }

    private func collapsedSpacing(
        after index: Int,
        subviews: Subviews,
        progressValues: [CGFloat]
    ) -> CGFloat {
        let currentProgress = progressValues[index]
        let nextProgress = progressValues[index + 1]
        let baseSpacing = spacingBetween(subviews[index], subviews[index + 1])
        let directSpacing = baseSpacing * min(currentProgress, nextProgress)

        guard currentProgress > 0.001,
              nextProgress < 0.999,
              let nextExpandedIndex = nextExpandedSubviewIndex(
                after: index,
                progressValues: progressValues
              ) else {
            return directSpacing
        }

        let hiddenRunProgress = progressValues[(index + 1)..<nextExpandedIndex].max() ?? 0
        let bridgeSpacing = spacingBetween(subviews[index], subviews[nextExpandedIndex])
            * (1 - hiddenRunProgress)

        return directSpacing + bridgeSpacing
    }

    private func spacingBetween(_ current: LayoutSubview, _ next: LayoutSubview) -> CGFloat {
        spacing ?? current.spacing.distance(to: next.spacing, along: .vertical)
    }

    private func presenceProgress(of subview: LayoutSubview) -> CGFloat {
        guard let progress = subview[AnimatedPresenceProgressKey.self] else { return 1 }
        return min(max(progress, 0), 1)
    }

    private func nextExpandedSubviewIndex(
        after index: Int,
        progressValues: [CGFloat]
    ) -> Int? {
        guard index + 2 < progressValues.count else { return nil }

        for candidate in (index + 2)..<progressValues.count {
            if progressValues[candidate] >= 0.999 {
                return candidate
            }
            if progressValues[candidate] <= 0.001 {
                continue
            }
        }

        return nil
    }

    private func xPosition(for width: CGFloat, in bounds: CGRect) -> CGFloat {
        switch alignment {
            case .leading:
                bounds.minX
            case .trailing:
                bounds.maxX - width
            default:
                bounds.minX + (bounds.width - width) / 2
        }
    }
}
