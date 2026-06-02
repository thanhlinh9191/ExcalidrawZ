//
//  ExistingRecoveryKeyLockSheet.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/05/28.
//

import SwiftUI

struct ExistingRecoveryKeyLockSheet: View {
    let request: LockedFileAccessRequest
    var onComplete: (() -> Void)?

    var body: some View {
        RecoveryKeyInputSheet(
            title: String(localizable: .lockedContentUseExistingRecoveryKeyTitle),
            subtitle: request.fileName,
            message: String(localizable: .lockedContentUseExistingRecoveryKeyMessage),
            primaryButtonTitle: String(localizable: .lockFileTitle),
            headerLayout: .compact
        ) { recoveryKey in
            let unlockedCount = try await PersistenceController.shared.fileRepository
                .unlockLockedFiles(recoveryKey: recoveryKey, includeTrash: true)
            let didValidateBackupRecoveryKey: Bool
#if canImport(AppKit)
            if unlockedCount == 0 {
                didValidateBackupRecoveryKey = await canUnlockEncryptedBackupExcalidrawFile(with: recoveryKey)
            } else {
                didValidateBackupRecoveryKey = false
            }
#else
            didValidateBackupRecoveryKey = false
#endif
            guard unlockedCount > 0 || didValidateBackupRecoveryKey else {
                throw EncryptedContentError.decryptionFailed
            }
            try await PersistenceController.shared.fileRepository.lockFileContent(
                fileObjectID: request.fileObjectID,
                recoveryKey: recoveryKey
            )
            onComplete?()
        }
    }
}
