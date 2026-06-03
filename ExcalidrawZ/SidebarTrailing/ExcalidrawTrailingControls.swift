//
//  ExcalidrawTrailingControls.swift
//  ExcalidrawZ
//
//  Created by OpenAI on 2025/2/14.
//

import SwiftUI

import ChocofordUI
import SFSafeSymbols

struct ExcalidrawTrailingControls: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass

    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var fileState: FileState

    private var historyDisabled: Bool {
        fileState.currentActiveFile == nil
    }

    private var shouldShowControls: Bool {
        shouldShowInCurrentSizeClass &&
        fileState.currentActiveFile != nil &&
        !fileState.activeCollaborationFileIsLoading
    }

    private var shouldShowInCurrentSizeClass: Bool {
#if os(iOS)
        true
#else
        containerHorizontalSizeClass != .compact
#endif
    }

    private var topPadding: CGFloat {
#if os(iOS)
        containerHorizontalSizeClass == .compact ? 116 : 16
#else
        16
#endif
    }

    private var trailingPadding: CGFloat {
#if os(iOS)
        containerHorizontalSizeClass == .compact ? 12 : 8
#else
        8
#endif
    }

    private var controlSpacing: CGFloat {
#if os(iOS)
        containerHorizontalSizeClass == .compact ? 8 : 10
#else
        10
#endif
    }

    private func isDisabled(tab: LayoutState.InspectorTab) -> Bool {
        switch tab {
            case .history:
                return historyDisabled
            default:
                return false
        }
    }

    var body: some View {
        if shouldShowControls {
            VStack(alignment: .trailing, spacing: controlSpacing) {
                InspectorTabButton(
                    tab: .preference,
                    icon: .sliderHorizontal3,
                    title: String(localizable: .canvasPreferencesTitle),
                    isDisabled: isDisabled(tab: .preference)
                )

                InspectorTabButton(
                    tab: .search,
                    icon: .magnifyingglass,
                    title: String(localizable: .searchButtonTitle),
                    isDisabled: isDisabled(tab: .search)
                )
                .keyboardShortcut("f", modifiers: .command)

                InspectorTabButton(
                    tab: .library,
                    icon: .book,
                    title: String(localizable: .librariesTitle),
                    isDisabled: isDisabled(tab: .library)
                )

                InspectorTabButton(
                    tab: .history,
                    icon: .clockArrowCirclepath,
                    title: String(localizable: .checkpoints),
                    isDisabled: isDisabled(tab: .history)
                )

                InspectorTabButton(
                    tab: .aiChat,
                    icon: .sparkles,
                    title: "AI Chat",
                    isDisabled: isDisabled(tab: .aiChat)
                )

#if DEBUG
                InspectorTabButton(
                    tab: .debug,
                    icon: .ladybug,
                    title: "Debug",
                    isDisabled: isDisabled(tab: .debug)
                )
#endif
            }
            .padding(.top, topPadding)
            .padding(.trailing, trailingPadding)
        }
    }
}

private struct InspectorTabButton: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @EnvironmentObject private var layoutState: LayoutState

    let tab: LayoutState.InspectorTab
    let icon: SFSymbol
    let title: String
    var isDisabled: Bool = false

    private var isActive: Bool {
        layoutState.isInspectorPresented && layoutState.activeInspectorTab == tab
    }

    private var isCompactIOS: Bool {
#if os(iOS)
        containerHorizontalSizeClass == .compact
#else
        false
#endif
    }

    private var iconSize: CGFloat {
        16
    }

    private var iconFrame: CGFloat {
#if os(iOS)
        containerHorizontalSizeClass == .compact ? 28 : 24
#else
        24
#endif
    }

    var body: some View {
        Button {
            guard !isDisabled else { return }
            layoutState.toggleInspector(tab)
        } label: {
            Label(title, systemSymbol: icon)
                .font(.system(size: iconSize))
                .frame(width: iconFrame, height: iconFrame)
        }
        .labelStyle(.iconOnly)
        .modernButtonStyle(
            style: isActive ? .glassProminent : .glass,
            size: isCompactIOS ? .regular : .large,
            shape: .circle
        )
        .help(title)
        .opacity(isDisabled && !isActive ? 0.55 : 1)
        .allowsHitTesting(!isDisabled)
    }
}
