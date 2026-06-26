//
//  ExcalidrawDocumentAppStateSnapshotSaver.swift
//  ExcalidrawZ
//
//  Persists appState-only canvas changes without pulling a full content snapshot.
//

import Foundation
import UniformTypeIdentifiers

final class ExcalidrawDocumentAppStateSnapshotSaver: @unchecked Sendable {
    private let lock = NSLock()
    private weak var delegate: ExcalidrawDocumentSnapshotCoordinatorDelegate?

    private var commitTask: Task<Void, Never>?
    private var latestAppState: ExcalidrawCore.JSONValue?
    private var latestAppStateFileID: String?

    private let trailingDebounceNanoseconds: UInt64 = 2_000_000_000

    func attach(delegate: ExcalidrawDocumentSnapshotCoordinatorDelegate) {
        self.delegate = delegate
    }

    func reset() {
        clear()
    }

    func recordLatestAppState(_ metadata: ExcalidrawCore.StateChangedMetadata) {
        guard metadata.appStateDirty == true,
              let appState = metadata.appState else {
            return
        }

        lock.lock()
        latestAppState = appState
        lock.unlock()
    }

    func clear(cancelTask: Bool = true) {
        lock.lock()
        clearLocked(cancelTask: cancelTask)
        lock.unlock()
    }

    func schedule(
        _ metadata: ExcalidrawCore.StateChangedMetadata,
        currentFileID: String?,
        savingType: UTType?
    ) {
        guard metadata.appStateDirty == true,
              metadata.appState != nil,
              savingType == nil || savingType == .excalidrawFile else {
            return
        }

        lock.lock()
        latestAppStateFileID = metadata.currentFileId ?? currentFileID
        commitTask?.cancel()
        commitTask = makeCommitTask(delay: trailingDebounceNanoseconds)
        lock.unlock()
    }

    func flush(reason: String) async {
        cancelScheduledCommit()
        await commit(reason: reason)
    }

    func flushToCapturedTarget(
        reason: String,
        expectedFileID: String,
        target: FileState.CapturedCanvasSaveTarget,
        capturedContent: Data?
    ) async {
        cancelScheduledCommit()
        guard let core = delegate?.snapshotCoordinatorCore else { return }
        let commitState = takePendingCommitState()
        guard commitState.expectedFileID == expectedFileID,
              let appState = commitState.appState,
              let capturedContent else {
            return
        }

        do {
            let contentWithAppState = try Self.mergingAppState(appState, into: capturedContent)
            await FileState.saveCapturedAppStateOnlyUpdate(
                target,
                content: contentWithAppState
            )
            core.logger.debug("Committed background appState-only canvas update: \(reason) id=\(expectedFileID)")
        } catch {
            core.logger.error("Failed to apply background appState-only canvas update: \(error)")
            core.publishError(error)
        }
    }

    func flushCurrentAppState(reason: String) async -> Bool {
        cancelScheduledCommit()
        guard let core = delegate?.snapshotCoordinatorCore else { return false }

        do {
            let state = await MainActor.run {
                (
                    currentFileID: core.parent?.file?.id,
                    content: core.parent?.file?.content,
                    type: core.parent?.type,
                    savingType: core.parent?.savingType
                )
            }
            guard state.savingType == nil || state.savingType == .excalidrawFile else {
                return false
            }
            guard state.type != .collaboration,
                  let expectedFileID = state.currentFileID,
                  let content = state.content else {
                return false
            }

            let loadedID = await core.webActor.loadedFileID
            guard loadedID == expectedFileID else {
                core.logger.debug(
                    "Skipped forced appState-only canvas update \(reason): loaded file mismatch expected=\(expectedFileID) loaded=\(loadedID ?? "nil")"
                )
                return false
            }

            let appState = try await core.getCurrentAppState()
            let contentWithAppState = try Self.mergingAppState(appState, into: content)
            await MainActor.run {
                core.parent?.fileState.updateAppStateOnlyForCurrentFile(
                    expectedFileID: expectedFileID,
                    content: contentWithAppState
                )
            }
            clear()
            core.logger.debug("Committed forced appState-only canvas update: \(reason) id=\(expectedFileID)")
            return true
        } catch is CancellationError {
            return false
        } catch {
            core.logger.error("Failed to apply forced appState-only canvas update: \(error)")
            core.publishError(error)
            return false
        }
    }

    func flushCurrentAppStateToCapturedTarget(
        reason: String,
        expectedFileID: String,
        target: FileState.CapturedCanvasSaveTarget,
        capturedContent: Data?
    ) async -> Bool {
        cancelScheduledCommit()
        guard let core = delegate?.snapshotCoordinatorCore,
              let capturedContent else {
            return false
        }
        if case .collaborationFile = target.kind {
            return false
        }

        do {
            let loadedID = await core.webActor.loadedFileID
            guard loadedID == expectedFileID else {
                core.logger.debug(
                    "Skipped forced background appState-only canvas update \(reason): loaded file mismatch expected=\(expectedFileID) loaded=\(loadedID ?? "nil")"
                )
                return false
            }

            let appState = try await core.getCurrentAppState()
            let contentWithAppState = try Self.mergingAppState(appState, into: capturedContent)
            await FileState.saveCapturedAppStateOnlyUpdate(
                target,
                content: contentWithAppState
            )
            clear()
            core.logger.debug("Committed forced background appState-only canvas update: \(reason) id=\(expectedFileID)")
            return true
        } catch is CancellationError {
            return false
        } catch {
            core.logger.error("Failed to apply forced background appState-only canvas update: \(error)")
            core.publishError(error)
            return false
        }
    }

    private func makeCommitTask(delay: UInt64) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
                try Task.checkCancellation()
                await self?.commit(reason: "appStateOnlyDebounced")
            } catch {
                return
            }
        }
    }

    private func commit(reason: String) async {
        guard let core = delegate?.snapshotCoordinatorCore else { return }
        let commitState = takePendingCommitState()
        guard let expectedFileID = commitState.expectedFileID,
              let appState = commitState.appState else {
            return
        }

        do {
            let state = await MainActor.run {
                (
                    currentFileID: core.parent?.file?.id,
                    content: core.parent?.file?.content,
                    type: core.parent?.type,
                    savingType: core.parent?.savingType
                )
            }
            guard state.savingType == nil || state.savingType == .excalidrawFile else {
                return
            }
            guard state.type != .collaboration,
                  state.currentFileID == expectedFileID,
                  let content = state.content else {
                return
            }

            let contentWithAppState = try Self.mergingAppState(appState, into: content)
            await MainActor.run {
                core.parent?.fileState.updateAppStateOnlyForCurrentFile(
                    expectedFileID: expectedFileID,
                    content: contentWithAppState
                )
            }
        } catch {
            core.logger.error("Failed to apply appState-only canvas update: \(error)")
            core.publishError(error)
        }
    }

    private func cancelScheduledCommit() {
        lock.lock()
        commitTask?.cancel()
        commitTask = nil
        lock.unlock()
    }

    private func takePendingCommitState() -> (
        expectedFileID: String?,
        appState: ExcalidrawCore.JSONValue?
    ) {
        lock.lock()
        let fileID = latestAppStateFileID
        let appState = latestAppState
        clearLocked(cancelTask: false)
        lock.unlock()
        return (fileID, appState)
    }

    private func clearLocked(cancelTask: Bool = true) {
        if cancelTask {
            commitTask?.cancel()
        }
        commitTask = nil
        latestAppState = nil
        latestAppStateFileID = nil
    }

    static func mergingAppState(
        _ appState: ExcalidrawCore.JSONValue,
        into content: Data
    ) throws -> Data {
        let appStateData = try JSONEncoder().encode(appState)
        let appStateObject = try JSONSerialization.jsonObject(with: appStateData)
        guard var contentObject = try JSONSerialization.jsonObject(with: content) as? [String: Any] else {
            return content
        }
        contentObject["appState"] = appStateObject
        return try JSONSerialization.data(withJSONObject: contentObject)
    }

}
