//
//  AIChatView+Toolbar.swift
//  ExcalidrawZ
//

import ChocofordUI
import SFSafeSymbols
import SwiftUI

extension AIChatView {
    @MainActor @ToolbarContentBuilder
    func toolbar() -> some ToolbarContent {
        if layoutState.isInspectorPresented {
            ToolbarItemGroup(placement: .destructiveAction) {
                Button {
#if os(iOS)
                    if containerHorizontalSizeClass == .compact {
                        layoutState.enterCompactAIChatInputEditing()
                    } else {
                        layoutState.enterAIChatIsland()
                    }
#else
                    layoutState.enterAIChatIsland()
#endif
                } label: {
                    Label(.localizable(.aiChatButtonIslandMode), systemSymbol: .menubarDockRectangle)
                }
                .disabled(fileState.currentActiveFileIsInTrash || !isAIAvailable || !prefs.isAIEnabled)
                .help(String(localizable: .aiChatButtonIslandModeHelp))
            }
            
            // This work...
            ToolbarItemGroup(placement: .principal) {
                Spacer()
            }
            
#if os(macOS)
            if #available(macOS 26.0, *) {
                // Not working...
                ToolbarSpacer(.fixed)
            }
#endif
            
#if os(macOS)
            InspectorHeaderToolbar(
                title: String(localizable: .aiChatTitle),
                isInspectorPresented: layoutState.isInspectorPresented
            )
#endif
            
            ToolbarItemGroup(placement: .automatic) {
                aiChatMoreMenu
            }
        }

#if os(iOS)
        if containerHorizontalSizeClass == .compact,
           !layoutState.isInspectorPresented {
            ToolbarItemGroup(placement: .topBarTrailing) {
                aiChatMoreMenu
            }
        }
#endif
    }

    @ViewBuilder
    private var aiChatMoreMenu: some View {
        Menu {
            Button {} label: {
                Label(.localizable(.aiChatButtonCreditsCount(creditsDisplayText)),
                    systemSymbol: .sparkles
                )
            }
            .disabled(true)

            Divider()

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isShowingWelcomeManually = true
                }
            } label: {
                Label(.localizable(.aiChatButtonShowWelcome), systemSymbol: .sparkles)
            }

#if os(macOS)
            if #available(macOS 14.0, *) {
                OpenSettingsMenuItem(deepLinkTo: .ai, aiSettingsRoute: .settings)
            } else {
                // Pre-`openSettings` env fallback — NSApp.sendAction path.
                Button {
                    presentAISettings()
                } label: {
                    Label(.localizable(.generalButtonSettings), systemSymbol: .gearshape)
                }
            }
#else
            Button {
                presentAISettings()
            } label: {
                Label(.localizable(.generalButtonSettings), systemSymbol: .gearshape)
            }
#endif

            Divider()

            Button(role: .destructive) {
                isConfirmingClear = true
            } label: {
                Label(.localizable(.aiChatButtonClearChat), systemSymbol: .trash)
            }
            .disabled(fileState.aiChatConversationID == nil)
        } label: {
            Label(.localizable(.generalButtonMore), systemSymbol: .ellipsis)
        }
        .menuIndicator(.hidden)
    }

    private func presentAISettings() {
        SettingsRouter.shared.pendingRoute = .ai
        SettingsRouter.shared.pendingAISettingsRoute = .settings
#if os(iOS)
        isAISettingsSheetPresented = true
#else
        SettingsRouter.shared.requestOpen(.ai)
#endif
    }
}
