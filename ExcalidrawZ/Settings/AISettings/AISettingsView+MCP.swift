//
//  AISettingsView+MCP.swift
//  ExcalidrawZ
//
//  Created by Codex on 6/15/26.
//

import SwiftUI
import SFSafeSymbols

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum MCPConnectionGuideTab: Hashable, Identifiable {
    case claude
    case vscode

    var id: Self { self }
}

extension AISettingsView {
    @ViewBuilder
    var mcpSettingsSection: some View {
        Section {
            mcpRows
        } header: {
            mcpHeader
                .textCase(nil)
        }
    }

    @ViewBuilder
    var mcpHeader: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localizable: .settingsAIMCPTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(localizable: .settingsAIMCPSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            mcpConnectionGuideButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var mcpRows: some View {
        Toggle(isOn: mcpServerEnabledBinding) {
            VStack(alignment: .leading, spacing: 3) {
                Text(localizable: .settingsAIMCPServerToggleTitle)

                Text(localizable: .settingsAIMCPServerToggleHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        mcpServiceModeRow

        if usesCompactSettingsLayout {
            compactMCPStatusRow
        } else {
            regularMCPStatusRow
        }
    }

    @ViewBuilder
    var mcpServiceModeRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                mcpServiceModeLabel

                Spacer(minLength: 16)

                mcpServiceModePicker
            }

            VStack(alignment: .leading, spacing: 8) {
                mcpServiceModeLabel
                mcpServiceModePicker
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var mcpServiceModeLabel: some View {
        HStack(spacing: 4) {
            Text(localizable: .settingsAIMCPServiceModeTitle)

            Button {
                isPresentingMCPServiceModeHelp = true
            } label: {
                Image(systemSymbol: .questionmarkCircle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localizable: .settingsAIMCPServiceModeHelp))
        }
    }

    @ViewBuilder
    var mcpServiceModePicker: some View {
        Picker(
            String(localizable: .settingsAIMCPServiceModeTitle),
            selection: mcpServiceModeBinding
        ) {
            ForEach(ExcalidrawMCPServiceMode.allCases) { mode in
                Text(mcpServiceModeTitle(for: mode))
                    .tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .mcpServiceModePickerShape()
        .fixedSize(horizontal: true, vertical: true)
    }

    @ViewBuilder
    var regularMCPStatusRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(localizable: .settingsAIMCPStatusLabel)

            Spacer(minLength: 16)

            Text(mcpStatusText)
                .foregroundStyle(mcpStatusColor)
        }
    }

    @ViewBuilder
    var compactMCPStatusRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localizable: .settingsAIMCPStatusLabel)

            Text(mcpStatusText)
                .foregroundStyle(mcpStatusColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var mcpConnectionGuideButton: some View {
        Button {
            isPresentingMCPConnectionGuide = true
        } label: {
            ViewThatFits(in: .horizontal) {
                Label(.localizable(.settingsAIMCPHowToConnectButton), systemSymbol: .link)

                Image(systemSymbol: .link)
            }
            .font(.caption.weight(.semibold))
        }
        .controlSize(.small)
        .help(String(localizable: .settingsAIMCPHowToConnectButton))
    }

    @ViewBuilder
    var mcpConnectionGuideSheet: some View {
        VStack(spacing: 0) {
            mcpConnectionGuideNavigationHeader

            VStack(alignment: .leading, spacing: 20) {
                mcpConnectionGuideTabPicker

                switch selectedMCPConnectionGuideTab {
                    case .claude:
                        mcpClaudeConnectionGuideContent

                    case .vscode:
                        mcpVSCodeConnectionGuideContent
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .mcpConnectionGuideSheetFrame()
    }

    @ViewBuilder
    var mcpServiceModeHelpSheet: some View {
        VStack(spacing: 0) {
            mcpServiceModeHelpNavigationHeader

            VStack(alignment: .leading, spacing: 16) {
                Text(localizable: .settingsAIMCPServiceModeHelp)
                    .font(.callout)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        mcpServiceModeComparisonCard(
                            mode: .basic,
                            symbol: .serverRack,
                            description: String(localizable: .settingsAIMCPServiceModeBasicHelp)
                        )

                        mcpServiceModeComparisonCard(
                            mode: .optimized,
                            symbol: .sparkles,
                            description: String(localizable: .settingsAIMCPServiceModeOptimizedHelp)
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        mcpServiceModeComparisonCard(
                            mode: .basic,
                            symbol: .serverRack,
                            description: String(localizable: .settingsAIMCPServiceModeBasicHelp)
                        )

                        mcpServiceModeComparisonCard(
                            mode: .optimized,
                            symbol: .sparkles,
                            description: String(localizable: .settingsAIMCPServiceModeOptimizedHelp)
                        )
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .mcpConnectionGuideSheetFrame()
    }

    @ViewBuilder
    var mcpServiceModeHelpNavigationHeader: some View {
        ZStack {
            Text(localizable: .settingsAIMCPServiceModeTitle)
                .font(.headline)
                .lineLimit(1)

            HStack {
                mcpSheetCloseButton {
                    isPresentingMCPServiceModeHelp = false
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    func mcpServiceModeComparisonCard(
        mode: ExcalidrawMCPServiceMode,
        symbol: SFSymbol,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemSymbol: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24, height: 24)

                Text(mcpServiceModeTitle(for: mode))
                    .font(.callout.weight(.semibold))
            }

            Text(description)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        }
    }

    @ViewBuilder
    var mcpConnectionGuideNavigationHeader: some View {
        ZStack {
            Text(localizable: .settingsAIMCPConnectionGuideTitle)
                .font(.headline)
                .lineLimit(1)

            HStack {
                mcpConnectionGuideCloseButton

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    var mcpConnectionGuideCloseButton: some View {
        mcpSheetCloseButton {
            isPresentingMCPConnectionGuide = false
        }
    }

    @ViewBuilder
    func mcpSheetCloseButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemSymbol: .xmark)
                .labelStyle(.iconOnly)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .background {
                    if #available(macOS 26.0, iOS 26.0, *) {
                        Circle()
                            .fill(.clear)
                            .glassEffect(.clear, in: Circle())
                    } else {
                        Circle()
                            .fill(.regularMaterial)
                    }
                }
        }
        .buttonStyle(.plain)
        .controlSize(.regular)
        .contentShape(Circle())
        .help(String(localizable: .generalButtonClose))
    }

    @ViewBuilder
    var mcpConnectionGuideTabPicker: some View {
        HStack(spacing: 2) {
            mcpConnectionGuideTabButton(
                .claude,
                title: String(localizable: .settingsAIMCPConnectionGuideClaudeTabTitle)
            )
            mcpConnectionGuideTabButton(
                .vscode,
                title: String(localizable: .settingsAIMCPConnectionGuideVSCodeTabTitle)
            )
        }
        .padding(3)
        .background {
            Capsule()
                .fill(Color.secondary.opacity(0.10))
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    func mcpConnectionGuideTabButton(
        _ tab: MCPConnectionGuideTab,
        title: String
    ) -> some View {
        let isSelected = selectedMCPConnectionGuideTab == tab
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedMCPConnectionGuideTab = tab
            }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(minWidth: 86, minHeight: 28)
                .padding(.horizontal, 8)
                .background {
                    Capsule()
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    var mcpClaudeConnectionGuideContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(.localizable(.settingsAIMCPClaudeUnsupportedTitle), systemSymbol: .exclamationmarkTriangle)
                .font(.headline)

            Text(localizable: .settingsAIMCPClaudeUnsupportedMessage)
                .foregroundStyle(.secondary)

            Text(localizable: .settingsAIMCPClaudeUnsupportedHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var mcpVSCodeConnectionGuideContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(localizable: .settingsAIMCPVSCodeGuideMessage)
                    .foregroundStyle(.secondary)

                Text(localizable: .settingsAIMCPVSCodeGuideSteps)
                    .font(.callout)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(localizable: .settingsAIMCPVSCodeConfigLabel)
                        .font(.headline)

                    Spacer(minLength: 12)

                    mcpGuideCopyButton
                }

                mcpCodeBlock(mcpVSCodeClientConfig)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func mcpCodeBlock(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            }
    }

    @ViewBuilder
    var mcpGuideCopyButton: some View {
        Button {
            copyMCPClientConfig()
        } label: {
            Label(
                didCopyMCPClientConfig ? String(localizable: .exportActionCopied) : String(localizable: .generalButtonCopy),
                systemSymbol: didCopyMCPClientConfig ? .checkmark : .clipboard
            )
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
    }

    var mcpEndpoint: String {
        "http://127.0.0.1:\(mcpServerController.port)/mcp"
    }

    var mcpVSCodeClientConfig: String {
        """
        {
          "servers": {
            "excalidrawz": {
              "type": "http",
              "url": "\(mcpEndpoint)"
            }
          }
        }
        """
    }

    var mcpStatusText: String {
        switch mcpServerController.state {
            case .off:
                String(localizable: .settingsAIMCPStatusOff)
            case .starting:
                String(localizable: .settingsAIMCPStatusStarting)
            case .running:
                String(localizable: .settingsAIMCPStatusRunning)
            case .stopping:
                String(localizable: .settingsAIMCPStatusStopping)
            case .failed:
                String(localizable: .settingsAIMCPStatusFailed)
        }
    }

    var mcpStatusColor: Color {
        switch mcpServerController.state {
            case .off:
                .secondary
            case .starting, .stopping:
                .orange
            case .running:
                .green
            case .failed:
                .red
        }
    }

    var mcpServerEnabledBinding: Binding<Bool> {
        Binding(
            get: { mcpServerController.isEnabled },
            set: { mcpServerController.setEnabled($0) }
        )
    }

    var displayedMCPServiceMode: ExcalidrawMCPServiceMode {
        if mcpServerController.serviceMode == .optimized,
           !store.canUseOptimizedMCPServices {
            return .basic
        }
        return mcpServerController.serviceMode
    }

    var mcpServiceModeBinding: Binding<ExcalidrawMCPServiceMode> {
        Binding(
            get: { displayedMCPServiceMode },
            set: { selectMCPServiceMode($0) }
        )
    }

    func selectMCPServiceMode(_ mode: ExcalidrawMCPServiceMode) {
        guard mode != displayedMCPServiceMode else { return }

        if mode == .optimized,
           !store.canUseOptimizedMCPServices {
            mcpServerController.setServiceMode(.basic)
            store.togglePaywall(reason: .optimizedMCPServices)
            return
        }

        mcpServerController.setServiceMode(mode)
    }

    func mcpServiceModeTitle(for mode: ExcalidrawMCPServiceMode) -> String {
        switch mode {
            case .basic:
                String(localizable: .settingsAIMCPServiceModeBasicTitle)
            case .optimized:
                String(localizable: .settingsAIMCPServiceModeOptimizedTitle)
        }
    }

    @MainActor
    func copyMCPClientConfig() {
        copyMCPText(mcpVSCodeClientConfig)
        didCopyMCPClientConfig = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            didCopyMCPClientConfig = false
        }
    }

    @MainActor
    func copyMCPText(_ text: String) {
#if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
#elseif os(iOS)
        UIPasteboard.general.string = text
#endif
    }
}

private extension View {
    @ViewBuilder
    func mcpConnectionGuideSheetFrame() -> some View {
#if os(macOS)
        self.frame(minWidth: 520, idealWidth: 620, minHeight: 320, idealHeight: 420)
#else
        self
#endif
    }

    @ViewBuilder
    func mcpServiceModePickerShape() -> some View {
        if #available(macOS 14.0, *) {
            self
                .buttonBorderShape(.capsule)
                .containerShape(.capsule)
        } else {
            self
        }
    }
}
