//
//  PencilSettingsView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 12/16/24.
//

import SwiftUI
import ChocofordUI

struct PencilSettingsView: View {
    @AppStorage(ToolState.pencilInteractionModeDefaultsKey) private var pencilInteractionModeRawValue = ToolState.PencilInteractionMode.fingerSelect.rawValue
    @State private var inPenMode = false
#if DEBUG
    @AppStorage(ApplePencilDefaults.isFirstOpenPencilModeKey) private var isFirstOpenPencilMode = true
#endif

    private var pencilInteractionMode: ToolState.PencilInteractionMode {
        ToolState.PencilInteractionMode(rawValue: pencilInteractionModeRawValue) ?? .fingerSelect
    }
    
    var body: some View {
        SettingsFormContainer {
            content()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pencilPenModeStateDidChange)) { notification in
            guard let inPenMode = notification.object as? Bool else { return }
            self.inPenMode = inPenMode
        }
        .task {
            NotificationCenter.default.post(name: .pencilPenModeStateRequested, object: nil)
        }
    }
    
    @ViewBuilder
    private func content() -> some View {
        Section {
            Picker(selection: Binding {
                pencilInteractionMode
            } set: { mode in
                pencilInteractionModeRawValue = mode.rawValue
                NotificationCenter.default.post(
                    name: .pencilInteractionModeDidChange,
                    object: mode
                )
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
                inPenMode
            } set: { enabled in
                NotificationCenter.default.post(
                    name: .pencilPenModeChangeRequested,
                    object: PencilPenModeChangeRequest(
                        enabled: enabled,
                        pencilConnected: enabled
                    )
                )
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
                Text(inPenMode ? "true" : "false")
                    .foregroundStyle(inPenMode ? .green : .secondary)
            }

            Button("Reset First Pencil Mode Tip") {
                isFirstOpenPencilMode = true
                if inPenMode {
                    NotificationCenter.default.post(
                        name: .pencilPenModeChangeRequested,
                        object: PencilPenModeChangeRequest(
                            enabled: false,
                            pencilConnected: true
                        )
                    )
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
        }
    }
}
