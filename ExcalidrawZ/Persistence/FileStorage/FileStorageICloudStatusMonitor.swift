//
//  FileStorageICloudStatusMonitor.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/29.
//

import Foundation
import Logging

/// Watches the iCloud Drive state for one active FileStorage item.
///
/// This is intentionally scoped to a single active file. FileStorage keeps a
/// local Application Support copy for fast reads, while iCloud Drive owns the
/// remote copy and may evict or delay Mobile Documents files. This monitor
/// publishes metadata/status changes only; the editor still decides if and when
/// it is safe to pull and apply content.
final class FileStorageICloudStatusMonitor: NSObject {
    private let logger = Logger(label: "FileStorageICloudStatusMonitor")

    private var setupTask: Task<Void, Never>?
    private var monitoredFileID: String?
    private var monitoredRelativePath: String?
    private var monitoredURL: URL?
    private var onStatusChange: ((String, ICloudFileStatus) -> Void)?

    private var query: NSMetadataQuery?

    deinit {
        if let query {
            NotificationCenter.default.removeObserver(self)
            query.stop()
        }
    }

    @MainActor
    func start(
        fileID: String,
        relativePath: String,
        onStatusChange: @escaping (String, ICloudFileStatus) -> Void
    ) {
        if monitoredFileID == fileID, monitoredRelativePath == relativePath {
            self.onStatusChange = onStatusChange
            if let monitoredURL {
                Task { @MainActor [weak self] in
                    await self?.publishCurrentStatus(for: monitoredURL)
                }
                return
            }
        }

        stop()

        monitoredFileID = fileID
        monitoredRelativePath = relativePath
        self.onStatusChange = onStatusChange

        setupTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                guard let fileURL = try await FileStorageManager.shared.iCloudFileURL(
                    relativePath: relativePath
                ) else {
                    logger.debug("No iCloud URL available for active FileStorage item: \(relativePath)")
                    return
                }

                guard !Task.isCancelled else { return }

                configureMetadataQuery(fileURL: fileURL)
                await publishCurrentStatus(for: fileURL)
            } catch {
                logger.warning("Failed to start FileStorage iCloud monitor for \(relativePath): \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    func stop() {
        setupTask?.cancel()
        setupTask = nil
        monitoredFileID = nil
        monitoredRelativePath = nil
        monitoredURL = nil
        onStatusChange = nil

        stopMetadataQuery()
    }

    @MainActor
    private func configureMetadataQuery(fileURL: URL) {
        stopMetadataQuery()

        monitoredURL = fileURL.standardizedFileURL

        let query = NSMetadataQuery()
        query.searchScopes = metadataQueryScopes(for: fileURL)
        query.predicate = NSPredicate(
            format: "%K == %@",
            NSMetadataItemFSNameKey,
            fileURL.lastPathComponent
        )
        query.notificationBatchingInterval = 0.5

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidFinishGathering(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )

        self.query = query
        query.start()
    }

    private func metadataQueryScopes(for fileURL: URL) -> [Any] {
#if os(iOS)
        // FileStorage lives under the app's ubiquity Data container. iOS
        // metadata queries should use the ubiquitous data scope instead of a
        // local URL scope, which can miss Mobile Documents state changes.
        return [NSMetadataQueryUbiquitousDataScope]
#else
        return [fileURL.deletingLastPathComponent()]
#endif
    }

    @MainActor
    private func stopMetadataQuery() {
        guard let query else { return }

        NotificationCenter.default.removeObserver(
            self,
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        NotificationCenter.default.removeObserver(
            self,
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        query.stop()
        self.query = nil
    }

    @MainActor
    @objc private func metadataQueryDidFinishGathering(_ notification: Notification) {
        handleMetadataQueryNotification(notification)
    }

    @MainActor
    @objc private func metadataQueryDidUpdate(_ notification: Notification) {
        handleMetadataQueryNotification(notification)
    }

    @MainActor
    private func handleMetadataQueryNotification(_ notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery,
              query === self.query,
              let monitoredURL else {
            return
        }

        query.disableUpdates()
        defer { query.enableUpdates() }

        let monitoredPath = monitoredURL.standardizedFileURL.filePath
        let matchingURL = query.results.compactMap { item -> URL? in
            guard let metadataItem = item as? NSMetadataItem else { return nil }

            if let url = metadataItem.value(forAttribute: NSMetadataItemURLKey) as? URL {
                return url
            }
            if let path = metadataItem.value(forAttribute: NSMetadataItemPathKey) as? String {
                return URL(fileURLWithPath: path)
            }
            return nil
        }
        .first { url in
            url.standardizedFileURL.filePath == monitoredPath
        }

        guard let matchingURL else { return }

        Task { @MainActor [weak self] in
            await self?.publishCurrentStatus(for: matchingURL)
        }
    }

    @MainActor
    private func publishCurrentStatus(for fileURL: URL) async {
        guard let fileID = monitoredFileID else { return }

        do {
            let status = try await ICloudStatusChecker.shared.checkStatus(for: fileURL)
            publish(status, fileID: fileID)
        } catch {
            logger.warning("Failed to resolve iCloud status for \(fileURL.lastPathComponent): \(error.localizedDescription)")
            publish(.error(error.localizedDescription), fileID: fileID)
        }
    }

    @MainActor
    private func publish(_ status: ICloudFileStatus, fileID: String) {
        onStatusChange?(fileID, status)
    }
}
