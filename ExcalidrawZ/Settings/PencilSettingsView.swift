//
//  PencilSettingsView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 12/16/24.
//

import SwiftUI
import ChocofordUI

struct PencilSettingsView: View {
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var toolState: ToolState
#if DEBUG
    @AppStorage(ApplePencilDefaults.isFirstOpenPencilModeKey) private var isFirstOpenPencilMode = true
#endif
    
    var body: some View {
        SettingsFormContainer {
            content()
        }
    }
    
    @ViewBuilder
    private func content() -> some View {
        Section {
            Picker(selection: Binding {
                toolState.pencilInteractionMode
            } set: { mode in
                Task {
                    try? await toolState.setPencilInteractionMode(mode)
                }
            }) {
                Text(.localizable(.applePencilInterationModeOneFingerSelectTitle)).tag(ToolState.PencilInteractionMode.fingerSelect)
                Text(.localizable(.applePencilInterationModeOneFingerMoveTitle)).tag(ToolState.PencilInteractionMode.fingerMove)
                Text(.localizable(.applePencilInterationModeNoneTitle)).tag(ToolState.PencilInteractionMode.none)
            } label: {
                
            }
            .pickerStyle(.inline)
        } header: {
            Text(.localizable(.applePencilInterationTitle))
        } footer: {
            VStack(spacing: 10) {
                Text(.localizable(.applePencilInterationModeOneFingerSelectDescription))
                Text(.localizable(.applePencilInterationModeOneFingerMoveDescription))
                Text(.localizable(.applePencilInterationModeNoneDescription))
            }
        }
        
        
        Section {
            Toggle(isOn: Binding {
                toolState.inPenMode
            } set: { enabled in
                Task {
                    do {
                        try await toolState.togglePenMode(enabled: enabled, pencilConnected: enabled)
                    } catch {
                        alertToast(error)
                    }
                }
            }) {
                Text(.localizable(.applePencilConnectToPencil))
            }
        } footer: {
            Text(.localizable(.applePencilConnectionTips))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

#if DEBUG
        Section {
            LabeledContent("isFirstOpenPencilMode") {
                Text(isFirstOpenPencilMode ? "true" : "false")
                    .foregroundStyle(isFirstOpenPencilMode ? .green : .secondary)
            }

            LabeledContent("inPenMode") {
                Text(toolState.inPenMode ? "true" : "false")
                    .foregroundStyle(toolState.inPenMode ? .green : .secondary)
            }

            Button("Reset First Pencil Mode Tip") {
                Task {
                    isFirstOpenPencilMode = true
                    if toolState.inPenMode {
                        do {
                            try await toolState.togglePenMode(enabled: false, pencilConnected: true)
                        } catch {
                            alertToast(error)
                        }
                    }
                }
            }
        } header: {
            Text("Debug")
        }
#endif
    }
}

#Preview {
    if #available(macOS 13.0, *) {
        NavigationStack {
            PencilSettingsView()
                .environmentObject(ToolState())
        }
    }
}
