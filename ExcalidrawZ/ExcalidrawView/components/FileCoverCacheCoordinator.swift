//
//  FileCoverCacheCoordinator.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/6/23.
//

import CoreData
import Logging
import SwiftUI

extension Notification.Name {
    static let filePreviewDidUpdate = Notification.Name("FilePreviewDidUpdate")
}

@MainActor
final class FileCoverCacheCoordinator: ObservableObject {
    static let shared = FileCoverCacheCoordinator()

    enum Priority: Int {
        case background = 0
        case recently = 5
        case userInitiated = 10
    }

    enum Source {
        case activeFile(FileState.ActiveFile)
        case excalidrawFile(ExcalidrawFile)

        var id: String {
            switch self {
                case .activeFile(let file):
                    file.id
                case .excalidrawFile(let file):
                    file.id
            }
        }
    }

    private struct Job {
        let source: Source
        let colorScheme: ColorScheme
        let forceRefresh: Bool
        let priority: Priority
        let sequence: Int
        let retryCount: Int

        var cacheKey: String {
            FileItemPreviewCache.cacheKey(forID: source.id, colorScheme: colorScheme) as String
        }
    }

    private enum GenerationResult: Equatable {
        case completed
        case retry
    }

    private weak var fileState: FileState?
    private weak var lockedContentState: LockedContentStateStore?
    private weak var context: NSManagedObjectContext?

    private var queue: [Job] = []
    private var queuedKeys: Set<String> = []
    private var inFlightKeys: Set<String> = []
    private var nextSequence = 0
    private var processingTask: Task<Void, Never>?
    private var prewarmTask: Task<Void, Never>?
    private var currentColorScheme: ColorScheme = .light

    private let cache = FileItemPreviewCache.shared
    private let logger = Logger(label: "FileCoverCacheCoordinator")
    private let maximumRetryCount = 8

    private init() {}

    func register(
        fileState: FileState,
        lockedContentState: LockedContentStateStore,
        context: NSManagedObjectContext
    ) {
        self.fileState = fileState
        self.lockedContentState = lockedContentState
        self.context = context
    }

    func request(
        source: Source,
        colorScheme: ColorScheme,
        priority: Priority = .background,
        forceRefresh: Bool = false
    ) {
        currentColorScheme = colorScheme
        let cacheKey = FileItemPreviewCache.cacheKey(
            forID: source.id,
            colorScheme: colorScheme
        ) as String

        if !forceRefresh,
           cache.object(forKey: cacheKey as NSString) != nil {
            return
        }

        if let existingJob = queue.first(where: { $0.cacheKey == cacheKey }) {
            let shouldReplace = forceRefresh || priority.rawValue > existingJob.priority.rawValue
            guard shouldReplace else { return }
            queue.removeAll { $0.cacheKey == cacheKey }
            queuedKeys.remove(cacheKey)
        }

        guard !inFlightKeys.contains(cacheKey) else { return }
        guard !shouldSkipLockedSource(source) else { return }

        queuedKeys.insert(cacheKey)
        queue.append(Job(
            source: source,
            colorScheme: colorScheme,
            forceRefresh: forceRefresh,
            priority: priority,
            sequence: nextSequence,
            retryCount: 0
        ))
        nextSequence += 1
        sortQueue()
        startProcessingIfNeeded()
    }

    func request(
        activeFile: FileState.ActiveFile,
        colorScheme: ColorScheme,
        priority: Priority = .background,
        forceRefresh: Bool = false
    ) {
        request(
            source: .activeFile(activeFile),
            colorScheme: colorScheme,
            priority: priority,
            forceRefresh: forceRefresh
        )
    }

    func prioritizeRecentlyVisibleFiles(
        _ files: [FileState.ActiveFile],
        colorScheme: ColorScheme,
        limit: Int = 20
    ) {
        currentColorScheme = colorScheme
        for file in files.prefix(limit) {
            request(
                activeFile: file,
                colorScheme: colorScheme,
                priority: .recently
            )
        }
    }

    func scheduleLibraryPrewarm(
        colorScheme: ColorScheme,
        delay: UInt64 = 1_500_000_000
    ) {
        currentColorScheme = colorScheme
        prewarmTask?.cancel()
        prewarmTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            enqueueRecentlyUsedCovers(colorScheme: colorScheme)
            enqueueMissingLibraryCovers(colorScheme: colorScheme)
        }
    }

    func cancelPrewarm() {
        prewarmTask?.cancel()
        prewarmTask = nil
    }

    func cacheCurrentViewportPreview(for activeFile: FileState.ActiveFile) async {
        guard !shouldSkipLockedSource(.activeFile(activeFile)),
              let coordinator = fileState?.excalidrawWebCoordinator,
              !coordinator.isLoading,
              coordinator.documentSyncController.currentLoadedFileID == activeFile.id else {
            return
        }

        do {
            let image = try await coordinator.exportCurrentViewportToPNG()
            guard let thumbnail = makeThumbnail(from: image) else {
                logger.warning("Failed to downsample current viewport preview for \(activeFile.id)")
                return
            }
            let cacheKey = FileItemPreviewCache.cacheKey(
                forID: activeFile.id,
                colorScheme: currentColorScheme
            )
            cache.setObject(thumbnail, forKey: cacheKey)
            logger.debug("Cached current viewport preview for \(activeFile.id)")
            NotificationCenter.default.post(
                name: .filePreviewDidUpdate,
                object: activeFile.id
            )
        } catch {
            logger.debug("Failed to cache current viewport preview for \(activeFile.id): \(error)")
        }
    }

    private func sortQueue() {
        queue.sort {
            if $0.priority.rawValue != $1.priority.rawValue {
                return $0.priority.rawValue > $1.priority.rawValue
            }
            return $0.sequence < $1.sequence
        }
    }

    private func startProcessingIfNeeded() {
        guard processingTask == nil else { return }
        processingTask = Task { @MainActor in
            await processQueue()
        }
    }

    private func processQueue() async {
        defer {
            processingTask = nil
            if !queue.isEmpty {
                startProcessingIfNeeded()
            }
        }

        while !Task.isCancelled, !queue.isEmpty {
            let job = queue.removeFirst()
            queuedKeys.remove(job.cacheKey)

            if job.priority.rawValue < Priority.userInitiated.rawValue,
               fileState?.currentActiveFile != nil {
                queuedKeys.insert(job.cacheKey)
                queue.append(job)
                sortQueue()
                try? await Task.sleep(nanoseconds: 750_000_000)
                continue
            }

            if !job.forceRefresh,
               cache.object(forKey: job.cacheKey as NSString) != nil {
                continue
            }

            inFlightKeys.insert(job.cacheKey)
            let result = await generate(job)
            inFlightKeys.remove(job.cacheKey)

            if result == .retry {
                try? await Task.sleep(nanoseconds: 750_000_000)
                guard !Task.isCancelled else { return }
                requeue(job)
            }
        }
    }

    private func requeue(_ job: Job) {
        guard job.retryCount < maximumRetryCount else {
            logger.warning("Dropped preview generation after retries for \(job.source.id)")
            return
        }

        guard (job.forceRefresh || cache.object(forKey: job.cacheKey as NSString) == nil),
              !queuedKeys.contains(job.cacheKey),
              !inFlightKeys.contains(job.cacheKey) else {
            return
        }

        queuedKeys.insert(job.cacheKey)
        queue.append(Job(
            source: job.source,
            colorScheme: job.colorScheme,
            forceRefresh: job.forceRefresh,
            priority: job.priority,
            sequence: nextSequence,
            retryCount: job.retryCount + 1
        ))
        nextSequence += 1
        sortQueue()
    }

    private func enqueueRecentlyUsedCovers(colorScheme: ColorScheme) {
        guard let context else { return }

        let fileRequest = NSFetchRequest<File>(entityName: "File")
        fileRequest.predicate = NSPredicate(format: "inTrash == NO")
        fileRequest.sortDescriptors = [
            NSSortDescriptor(key: "visitedAt", ascending: false),
            NSSortDescriptor(key: "updatedAt", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        fileRequest.fetchLimit = 20

        let collaborationRequest = NSFetchRequest<CollaborationFile>(entityName: "CollaborationFile")
        collaborationRequest.predicate = NSPredicate(format: "inTrash == NO")
        collaborationRequest.sortDescriptors = [
            NSSortDescriptor(key: "visitedAt", ascending: false),
            NSSortDescriptor(key: "updatedAt", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        collaborationRequest.fetchLimit = 20

        do {
            let files = try context.fetch(fileRequest)
            let collaborationFiles = try context.fetch(collaborationRequest)
            let recentFiles: [FileState.ActiveFile] = files.map { .file($0) }
                + collaborationFiles.map { .collaborationFile($0) }

            for file in recentFiles.sorted(by: { lhs, rhs in
                recentDate(for: lhs) > recentDate(for: rhs)
            }).prefix(20) {
                request(
                    activeFile: file,
                    colorScheme: colorScheme,
                    priority: .recently
                )
            }
        } catch {
            logger.warning("Failed to enqueue recently used cover prewarm: \(error)")
        }
    }

    private func enqueueMissingLibraryCovers(colorScheme: ColorScheme) {
        guard let context else { return }

        let fetchRequest = NSFetchRequest<File>(entityName: "File")
        fetchRequest.predicate = NSPredicate(format: "inTrash == NO")
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "updatedAt", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]

        do {
            let files = try context.fetch(fetchRequest)
            for file in files {
                let activeFile = FileState.ActiveFile.file(file)
                if let lockState = lockedContentState?.previewLockState(for: activeFile),
                   lockState == .locked {
                    continue
                }
                request(
                    activeFile: activeFile,
                    colorScheme: colorScheme,
                    priority: .background
                )
            }
        } catch {
            logger.warning("Failed to enqueue library cover prewarm: \(error)")
        }
    }

    private func shouldSkipLockedSource(_ source: Source) -> Bool {
        guard case .activeFile(let activeFile) = source,
              case .file = activeFile,
              let lockState = lockedContentState?.previewLockState(for: activeFile) else {
            return false
        }

        return lockState == .locked
    }

    private func recentDate(for file: FileState.ActiveFile) -> Date {
        switch file {
            case .file(let file):
                return file.visitedAt ?? file.updatedAt ?? file.createdAt ?? .distantPast
            case .collaborationFile(let file):
                return file.visitedAt ?? file.updatedAt ?? file.createdAt ?? .distantPast
            case .localFile(let url), .temporaryFile(let url):
                let resourceValues = try? url.resourceValues(forKeys: [
                    .contentModificationDateKey,
                    .creationDateKey
                ])
                return max(
                    resourceValues?.contentModificationDate ?? .distantPast,
                    resourceValues?.creationDate ?? .distantPast
                )
        }
    }

    private func generate(_ job: Job) async -> GenerationResult {
        guard let coordinator = await waitForPreviewExporter() else {
            logger.debug("Preview export coordinator unavailable for \(job.source.id), retry=\(job.retryCount)")
            return .retry
        }

        do {
            var excalidrawFile: ExcalidrawFile
            let mediaHydrationFileObjectID: NSManagedObjectID?

            switch job.source {
                case .activeFile(let activeFile):
                    switch activeFile {
                        case .file(let file):
                            mediaHydrationFileObjectID = file.objectID
                            if let lockedContentState {
                                await lockedContentState.refresh(
                                    fileObjectID: file.objectID,
                                    fileID: activeFile.id
                                )
                                if lockedContentState.previewLockState(for: activeFile) == .locked {
                                    cache.removePreviewCache(forID: activeFile.id)
                                    NotificationCenter.default.post(
                                        name: .filePreviewDidUpdate,
                                        object: activeFile.id
                                    )
                                    return .completed
                                }
                            }
                            let content = try await file.loadContent()
                            excalidrawFile = try ExcalidrawFile(data: content, id: activeFile.id)

                        case .localFile(let url):
                            mediaHydrationFileObjectID = nil
                            excalidrawFile = try await loadLocalFileForPreview(at: url)

                        case .temporaryFile(let url):
                            mediaHydrationFileObjectID = nil
                            excalidrawFile = try ExcalidrawFile(contentsOf: url)

                        case .collaborationFile(let collaborationFile):
                            mediaHydrationFileObjectID = nil
                            let content = try await collaborationFile.loadContent()
                            excalidrawFile = try ExcalidrawFile(
                                data: content,
                                id: collaborationFile.id?.uuidString
                            )
                    }

                case .excalidrawFile(let file):
                    mediaHydrationFileObjectID = nil
                    excalidrawFile = file
            }

            excalidrawFile = await hydrateMediaForPreview(
                excalidrawFile,
                fileObjectID: mediaHydrationFileObjectID
            )

            guard !Task.isCancelled else { return .completed }

            let image: PlatformImage
            do {
                image = try await exportViewportPreview(
                    for: excalidrawFile,
                    colorScheme: job.colorScheme,
                    coordinator: coordinator
                )
            } catch {
                guard !Task.isCancelled else { return .completed }
                logger.debug("Failed to export viewport preview for \(job.source.id): \(error), retry=\(job.retryCount)")
                return .retry
            }

            guard !Task.isCancelled else { return .completed }

            let thumbnail = makeThumbnail(from: image)
            guard let thumbnail else {
                logger.warning("Failed to downsample preview image for \(job.source.id)")
                return .completed
            }

            cache.setObject(thumbnail, forKey: job.cacheKey as NSString)
            logger.debug("Cached generated preview for \(job.source.id)")
            NotificationCenter.default.post(
                name: .filePreviewDidUpdate,
                object: job.source.id
            )
            return .completed
        } catch {
            guard !Task.isCancelled else { return .completed }
            logger.debug("Failed to generate preview for \(job.source.id): \(error)")
            return .completed
        }
    }

    private func exportViewportPreview(
        for excalidrawFile: ExcalidrawFile,
        colorScheme: ColorScheme,
        coordinator: ExcalidrawCanvasView.Coordinator
    ) async throws -> PlatformImage {
        var exportFile = excalidrawFile
        if exportFile.content != nil {
            try exportFile.updateContentFilesFromFiles()
        }
        let sceneData = try exportFile.content ?? JSONEncoder().encode(exportFile)
        return try await coordinator.exportViewportToPNG(
            sceneData: sceneData,
            colorScheme: colorScheme
        )
    }

    private func waitForPreviewExporter() async -> ExcalidrawCanvasView.Coordinator? {
        for _ in 0..<20 {
            guard !Task.isCancelled else { return nil }

            if let coordinator = fileState?.excalidrawWebCoordinator,
               !coordinator.isLoading {
                return coordinator
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        return nil
    }

    private func loadLocalFileForPreview(at url: URL) async throws -> ExcalidrawFile {
        try await LocalFolder.withSecurityScopedAccessToContainingFolder(for: url) {
            try await FileCoordinator.shared.downloadFile(url: url)
            return try ExcalidrawFile(contentsOf: url)
        }
    }

    private func hydrateMediaForPreview(
        _ excalidrawFile: ExcalidrawFile,
        fileObjectID: NSManagedObjectID?
    ) async -> ExcalidrawFile {
        guard let fileObjectID,
              excalidrawFile.files.isEmpty,
              excalidrawFile.elements.contains(where: \.isImageElement) else {
            return excalidrawFile
        }

        do {
            let resources = try await PersistenceController.shared
                .mediaItemRepository
                .getResourceFiles(forFile: fileObjectID)
            guard !resources.isEmpty else { return excalidrawFile }

            var hydratedFile = excalidrawFile
            let resourceFiles = Dictionary(
                resources.map { ($0.id, $0) },
                uniquingKeysWith: { existing, _ in existing }
            )
            hydratedFile.files = resourceFiles.merging(hydratedFile.files) { _, fileResource in
                fileResource
            }
            return hydratedFile
        } catch {
            logger.warning("Failed to hydrate media for preview \(excalidrawFile.id): \(error)")
            return excalidrawFile
        }
    }

    private func makeThumbnail(from image: PlatformImage) -> PlatformImage? {
        guard let cgThumb = image.downsampledCGImage(maxPixelSize: 720) else {
            return nil
        }
#if canImport(UIKit)
        return UIImage(cgImage: cgThumb)
#elseif canImport(AppKit)
        return NSImage(
            cgImage: cgThumb,
            size: CGSize(
                width: CGFloat(cgThumb.width),
                height: CGFloat(cgThumb.height)
            )
        )
#endif
    }
}

private extension ExcalidrawElement {
    var isImageElement: Bool {
        if case .image = self {
            return true
        }
        return false
    }
}
