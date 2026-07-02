//
//  MathInputSheetView+Header.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/19.
//

import SwiftUI
import SFSafeSymbols

extension MathInputSheetView {
    @ViewBuilder
    var header: some View {
        ZStack {
            HStack {
                mathHeaderCloseButton

                Spacer()

#if os(macOS)
                mathHeaderInspectorToggleButton
#endif
            }

            workspaceSegmentedPicker
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    var mathHeaderCloseButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemSymbol: .xmark)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .background {
                    mathHeaderCircleButtonBackground
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .contentShape(Circle())
        .help(String(localizable: .generalButtonCancel))
    }

#if os(macOS)
    var mathHeaderInspectorToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isInspectorPresented.toggle()
            }
        } label: {
            Image(systemSymbol: .sidebarRight)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .background {
                    mathHeaderCircleButtonBackground
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isInspectorPresented ? Color.accentColor : Color.secondary)
        .contentShape(Circle())
        .help(String(localizable: .toolbarLatexMathTemplatesHelp))
    }
#endif

    @ViewBuilder
    var mathHeaderCircleButtonBackground: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            Circle()
                .fill(.clear)
                .glassEffect(.clear, in: Circle())
        } else {
            Circle()
                .fill(.regularMaterial)
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.10))
                }
        }
    }

    var workspaceSegmentedPicker: some View {
        HStack(spacing: 3) {
            ForEach(MathInputWorkspace.visibleCases) { workspace in
                workspaceSegmentButton(workspace)
            }
        }
        .padding(4)
        .background {
            workspaceSegmentedPickerBackground
        }
        .fixedSize(horizontal: true, vertical: true)
        .watch(value: activeWorkspace) { newValue in
            if isLatexAIModePresented {
                cancelLatexAIMode()
            }
            if newValue != .equation {
                templateSearchText = ""
            }
            generatePreview(input: newValue == .function ? functionLatexSource : inputText)
        }
    }

    func workspaceSegmentButton(_ workspace: MathInputWorkspace) -> some View {
        let isSelected = activeWorkspace == workspace
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                activeWorkspace = workspace
            }
        } label: {
            HStack(spacing: 6) {
                Text(workspace.symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(workspace.shortTitle)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(width: 86, height: 30)
            .background {
                if isSelected {
                    workspaceSelectedSegmentBackground
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    var workspaceSegmentedPickerBackground: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: Capsule())
        } else {
            Capsule()
                .fill(.regularMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.10))
                }
        }
    }

    @ViewBuilder
    var workspaceSelectedSegmentBackground: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .glassEffect(.clear.interactive(), in: Capsule())
        } else {
            Capsule()
                .fill(Color.primary.opacity(0.10))
                .overlay {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.10))
                }
        }
    }

    var formulaTabs: some View {
        Picker(String(localizable: .toolbarLatexMathFormulaPanelPickerTitle), selection: $formulaTab) {
            ForEach(MathFormulaTab.allCases) { tab in
                Text(tab.title)
                    .tag(tab)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.regular)
        .mathNativeCapsuleSegmentedPicker()
        .frame(maxWidth: .infinity)
        .watch(value: formulaTab) { _ in
            templateSearchText = ""
        }
    }
}
