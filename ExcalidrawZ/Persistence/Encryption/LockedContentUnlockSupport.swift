//
//  LockedContentUnlockSupport.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/05/27.
//

import Foundation
import LocalAuthentication
import Security

enum LockedContentErrorPresenter {
    static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

enum LockedContentSecurityDelay {
    private static let failedAttemptMinimumDuration: TimeInterval = 1

    static func waitBeforeShowingFailure(startedAt: Date) async {
        let remaining = failedAttemptMinimumDuration - Date().timeIntervalSince(startedAt)
        guard remaining > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
    }
}

enum LockedContentSymbols {
    static let lockShield = "lock.shield"
    static let removeLock = "shield.slash"

    static var keyShield: String {
        if #available(macOS 26.0, iOS 26.0, *) {
            return "key.shield"
        } else {
            return "key"
        }
    }
}

struct LockedContentSystemUnlockAvailability: Equatable {
    let isAvailable: Bool
    let buttonTitle: String
    let systemImage: String

    static var unavailable: Self {
        .init(
            isAvailable: false,
            buttonTitle: String(localizable: .lockedContentSystemUnlockMacPassword),
            systemImage: LockedContentSymbols.keyShield
        )
    }
}

enum LockedContentSystemUnlockError: LocalizedError, Equatable {
    case unavailable
    case noSavedRecoveryKey
    case canceled
    case authenticationFailed
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
            case .unavailable:
                String(localizable: .lockedContentSystemUnlockErrorUnavailable)
            case .noSavedRecoveryKey:
                String(localizable: .lockedContentSystemUnlockErrorNoSavedRecoveryKey)
            case .canceled:
                String(localizable: .lockedContentSystemUnlockErrorCanceled)
            case .authenticationFailed:
                String(localizable: .lockedContentSystemUnlockErrorAuthenticationFailed)
            case .keychainError:
                String(localizable: .lockedContentSystemUnlockErrorKeychain)
        }
    }

    var recoverySuggestion: String? {
        switch self {
            case .unavailable, .noSavedRecoveryKey, .authenticationFailed, .keychainError:
                String(localizable: .lockedContentSystemUnlockSuggestionEnterRecoveryKey)
            case .canceled:
                nil
        }
    }
}

enum LockedContentSystemUnlockReason {
    static let lockFile = String(localizable: .lockedContentSystemUnlockReasonLockFile)
    static let unlockFile = String(localizable: .lockedContentSystemUnlockReasonUnlockFile)
    static let manageLockedContent = String(localizable: .lockedContentSystemUnlockReasonManageLockedContent)
    static let archiveLockedFiles = String(localizable: .lockedContentSystemUnlockReasonArchiveLockedFiles)
    static let exportBackup = String(localizable: .lockedContentSystemUnlockReasonExportBackup)
    static let previewBackupFile = String(localizable: .lockedContentSystemUnlockReasonPreviewBackupFile)
}

enum LockedContentSavedRecoveryKeyState: Equatable {
    case available
    case missing
}

enum LockedContentSystemUnlockStore {
    private static let service = "\(Bundle.main.bundleIdentifier ?? "com.chocoford.ExcalidrawZ").locked-content"
    private static let account = "UnifiedRecoveryKey"
    private static let savedRecoveryKeyMarkerKey = "LockedContentSystemUnlockStore.hasSavedRecoveryKey"
    private static let loadCoordinator = RecoveryKeyLoadCoordinator()

    private actor RecoveryKeyLoadCoordinator {
        private var inFlight: Task<RecoveryKey, Error>?

        func load(reason: String) async throws -> RecoveryKey {
            if let inFlight {
                return try await inFlight.value
            }

            let task = Task {
                try await LockedContentSystemUnlockStore.loadRecoveryKeyDirect(reason: reason)
            }
            inFlight = task
            defer { inFlight = nil }
            return try await task.value
        }
    }

    static func availability() -> LockedContentSystemUnlockAvailability {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable
        }

        switch context.biometryType {
            case .touchID:
                return .init(
                    isAvailable: true,
                    buttonTitle: String(localizable: .lockedContentSystemUnlockTouchIDMacPassword),
                    systemImage: "touchid"
                )
            case .faceID:
                return .init(
                    isAvailable: true,
                    buttonTitle: String(localizable: .lockedContentSystemUnlockFaceIDPasscode),
                    systemImage: "faceid"
                )
            case .opticID:
                return .init(
                    isAvailable: true,
                    buttonTitle: String(localizable: .lockedContentSystemUnlockOpticIDPasscode),
                    systemImage: "opticid"
                )
            case .none:
#if os(macOS)
                return .init(
                    isAvailable: true,
                    buttonTitle: String(localizable: .lockedContentSystemUnlockMacPassword),
                    systemImage: LockedContentSymbols.keyShield
                )
#else
                return .init(
                    isAvailable: true,
                    buttonTitle: String(localizable: .lockedContentSystemUnlockDevicePasscode),
                    systemImage: LockedContentSymbols.keyShield
                )
#endif
            @unknown default:
                return .init(
                    isAvailable: true,
                    buttonTitle: String(localizable: .lockedContentSystemUnlockGeneric),
                    systemImage: LockedContentSymbols.keyShield
                )
        }
    }

    static func save(_ recoveryKey: RecoveryKey) throws {
        var updatedAttributes: [String: Any] = [:]
        updatedAttributes[kSecValueData as String] = recoveryKey.storageData

        let query = synchronizableQuery()
        let updateStatus = SecItemUpdate(query as CFDictionary, updatedAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            deleteLegacyLocalRecoveryKey()
            UserDefaults.standard.set(true, forKey: savedRecoveryKeyMarkerKey)
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw keychainError(for: updateStatus)
        }

        var attributes = query
        attributes.merge(updatedAttributes) { _, newValue in newValue }
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(query as CFDictionary, updatedAttributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw keychainError(for: updateStatus)
            }
        } else if status != errSecSuccess {
            throw keychainError(for: status)
        }
        deleteLegacyLocalRecoveryKey()
        UserDefaults.standard.set(true, forKey: savedRecoveryKeyMarkerKey)
    }

    static func deleteSavedRecoveryKey() {
        SecItemDelete(synchronizableQuery() as CFDictionary)
        deleteLegacyLocalRecoveryKey()
        UserDefaults.standard.set(false, forKey: savedRecoveryKeyMarkerKey)
    }

    static func hasSavedRecoveryKey() -> Bool {
        (try? savedRecoveryKeyState()) == .available
    }

    static func savedRecoveryKeyState() throws -> LockedContentSavedRecoveryKeyState {
        let synchronizableState = try savedRecoveryKeyState(query: synchronizableQuery())
        if synchronizableState == .available {
            return .available
        }

        return try savedRecoveryKeyState(query: legacyLocalQuery())
    }

    private static func savedRecoveryKeyState(query: [String: Any]) throws -> LockedContentSavedRecoveryKeyState {
        var query = query
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnAttributes as String] = true
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
            case errSecSuccess:
                UserDefaults.standard.set(true, forKey: savedRecoveryKeyMarkerKey)
                return .available
            case errSecItemNotFound:
                return .missing
            case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
                UserDefaults.standard.set(true, forKey: savedRecoveryKeyMarkerKey)
                return .available
            default:
                throw LockedContentSystemUnlockError.keychainError(status)
        }
    }

    static func shouldPromptAutomatically() -> Bool {
        UserDefaults.standard.bool(forKey: savedRecoveryKeyMarkerKey)
    }

    static func noteMissingSavedRecoveryKey() {
        UserDefaults.standard.set(false, forKey: savedRecoveryKeyMarkerKey)
    }

    static func loadRecoveryKey(reason: String) async throws -> RecoveryKey {
        try await loadCoordinator.load(reason: reason)
    }

    private static func loadRecoveryKeyDirect(reason: String) async throws -> RecoveryKey {
        let context = LAContext()
        context.localizedReason = reason
        context.touchIDAuthenticationAllowableReuseDuration = 10

        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            throw LockedContentSystemUnlockError.unavailable
        }

        try await authenticate(context: context, reason: reason)
        return try loadRecoveryKeySync(context: context)
    }

    private static func authenticate(context: LAContext, reason: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: authenticationError(for: error))
                }
            }
        }
    }

    private static func loadRecoveryKeySync(context: LAContext) throws -> RecoveryKey {
        do {
            let recoveryKey = try loadSynchronizableRecoveryKey()
            UserDefaults.standard.set(true, forKey: savedRecoveryKeyMarkerKey)
            return recoveryKey
        } catch LockedContentSystemUnlockError.noSavedRecoveryKey {
            let recoveryKey = try loadLegacyLocalRecoveryKey(context: context)
            try? save(recoveryKey)
            return recoveryKey
        }
    }

    private static func loadSynchronizableRecoveryKey() throws -> RecoveryKey {
        var query = synchronizableQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        return try loadRecoveryKey(query: query)
    }

    private static func loadLegacyLocalRecoveryKey(context: LAContext) throws -> RecoveryKey {
        var query = legacyLocalQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context

        let recoveryKey = try loadRecoveryKey(query: query)
        UserDefaults.standard.set(true, forKey: savedRecoveryKeyMarkerKey)
        return recoveryKey
    }

    private static func loadRecoveryKey(query: [String: Any]) throws -> RecoveryKey {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            let error = keychainError(for: status)
            if error == .noSavedRecoveryKey {
                noteMissingSavedRecoveryKey()
            }
            throw error
        }
        guard let data = item as? Data else {
            throw LockedContentSystemUnlockError.noSavedRecoveryKey
        }

        let recoveryKey = try RecoveryKey(storageData: data)
        UserDefaults.standard.set(true, forKey: savedRecoveryKeyMarkerKey)
        return recoveryKey
    }

    private static func authenticationError(for error: Error?) -> LockedContentSystemUnlockError {
        guard let nsError = error as NSError?,
              nsError.domain == LAError.errorDomain,
              let code = LAError.Code(rawValue: nsError.code) else {
            return .authenticationFailed
        }

        switch code {
            case .userCancel, .systemCancel, .appCancel, .userFallback:
                return .canceled
            case .passcodeNotSet, .biometryNotAvailable, .biometryNotEnrolled, .notInteractive:
                return .unavailable
            case .authenticationFailed, .biometryLockout:
                return .authenticationFailed
            default:
                return .authenticationFailed
        }
    }

    private static func keychainError(for status: OSStatus) -> LockedContentSystemUnlockError {
        switch status {
            case errSecItemNotFound:
                .noSavedRecoveryKey
            case errSecUserCanceled:
                .canceled
            case errSecAuthFailed:
                .authenticationFailed
            default:
                .keychainError(status)
        }
    }

    private static func synchronizableQuery() -> [String: Any] {
        var query = baseQuery()
        query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        return query
    }

    private static func legacyLocalQuery() -> [String: Any] {
        baseQuery()
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func deleteLegacyLocalRecoveryKey() {
        SecItemDelete(legacyLocalQuery() as CFDictionary)
    }
}
