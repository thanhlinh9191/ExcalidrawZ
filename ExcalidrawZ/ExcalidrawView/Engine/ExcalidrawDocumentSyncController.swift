//
//  ExcalidrawDocumentSyncController.swift
//  ExcalidrawZ
//
//  Coordinates host-driven file loads with WebView stateChanged events.
//

import Foundation
import UniformTypeIdentifiers

/// Owns the synchronization boundary between the native `ExcalidrawCanvasView`
/// binding and the embedded Excalidraw WebView.
///
/// Excalidraw can emit `stateChanged` events while the host is loading or
/// force-reloading a file. Applying those events blindly can persist an empty
/// or stale scene over the real file. This controller tracks which file is
/// expected in the WebView, suppresses load-induced events, and only applies
/// saves when the native file id still matches the WebView's loaded file id.
///
/// Swift-driven canvas mutations, such as AI tools and Library insertion, do
/// not always rely on a user edit-mode `stateChanged` round trip. For those,
/// the controller schedules a short delayed snapshot commit and routes it
/// through the same persistence path as normal WebView updates.
final class ExcalidrawDocumentSyncController: @unchecked Sendable {
    enum LoadOutcome {
        case skipped
        case loaded(LoadFileResult?)
        case failed

        var didLoad: Bool {
            if case .loaded = self {
                return true
            }
            return false
        }
    }

    private enum StateChangeSuppressionReason {
        case preparingFileLoad
        case canvasFileLoad
        case coreFileLoad
    }

    private struct StateChangeSuppression {
        let fileID: String
        let reason: StateChangeSuppressionReason
        let startedAt: Date
    }

    private let lock = NSLock()
    private weak var core: ExcalidrawCore?
    /// Last file id that the WebView confirmed as loaded.
    private var loadedFileID: String?
    /// File id currently being loaded by a host-driven request.
    private var pendingFileLoadID: String?
    /// Temporary guards used to ignore `stateChanged` events produced by file
    /// loading itself rather than by user or tool edits.
    private var stateChangeSuppressions: [UUID: StateChangeSuppression] = [:]
    /// Debounced commit for Swift-driven canvas mutations. A later mutation
    /// replaces the pending commit so one tool batch produces one snapshot save.
    private var programmaticMutationCommitTask: Task<Void, Never>?

    var currentLoadedFileID: String? {
        lock.lock()
        let fileID = loadedFileID
        lock.unlock()
        return fileID
    }

    func attach(core: ExcalidrawCore) {
        self.core = core
    }

    /// Called before the SwiftUI binding points the WebView at a different
    /// file. This arms a short suppression window so pre-load WebView events do
    /// not write into the previous or next file.
    func setTargetFileID(_ fileID: String?) {
        lock.lock()
        pruneExpiredStateChangeSuppressions()
        stateChangeSuppressions = stateChangeSuppressions.filter { _, suppression in
            suppression.reason != .preparingFileLoad
        }

        if let fileID, loadedFileID != fileID {
            stateChangeSuppressions[UUID()] = .init(
                fileID: fileID,
                reason: .preparingFileLoad,
                startedAt: Date()
            )
        }
        lock.unlock()
    }

    /// Loads a complete file into the WebView and records the file id only
    /// after the JS side confirms it has applied the scene.
    @discardableResult
    func load(_ file: ExcalidrawFile?, force: Bool = false) async -> LoadOutcome {
        guard let file, let data = file.content else {
            core.map {
                logFileLoad($0.logger, "Document load skipped: missing file or content", level: .warning)
            }
            return .failed
        }

        return await load(
            fileID: file.id,
            data: data,
            force: force,
            validateCurrentParentFile: true
        )
    }

    @discardableResult
    func load(
        fileID: String,
        data: Data,
        force: Bool = false,
        validateCurrentParentFile: Bool = false
    ) async -> LoadOutcome {
        cancelProgrammaticMutationCommit()

        let canvasToken: UUID
        if force {
            canvasToken = beginForcedCanvasFileLoad(fileID: fileID)
        } else if let token = beginCanvasFileLoadIfNeeded(fileID: fileID) {
            canvasToken = token
        } else {
            return .skipped
        }

        defer {
            endStateChangeSuppression(canvasToken)
        }

        let maxAttempts = 2
        for attempt in 1...maxAttempts {
            guard !Task.isCancelled else {
                finishCanvasFileLoad(fileID: fileID)
                return .failed
            }

            if validateCurrentParentFile {
                let isStillCurrent = await MainActor.run {
                    core?.parent?.file?.id == fileID
                }
                guard isStillCurrent else {
                    finishCanvasFileLoad(fileID: fileID)
                    return .failed
                }
            }

            let result = await loadPreparedFile(fileID: fileID, data: data, force: force)

            if validateCurrentParentFile {
                let isStillCurrent = await MainActor.run {
                    core?.parent?.file?.id == fileID
                }
                guard isStillCurrent else {
                    finishCanvasFileLoad(fileID: fileID)
                    return .failed
                }
            }

            let loadedID = await core?.webActor.loadedFileID

            if loadedID == fileID {
                commitLoadedFile(fileID: fileID)
                return .loaded(result)
            }

            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }

        let loadedID = await core?.webActor.loadedFileID
        core?.logger.warning("Failed to load file \(fileID) into Excalidraw after retries. loadedID=\(loadedID ?? "nil")")
        finishCanvasFileLoad(fileID: fileID)
        return .failed
    }

    /// Applies a normal WebView `stateChanged` payload to the native file
    /// binding, unless the event overlaps with a host-driven file load.
    func save(_ data: ExcalidrawCore.StateChangedMessageData) async {
        guard let core else { return }

        if let rejectionReason = receivedStateChangedRejectionReason(isCoreLoading: core.isLoading) {
            core.logger.debug("Ignored stateChanged during file load: \(rejectionReason)")
            return
        }

        let type = core.parent?.type
        let currentFileID = await core.parent?.file?.id
        let onError = core.publishError

        do {
            let loadedID = await core.webActor.loadedFileID
            guard self.canApplyStateChanged(
                currentFileID: currentFileID,
                webLoadedFileID: loadedID,
                isCollaboration: type == .collaboration
            ) else {
                return
            }

            try await applyCanvasFileData(
                data.data,
                currentFileID: currentFileID,
                type: type,
                savingType: core.parent?.savingType,
                markProgrammaticCommit: false
            )
        } catch {
            onError(error)
        }
    }

    /// Marks a native Swift mutation as locally dirty and schedules a live
    /// canvas snapshot save. This is intentionally separate from `save(_:)`
    /// because these mutations may not produce a reliable autosave event while
    /// the editor is outside explicit edit mode on iOS.
    @MainActor
    func scheduleProgrammaticMutationCommit(reason: String) {
        guard let core,
              let fileID = core.parent?.file?.id else {
            return
        }

        core.parent?.fileState.noteProgrammaticCanvasMutation(fileID: fileID)
        programmaticMutationCommitTask?.cancel()
        programmaticMutationCommitTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
                try Task.checkCancellation()
                await self?.commitProgrammaticMutation(
                    reason: reason,
                    expectedFileID: fileID
                )
            } catch {
                return
            }
        }
    }

    /// Captures the current WebView scene after a Swift-driven mutation and
    /// persists it if the canvas is still showing the same file.
    private func commitProgrammaticMutation(
        reason: String,
        expectedFileID: String
    ) async {
        guard let core else { return }

        let onError = core.publishError
        let currentFileID = await MainActor.run { core.parent?.file?.id }
        guard currentFileID == expectedFileID else { return }

        let type = await MainActor.run { core.parent?.type }
        let savingType = await MainActor.run { core.parent?.savingType }

        do {
            let loadedID = await core.webActor.loadedFileID
            guard self.canApplyStateChanged(
                currentFileID: currentFileID,
                webLoadedFileID: loadedID,
                isCollaboration: type == .collaboration
            ) else {
                return
            }

            let snapshot = try await core.getCurrentFileSnapshot()
            let fileData = try Self.makeFileData(from: snapshot)
            try await applyCanvasFileData(
                fileData,
                currentFileID: currentFileID,
                type: type,
                savingType: savingType,
                markProgrammaticCommit: true
            )
            core.logger.debug("Committed programmatic canvas mutation: \(reason)")
        } catch is CancellationError {
            return
        } catch {
            core.logger.error("Failed to commit programmatic canvas mutation \(reason): \(error)")
            onError(error)
        }
    }

    /// Shared persistence bridge for both WebView autosave events and explicit
    /// snapshot commits. This keeps PNG/SVG export-backed documents and normal
    /// `.excalidraw` documents on the same validation path.
    private func applyCanvasFileData(
        _ fileData: ExcalidrawCore.ExcalidrawFileData,
        currentFileID: String?,
        type: ExcalidrawCanvasView.ExcalidrawType?,
        savingType: UTType?,
        markProgrammaticCommit: Bool
    ) async throws {
        guard let core else { return }
        let elements = fileData.elements

        switch savingType {
            case .some(.excalidrawPNG), .some(.png):
                let data = try await core.exportElementsToPNGData(
                    elements: elements ?? [],
                    embedScene: true,
                    colorScheme: .light
                )
                await MainActor.run {
                    guard type == .collaboration || core.parent?.file?.id == currentFileID else { return }
                    core.parent?.file?.content = data
                }
            case .some(.excalidrawSVG), .some(.svg):
                let data = try await core.exportElementsToSVGData(
                    elements: elements ?? [],
                    embedScene: true,
                    colorScheme: .light
                )
                await MainActor.run {
                    guard type == .collaboration || core.parent?.file?.id == currentFileID else { return }
                    core.parent?.file?.content = data
                }
            default:
                let onError = core.publishError
                await MainActor.run {
                    guard type == .collaboration || core.parent?.file?.id == currentFileID else { return }
                    if markProgrammaticCommit, let currentFileID {
                        core.parent?.fileState.noteProgrammaticCanvasMutation(fileID: currentFileID)
                    }
                    do {
                        try core.parent?.file?.update(data: fileData)
                    } catch {
                        onError(error)
                    }
                }
        }
    }

    /// Converts a live JS snapshot into the same payload shape used by the
    /// `stateChanged` message. The snapshot's `dataString` does not include
    /// resource files, so this method rebuilds a complete payload with
    /// `elements`, `appState`, and `files`.
    private static func makeFileData(
        from snapshot: ExcalidrawCore.CurrentFileSnapshot
    ) throws -> ExcalidrawCore.ExcalidrawFileData {
        let payload: [String: Any] = [
            "elements": snapshot.elements.map(Self.jsonObject),
            "appState": Self.jsonObject(snapshot.appState),
            "files": snapshot.files.mapValues(Self.jsonObject)
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let dataString = String(data: data, encoding: .utf8) else {
            throw ExcalidrawCore.JSONEncodingFailed()
        }

        let elementsData = try JSONEncoder().encode(snapshot.elements)
        let elements = try JSONDecoder().decode([ExcalidrawElement].self, from: elementsData)
        let filesData = try JSONEncoder().encode(snapshot.files)
        let files = try JSONDecoder().decode(
            [String: ExcalidrawFile.ResourceFile].self,
            from: filesData
        )

        return .init(dataString: dataString, elements: elements, files: files)
    }

    private static func jsonObject(_ value: ExcalidrawCore.JSONValue) -> Any {
        switch value {
            case .string(let value):
                return value
            case .number(let value):
                return value
            case .bool(let value):
                return value
            case .object(let value):
                return value.mapValues(Self.jsonObject)
            case .array(let value):
                return value.map(Self.jsonObject)
            case .null:
                return NSNull()
        }
    }

    private func loadPreparedFile(
        fileID: String,
        data: Data,
        force: Bool
    ) async -> LoadFileResult? {
        guard let core else { return nil }

        let suppressionToken = beginCoreFileLoad(fileID: fileID)
        defer {
            endStateChangeSuppression(suppressionToken)
        }

        guard await core.waitUntilReadyForFileLoad(fileID: fileID) else {
            logFileLoad(core.logger, "File load skipped: core not ready id=\(fileID)", level: .warning)
            return nil
        }

        do {
            let result = try await core.webActor.loadFile(id: fileID, data: data, force: force)
            let loadedID = await core.webActor.loadedFileID
            if loadedID == fileID {
                commitLoadedFile(fileID: fileID)
            }
            return result
        } catch {
            core.publishError(error)
            return nil
        }
    }

    private func beginCanvasFileLoadIfNeeded(fileID: String) -> UUID? {
        lock.lock()
        pruneExpiredStateChangeSuppressions()
        clearStateChangeSuppressions(reason: .preparingFileLoad, fileID: fileID)

        guard loadedFileID != fileID, pendingFileLoadID != fileID else {
            lock.unlock()
            return nil
        }

        pendingFileLoadID = fileID
        let token = UUID()
        stateChangeSuppressions[token] = .init(
            fileID: fileID,
            reason: .canvasFileLoad,
            startedAt: Date()
        )
        lock.unlock()
        return token
    }

    private func beginForcedCanvasFileLoad(fileID: String) -> UUID {
        lock.lock()
        pruneExpiredStateChangeSuppressions()
        clearStateChangeSuppressions(reason: .preparingFileLoad, fileID: fileID)
        pendingFileLoadID = fileID
        let token = UUID()
        stateChangeSuppressions[token] = .init(
            fileID: fileID,
            reason: .canvasFileLoad,
            startedAt: Date()
        )
        lock.unlock()
        return token
    }

    private func beginCoreFileLoad(fileID: String) -> UUID {
        beginStateChangeSuppression(fileID: fileID, reason: .coreFileLoad)
    }

    private func endStateChangeSuppression(_ token: UUID) {
        lock.lock()
        stateChangeSuppressions.removeValue(forKey: token)
        lock.unlock()
    }

    private func commitLoadedFile(fileID: String) {
        lock.lock()
        loadedFileID = fileID
        if pendingFileLoadID == fileID {
            pendingFileLoadID = nil
        }
        lock.unlock()
    }

    private func finishCanvasFileLoad(fileID: String) {
        lock.lock()
        if pendingFileLoadID == fileID {
            pendingFileLoadID = nil
        }
        lock.unlock()
    }

    func resetFileLoadState() {
        cancelProgrammaticMutationCommit()
        lock.lock()
        loadedFileID = nil
        pendingFileLoadID = nil
        stateChangeSuppressions.removeAll()
        lock.unlock()
    }

    private func cancelProgrammaticMutationCommit() {
        programmaticMutationCommitTask?.cancel()
        programmaticMutationCommitTask = nil
    }

    private func receivedStateChangedRejectionReason(isCoreLoading: Bool) -> String? {
        lock.lock()
        pruneExpiredStateChangeSuppressions()
        let suppressedFileID = latestStateChangeSuppression()?.fileID
        lock.unlock()

        if let suppressedFileID {
            return "suppressed during file load id=\(suppressedFileID)"
        }

        if isCoreLoading {
            return "core loading"
        }

        return nil
    }

    private func canApplyStateChanged(
        currentFileID: String?,
        webLoadedFileID: String?,
        isCollaboration: Bool
    ) -> Bool {
        if isCollaboration {
            return true
        }

        guard let currentFileID else {
            return false
        }

        return webLoadedFileID == currentFileID
    }

    private func beginStateChangeSuppression(
        fileID: String,
        reason: StateChangeSuppressionReason
    ) -> UUID {
        let token = UUID()
        lock.lock()
        pruneExpiredStateChangeSuppressions()
        stateChangeSuppressions[token] = .init(
            fileID: fileID,
            reason: reason,
            startedAt: Date()
        )
        lock.unlock()
        return token
    }

    private func pruneExpiredStateChangeSuppressions() {
        let now = Date()
        stateChangeSuppressions = stateChangeSuppressions.filter { _, suppression in
            now.timeIntervalSince(suppression.startedAt) <= 8
        }
    }

    private func clearStateChangeSuppressions(
        reason: StateChangeSuppressionReason,
        fileID: String
    ) {
        stateChangeSuppressions = stateChangeSuppressions.filter { _, suppression in
            !(suppression.reason == reason && suppression.fileID == fileID)
        }
    }

    private func latestStateChangeSuppression() -> StateChangeSuppression? {
        stateChangeSuppressions.values.max { lhs, rhs in
            lhs.startedAt < rhs.startedAt
        }
    }
}
