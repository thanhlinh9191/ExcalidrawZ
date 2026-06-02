//
//  BackupsHomeView.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/01.
//

import SwiftUI

import ChocofordUI
import SFSafeSymbols

#if os(macOS)
struct BackupsPlaceholderView: View {
    var body: some View {
        VStack(spacing: 20) {
            BackupHeroIcon()

            VStack(spacing: 6) {
                Text(.localizable(.settingsBackupsName))
                    .font(.largeTitle.weight(.semibold))

                Text(.localizable(.settingsBackupsDescription))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            VStack(spacing: 10) {
                BackupInfoRow(
                    systemSymbol: .clockArrowCirclepath,
                    title: String(localizable: .settingsBackupsDailySnapshotsTitle),
                    message: String(localizable: .settingsBackupsDailySnapshotsMessage)
                )

                BackupInfoRow(
                    systemSymbol: .checkmarkShield,
                    title: String(localizable: .settingsBackupsEncryptedStorageTitle),
                    message: backupEncryptionDisclosure
                )
            }
            .frame(maxWidth: 480)
        }
        .padding(32)
        .frame(maxWidth: 560)
    }
}

struct BackupHomeView: View {
    let backup: URL
    let selectedBackupSize: Int
    let isExporting: Bool
    var onExport: (String) -> Void
    var onRevealInFinder: () -> Void
    var onDelete: () -> Void

    private var title: String {
        String(
            localizable: .backupName(
                (try? backup.resourceValues(forKeys: [.creationDateKey]).creationDate?.formatted()) ?? String(localizable: .generalUnknown)
            )
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            BackupHeroIcon()

            VStack(spacing: 6) {
                Text(title)
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(backupEncryptionDisclosure)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: 10) {
                BackupSummaryPill(
                    systemSymbol: .internaldrive,
                    title: backupTotalSizeTitle,
                    value: selectedBackupSize.formatted(.byteCount(style: .file))
                )

                BackupSummaryPill(
                    systemSymbol: .checkmarkShield,
                    title: String(localizable: .settingsBackupsStorageTitle),
                    value: String(localizable: .settingsBackupsEncryptedValue)
                )
            }
            .frame(maxWidth: 460)

            HStack {
                Button {
                    onExport(title)
                } label: {
                    HStack(spacing: 6) {
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Label(.localizable(.backupButtonExport), systemSymbol: .squareAndArrowUp)
                    }
                }
                .modernButtonStyle(style: .glass, shape: .modern)
                .disabled(isExporting)

#if DEBUG
                Button {
                    onRevealInFinder()
                } label: {
                    Label(.localizable(.generalButtonRevealInFinder), systemSymbol: .docViewfinder)
                }
                .modernButtonStyle(style: .glass, shape: .modern)
#endif

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label(.localizable(.backupButtonDelete), systemSymbol: .trash)
                }
                .modernButtonStyle(style: .glass, shape: .modern)
            }
        }
        .padding(20)
        .frame(maxWidth: 560)
    }
}

private var backupEncryptionDisclosure: String {
    String(localizable: .settingsBackupsEncryptedStorageMessage)
}

private var backupTotalSizeTitle: String {
    var title = String(localizable: .generalTotalSizeLabel)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    while title.last == ":" || title.last == "：" {
        title.removeLast()
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return title
}

private struct BackupHeroIcon: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .overlay {
                    Circle()
                        .stroke(.separator.opacity(0.7), lineWidth: 1)
                }
                .frame(width: 82, height: 82)
                .position(x: 47, y: 47)

            Image(systemSymbol: .externaldrive)
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 82, height: 82)
                .position(x: 47, y: 47)

            ZStack {
                Circle()
                    .fill(.background)
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
                Image(systemSymbol: .checkmarkShieldFill)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.green)
            }
            .frame(width: 30, height: 30)
            .position(x: 67, y: 67)
        }
        .frame(width: 82, height: 82)
    }
}

private struct BackupInfoRow: View {
    let systemSymbol: SFSymbol
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemSymbol: systemSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            if #available(macOS 26.0, iOS 26.0, *) {
                Capsule()
                    .fill(.regularMaterial)
                    .overlay {
                        Capsule()
                            .stroke(.separator.opacity(0.65), lineWidth: 1)
                    }
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.separator.opacity(0.65), lineWidth: 1)
                    }
            }
        }
    }
}

private struct BackupSummaryPill: View {
    let systemSymbol: SFSymbol
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemSymbol: systemSymbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.separator.opacity(0.65), lineWidth: 1)
                }
        }
    }
}
#endif
