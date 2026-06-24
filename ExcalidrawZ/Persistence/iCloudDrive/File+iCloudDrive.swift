//
//  File+iCloudDrive.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/20.
//

import Foundation
import CoreData
import Logging

extension File {
    private static let logger = Logger(label: "File+FileStorage")

    /// Load file content from storage (local/iCloud)
    /// Automatically checks iCloud for newer versions before returning
    /// Falls back to CoreData content if storage is unavailable
    func loadContent() async throws -> Data {
        guard let context = self.managedObjectContext else {
            struct NoContextError: LocalizedError {
                var errorDescription: String? { "File object has no managed object context" }
            }
            throw NoContextError()
        }

        // Use objectID to safely access object across async boundary
        let objectID = self.objectID

        // Read all Core Data properties in context.perform for thread safety
        let (filePath, fileID, content, name): (String?, UUID?, Data?, String?) = await context.perform {
            guard let file = context.object(with: objectID) as? File else {
                return (nil, nil, nil, nil)
            }
            return (file.filePath, file.id, file.content, file.name)
        }

        // Try to load from storage first (local/iCloud with bidirectional sync)
        if let filePath = filePath, let fileID = fileID {
            do {
                let data = try await FileStorageManager.shared.loadContent(relativePath: filePath, fileID: fileID.uuidString)
                Self.logger.debug("Loaded file content from storage id=\(fileID.uuidString) bytes=\(data.count.formatted(.byteCount(style: .file)))")
                if EncryptedContentService.isEncryptedEnvelope(data) {
                    try LockedContentReadPolicy.ensureProtectedContentAccessAllowed()
                    return try await LockedContentUnlockSession.shared.decrypt(
                        data,
                        expectedContentType: "file",
                        expectedContentID: fileID.uuidString
                    )
                }
                return data
            } catch let error as EncryptedContentError {
                throw error
            } catch {
                Self.logger.warning("\(error.localizedDescription), falling back to CoreData.")
            }
        }

        // Fallback to CoreData content
        if let content = content {
            if let fileID {
                Self.logger.warning("Falling back to Core Data file content id=\(fileID.uuidString) bytes=\(content.count.formatted(.byteCount(style: .file)))")
                if EncryptedContentService.isEncryptedEnvelope(content) {
                    try LockedContentReadPolicy.ensureProtectedContentAccessAllowed()
                    return try await LockedContentUnlockSession.shared.decrypt(
                        content,
                        expectedContentType: "file",
                        expectedContentID: fileID.uuidString
                    )
                }
            } else {
                Self.logger.warning("Falling back to Core Data file content id=nil bytes=\(content.count.formatted(.byteCount(style: .file)))")
            }
            return content
        }

        throw AppError.fileError(.contentNotAvailable(filename: name ?? String(localizable: .generalUnknown)))
    }

    /// Update file path and clear content (call this after successfully saving to storage)
    /// Must be called on the entity's managedObjectContext
    func updateAfterSavingToStorage(filePath: String) {
        self.filePath = filePath
        self.content = nil // Clear CoreData content to save space
        self.updatedAt = .now
    }

    /// Update content when iCloud is unavailable (fallback)
    /// Must be called on the entity's managedObjectContext
    func updateContentFallback(data: Data) {
        self.content = data
        self.updatedAt = .now
    }

    /// Clear all content references
    /// Must be called on the entity's managedObjectContext
    func clearContentReferences() {
        self.content = nil
        self.filePath = nil
    }
}
