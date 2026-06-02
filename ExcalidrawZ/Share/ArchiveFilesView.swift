//
//  ArchiveFilesView.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/05/28.
//

import CoreData
import SwiftUI

import ChocofordUI
import SFSafeSymbols

struct ArchiveFilesView: View {
#if os(macOS)
    static let preferredSheetHeight: CGFloat = 320
    private let macOSActionsSectionHeight: CGFloat = 36
#endif

    @Environment(\.managedObjectContext) private var viewContext

    var dismissAction: () -> Void

    @State private var isArchiveFilesExporterPresented = false
    @State private var isArchiving = false
    @State private var archiveResult: ArchiveResult?
    @State private var lockedFileCountForArchive: Int?
    @State private var includeLockedFilesInArchive = false
    @State private var archiveRecoveryKey: RecoveryKey?
    @State private var archiveErrorMessage: String?

    var body: some View {
        ShareSubViewContainer(dismiss: dismissAction) {
            Center {
                VStack(spacing: 16) {
                    previewSection
                    lockedFilesOption
                    messageSection
                    actionsView
                }
                .frame(maxWidth: 390)
            }
        }
        .task {
            await loadLockedFileCountForArchive()
        }
        .archiveFilesExporter(
            isPresented: $isArchiveFilesExporterPresented,
            context: viewContext,
            includeLockedFiles: includeLockedFilesInArchive,
            recoveryKey: archiveRecoveryKey,
            onComplete: { result in
                isArchiving = false
                archiveRecoveryKey = nil
                switch result {
                    case .success(let archiveResult):
                        self.archiveResult = archiveResult
                    case .failure(let error):
                        archiveErrorMessage = LockedContentErrorPresenter.message(for: error)
                }
            },
            onCancellation: {
                isArchiving = false
                archiveRecoveryKey = nil
            }
        )
    }

    @ViewBuilder
    private var previewSection: some View {
        VStack(spacing: 8) {
            Text(.localizable(.archiveFilesTitle))
                .font(.title2)

            Text(.localizable(.archiveFilesDescription))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
        }
    }

    @ViewBuilder
    private var lockedFilesOption: some View {
        ZStack {
            if let lockedFileCountForArchive {
                if lockedFileCountForArchive > 0 {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "lock.shield")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(.localizable(.archiveFilesIncludeLockedFilesTitle))
                                .font(.callout.weight(.medium))
                            Text(.localizable(.archiveFilesIncludeLockedFilesDescription(lockedFileCountForArchive)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 12)

                        Toggle(String(localizable: .archiveFilesIncludeLockedFilesTitle), isOn: $includeLockedFilesInArchive)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .disabled(isArchiving)
                    }
                } else {
                    Label(.localizable(.archiveFilesNoLockedFilesMessage), systemImage: "lock.shield")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(.localizable(.archiveFilesCheckingLockedFilesMessage))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var resultMessage: some View {
        if let archiveErrorMessage {
            Label(archiveErrorMessage, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        } else if let archiveResult, !archiveResult.failedFiles.isEmpty {
            Label(.localizable(.archiveFilesFailedMessage(archiveResult.failedFiles.count)), systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var messageSection: some View {
        ZStack(alignment: .top) {
            resultMessage
        }
        .frame(height: 22, alignment: .top)
    }

    @ViewBuilder
    private var actionsView: some View {
        HStack {
            Spacer()

            Button {
                Task { @MainActor in
                    await exportArchive()
                }
            } label: {
                if isArchiving {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(.localizable(.archiveFilesExportingMessage))
                    }
                    .padding(.horizontal, 6)
                } else {
                    Label(.localizable(.archiveFilesExportButton), systemSymbol: .squareAndArrowDown)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                }
            }
            .modernButtonStyle(style: .glassProminent, size: .large, shape: .modern)
            .disabled(isArchiving || lockedFileCountForArchive == nil)

            Spacer()
        }
        .modernButtonStyle(style: .glass, size: .regular, shape: .modern)
#if os(macOS)
        .frame(height: macOSActionsSectionHeight)
#endif
    }

    @MainActor
    private func loadLockedFileCountForArchive() async {
        guard lockedFileCountForArchive == nil else { return }
        do {
            let files = try await PersistenceController.shared.fileRepository.listLockedFiles()
            lockedFileCountForArchive = files.count
            if files.isEmpty {
                includeLockedFilesInArchive = false
            }
        } catch {
            lockedFileCountForArchive = 0
            archiveErrorMessage = LockedContentErrorPresenter.message(for: error)
        }
    }

    @MainActor
    private func exportArchive() async {
        archiveErrorMessage = nil
        archiveResult = nil
        isArchiving = true

        let shouldIncludeLockedFiles = includeLockedFilesInArchive && (lockedFileCountForArchive ?? 0) > 0
        if shouldIncludeLockedFiles {
            do {
                archiveRecoveryKey = try await LockedContentSystemUnlockStore.loadRecoveryKey(
                    reason: LockedContentSystemUnlockReason.archiveLockedFiles
                )
            } catch let unlockError as LockedContentSystemUnlockError {
                isArchiving = false
                archiveRecoveryKey = nil
                if unlockError != .canceled {
                    archiveErrorMessage = LockedContentErrorPresenter.message(for: unlockError)
                }
                return
            } catch {
                isArchiving = false
                archiveRecoveryKey = nil
                archiveErrorMessage = LockedContentErrorPresenter.message(for: error)
                return
            }
        } else {
            archiveRecoveryKey = nil
        }

        isArchiveFilesExporterPresented = true
    }
}
