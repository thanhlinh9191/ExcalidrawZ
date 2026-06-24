//
//  SpotlightDelegate.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/25/25.
//

import Foundation
import CoreData
import CoreSpotlight
import Logging
import UniformTypeIdentifiers

actor SpotlightIndexingService {
    static let implementationVersion = 2
    static let implementationVersionDefaultsKey = "SpotlightIndexImplementationVersion"
    static let lastRefreshDefaultsKey = "LastSpotlightIndexRefreshTime"
    static let periodicRebuildInterval: TimeInterval = 30 * 24 * 60 * 60

    private static let domainIdentifier = "com.chocoford.excalidrawz.files"
    private static let legacyCoreDataDomainIdentifier = "com.chocoford.excalidraw.model"

    private let logger = Logger(label: "SpotlightIndexingService")
    private let index = CSSearchableIndex.default()
    private var scheduledRebuildTask: Task<Void, Never>?

    func indexFile(fileObjectID: NSManagedObjectID) async {
        do {
            guard let record = try await fetchRecord(fileObjectID: fileObjectID) else { return }
            try await apply(record)
        } catch {
            logger.warning("Failed to index file for Spotlight: \(error.localizedDescription)")
        }
    }

    func indexFile(id fileID: UUID) async {
        do {
            guard let record = try await fetchRecord(fileID: fileID) else { return }
            try await apply(record)
        } catch {
            logger.warning("Failed to index file for Spotlight: \(error.localizedDescription)")
        }
    }

    func indexFiles(ids fileIDs: [UUID]) async {
        let uniqueFileIDs = Array(Set(fileIDs))
        guard !uniqueFileIDs.isEmpty else { return }

        do {
            let records = try await fetchRecords(fileIDs: uniqueFileIDs)
            let indexableRecords = records.filter(\.isIndexable)
            let deletedIDs = Set(uniqueFileIDs).subtracting(indexableRecords.map(\.id))

            if !indexableRecords.isEmpty {
                try await indexSearchableItems(indexableRecords.map(searchableItem))
            }
            if !deletedIDs.isEmpty {
                try await deleteSearchableItems(withIdentifiers: deletedIDs.map(\.uuidString))
            }
        } catch {
            logger.warning("Failed to index files for Spotlight: \(error.localizedDescription)")
        }
    }

    func deleteFile(id fileID: UUID) async {
        do {
            try await deleteSearchableItems(withIdentifiers: [fileID.uuidString])
        } catch {
            logger.warning("Failed to delete Spotlight item for file \(fileID.uuidString): \(error.localizedDescription)")
        }
    }

    func scheduleRebuild(delayNanoseconds: UInt64 = 2_000_000_000) {
        scheduledRebuildTask?.cancel()
        scheduledRebuildTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
                guard !Task.isCancelled else { return }
                try await self?.rebuildFileIndex()
            } catch is CancellationError {
                return
            } catch {
                await self?.logScheduledRebuildFailure(error)
            }
        }
    }

    func rebuildFileIndex() async throws {
        scheduledRebuildTask?.cancel()
        scheduledRebuildTask = nil

        let records = try await fetchIndexableRecords()
        try await deleteSearchableItems(withDomainIdentifiers: [
            Self.domainIdentifier,
            Self.legacyCoreDataDomainIdentifier
        ])

        let items = records.map(searchableItem)
        guard !items.isEmpty else {
            recordRebuildCompleted()
            logger.info("Rebuilt Spotlight file index with 0 item.")
            return
        }

        try await indexSearchableItems(items)
        recordRebuildCompleted()
        logger.info("Rebuilt Spotlight file index with \(items.count) item(s).")
    }

    private func logScheduledRebuildFailure(_ error: Error) {
        logger.warning("Failed to rebuild Spotlight file index: \(error.localizedDescription)")
    }

    private func recordRebuildCompleted() {
        UserDefaults.standard.set(
            Date.now.formatted(.iso8601),
            forKey: Self.lastRefreshDefaultsKey
        )
        UserDefaults.standard.set(
            Self.implementationVersion,
            forKey: Self.implementationVersionDefaultsKey
        )
    }

    private func apply(_ record: FileRecord) async throws {
        if record.isIndexable {
            try await indexSearchableItems([searchableItem(for: record)])
        } else {
            try await deleteSearchableItems(withIdentifiers: [record.id.uuidString])
        }
    }

    private func fetchRecord(fileObjectID: NSManagedObjectID) async throws -> FileRecord? {
        let context = PersistenceController.shared.newTaskContext()
        return await context.perform {
            guard let file = context.object(with: fileObjectID) as? File else {
                return nil
            }
            return Self.makeRecord(from: file)
        }
    }

    private func fetchRecord(fileID: UUID) async throws -> FileRecord? {
        let context = PersistenceController.shared.newTaskContext()
        return try await context.perform {
            let fetchRequest = NSFetchRequest<File>(entityName: "File")
            fetchRequest.predicate = NSPredicate(format: "id == %@", fileID as CVarArg)
            fetchRequest.fetchLimit = 1
            guard let file = try context.fetch(fetchRequest).first else {
                return nil
            }
            return Self.makeRecord(from: file)
        }
    }

    private func fetchRecords(fileIDs: [UUID]) async throws -> [FileRecord] {
        let context = PersistenceController.shared.newTaskContext()
        return try await context.perform {
            let fetchRequest = NSFetchRequest<File>(entityName: "File")
            fetchRequest.predicate = NSPredicate(format: "id IN %@", fileIDs)
            return try context.fetch(fetchRequest)
                .compactMap(Self.makeRecord(from:))
        }
    }

    private func fetchIndexableRecords() async throws -> [FileRecord] {
        let context = PersistenceController.shared.newTaskContext()
        return try await context.perform {
            let fetchRequest = NSFetchRequest<File>(entityName: "File")
            fetchRequest.predicate = NSPredicate(format: "inTrash == NO")
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(key: "updatedAt", ascending: false),
                NSSortDescriptor(key: "createdAt", ascending: false)
            ]
            return try context.fetch(fetchRequest)
                .compactMap(Self.makeRecord(from:))
                .filter(\.isIndexable)
        }
    }

    private static func makeRecord(from file: File) -> FileRecord? {
        guard let id = file.id else { return nil }
        return FileRecord(
            id: id,
            name: file.name?.isEmpty == false ? file.name! : String(localizable: .generalUntitled),
            groupPath: groupPath(for: file.group),
            createdAt: file.createdAt,
            updatedAt: file.updatedAt,
            isIndexable: !file.inTrash
        )
    }

    private static func groupPath(for group: Group?) -> String? {
        var names: [String] = []
        var currentGroup = group
        var visitedGroupIDs: Set<NSManagedObjectID> = []

        while let group = currentGroup,
              !visitedGroupIDs.contains(group.objectID) {
            visitedGroupIDs.insert(group.objectID)
            if let name = group.name, !name.isEmpty {
                names.insert(name, at: 0)
            }
            currentGroup = group.parent
        }

        guard !names.isEmpty else { return nil }
        return names.joined(separator: " / ")
    }

    private func searchableItem(for record: FileRecord) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = record.name
        attributeSet.displayName = record.name
        attributeSet.contentDescription = record.groupPath
        attributeSet.containerTitle = record.groupPath
        attributeSet.contentCreationDate = record.createdAt
        attributeSet.contentModificationDate = record.updatedAt
        attributeSet.keywords = [record.name, record.groupPath]
            .compactMap { $0 }

        return CSSearchableItem(
            uniqueIdentifier: record.id.uuidString,
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attributeSet
        )
    }

    private func indexSearchableItems(_ items: [CSSearchableItem]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.indexSearchableItems(items) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func deleteSearchableItems(withIdentifiers identifiers: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.deleteSearchableItems(withIdentifiers: identifiers) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func deleteSearchableItems(withDomainIdentifiers domainIdentifiers: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.deleteSearchableItems(withDomainIdentifiers: domainIdentifiers) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private struct FileRecord: Sendable {
        var id: UUID
        var name: String
        var groupPath: String?
        var createdAt: Date?
        var updatedAt: Date?
        var isIndexable: Bool
    }
}

extension PersistenceController {
    public func refreshIndices() async throws {
        self.logger.info("[PersistenceController] Refresh Spotlight Index...")
        try await spotlightIndexingService.rebuildFileIndex()
        self.logger.info("[PersistenceController] Spotlight Index refreshed.")
    }
}
