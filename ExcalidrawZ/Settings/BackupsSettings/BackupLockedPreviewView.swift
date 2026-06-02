//
//  BackupLockedPreviewView.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/01.
//

import SwiftUI

import ChocofordUI
import SFSafeSymbols

#if os(macOS)
struct BackupLockedPreviewView: View {
    let isUnlocking: Bool
    let errorMessage: String?
    let systemUnlockAvailability: LockedContentSystemUnlockAvailability
    var onUnlock: () -> Void
    var onUseRecoveryKey: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemSymbol: .lockShield)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text(.localizable(.settingsBackupsLockedPreviewTitle))
                .font(.title3.weight(.semibold))

            Text(.localizable(.settingsBackupsLockedPreviewMessage))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            VStack(spacing: 6) {
                Button {
                    onUnlock()
                } label: {
                    if isUnlocking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(.localizable(.settingsBackupsUnlockPreviewButton), systemSymbol: unlockSystemSymbol)
                    }
                }
                .modernButtonStyle(style: .glassProminent, size: .large, shape: .capsule)
                .disabled(isUnlocking || !systemUnlockAvailability.isAvailable)
                .help(systemUnlockAvailability.buttonTitle)

                Button {
                    onUseRecoveryKey()
                } label: {
                    Text(.localizable(.lockedContentUseRecoveryKeyButton))
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(isUnlocking)
            }
            .padding(.top, 4)

            if let errorMessage {
                Label(errorMessage, systemSymbol: .exclamationmarkTriangle)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .padding()
    }

    private var unlockSystemSymbol: SFSymbol {
        switch systemUnlockAvailability.systemImage {
            case "touchid":
                return .touchid
            case "faceid":
                return .faceid
            case "key.shield":
                if #available(macOS 26.0, *) {
                    return .keyShield
                }
                return .key
            default:
                return .key
        }
    }
}

struct BackupEncryptedPreviewLoadingView: View {
    let isUnlocking: Bool
    let errorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            if isUnlocking {
                ProgressView()
                    .controlSize(.small)
            }

            if let errorMessage {
                Label(errorMessage, systemSymbol: .exclamationmarkTriangle)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .padding()
    }
}
#endif
