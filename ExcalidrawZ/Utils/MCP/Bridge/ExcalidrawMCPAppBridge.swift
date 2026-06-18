//
//  ExcalidrawMCPAppBridge.swift
//  ExcalidrawZ
//
//  Created by Codex on 6/15/26.
//

import CoreData
import Foundation
import SwiftUI

@MainActor
final class ExcalidrawMCPAppBridge {
    struct ApplyResult: Sendable {
        let targetFileID: String
        let preCheckpointID: UUID?
        let postCheckpointID: UUID?
        let checkpointWarning: String?
    }

    struct MutationCheckpointResult<Result>: Sendable where Result: Sendable {
        let result: Result
        let preCheckpointID: UUID?
        let postCheckpointID: UUID?
        let checkpointWarning: String?
    }

    private struct ApplyRequestKey: Hashable {
        let targetFileID: String
        let clientUpdateID: String
    }

    enum BridgeError: LocalizedError {
        case appContextUnavailable
        case targetGroupUnavailable
        case createdFileUnavailable
        case aiGenerationInProgress
        case canvasUnavailable
        case fileLoadTimedOut
        case unsupportedActiveFile(String)
        case currentFileAccessDenied
        case fileNotFound(String)
        case invalidGeneratedFile(String)

        var errorDescription: String? {
            switch self {
                case .appContextUnavailable:
                    "ExcalidrawZ is not ready. Open the app window before using MCP drawing tools."
                case .targetGroupUnavailable:
                    "No library group is available for the MCP drawing."
                case .createdFileUnavailable:
                    "The new MCP drawing file could not be loaded from persistence."
                case .aiGenerationInProgress:
                    "ExcalidrawZ is generating another AI response. Stop it before using MCP drawing tools."
                case .canvasUnavailable:
                    "The Excalidraw canvas is not ready. Open a drawing window before using MCP drawing tools."
                case .fileLoadTimedOut:
                    "The MCP target file did not finish loading in ExcalidrawZ."
                case .unsupportedActiveFile(let reason):
                    "The current file cannot be modified by MCP: \(reason)"
                case .currentFileAccessDenied:
                    AIFileAccessStatusMessage.protectedContentAccessDenied
                case .fileNotFound(let id):
                    "File not found: \(id)"
                case .invalidGeneratedFile(let message):
                    "The generated Excalidraw file is invalid: \(message)"
            }
        }
    }

    static let shared = ExcalidrawMCPAppBridge()

    private weak var fileState: FileState?
    private weak var context: NSManagedObjectContext?
    private var recentApplyResults: [ApplyRequestKey: ApplyResult] = [:]
    private var recentApplyResultKeys: [ApplyRequestKey] = []
    private static let maxRecentApplyResultCount = 32

    private init() {}

    func register(
        fileState: FileState,
        context: NSManagedObjectContext
    ) {
        self.fileState = fileState
        self.context = context
    }

    @discardableResult
    func createElements(
        _ elements: [MCPJSONValue]
    ) async throws -> [MCPJSONValue] {
        guard let coordinator = fileState?.excalidrawWebCoordinator else {
            throw BridgeError.canvasUnavailable
        }
        let inputData = try MCPJSONValue.array(elements).mcpJSONData()
        let inputElements = try JSONDecoder().decode(ExcalidrawCore.JSONValue.self, from: inputData)
        let convertedElements = try await coordinator.createElements(
            inputElements,
            options: .init(regenerateIds: false)
        )
        let convertedData = try JSONEncoder().encode(convertedElements)
        let convertedValue = try MCPJSONValue.parse(from: convertedData)
        guard let convertedArray = convertedValue.arrayValue else {
            throw BridgeError.invalidGeneratedFile("Converted elements is not a JSON array.")
        }
        return convertedArray
    }

    @discardableResult
    func apply(
        _ session: ExcalidrawMCPDiagramSession,
        clientUpdateID: String? = nil
    ) async throws -> ApplyResult {
        guard let fileState else {
            throw BridgeError.appContextUnavailable
        }
        guard fileState.aiChatSession == nil else {
            throw BridgeError.aiGenerationInProgress
        }
        syncCoordinatorRegistry(fileState: fileState)

        let targetFile = try await requireActiveFileForMCPUpdate(fileState: fileState)
        let applyRequestKey = applyRequestKey(
            targetFileID: targetFile.id,
            clientUpdateID: clientUpdateID
        )
        if let applyRequestKey,
           let cachedResult = recentApplyResults[applyRequestKey] {
            return cachedResult
        }

        let preCheckpointID = try await recordMCPCheckpoint(
            file: targetFile,
            fileState: fileState,
            source: .mcpPre,
            description: mcpCheckpointDescription(
                phase: "Before MCP update",
                clientUpdateID: clientUpdateID
            )
        )

        let sessionElementsJSON: String
        do {
            sessionElementsJSON = try elementsJSON(for: session)
        } catch {
            if let preCheckpointID {
                try? await deleteMCPCheckpoint(id: preCheckpointID, file: targetFile)
            }
            throw error
        }
        fileState.mcpCheckpointSuppressionDepth += 1
        defer {
            fileState.mcpCheckpointSuppressionDepth = max(
                0,
                fileState.mcpCheckpointSuppressionDepth - 1
            )
        }
        do {
            try await replaceCanvasElements(
                sessionElementsJSON,
                fileID: targetFile.id,
                fileState: fileState
            )
            try await applyViewportUpdate(
                session.viewportUpdate,
                fileID: targetFile.id,
                fileState: fileState
            )
        } catch {
            if let preCheckpointID {
                try? await deleteMCPCheckpoint(id: preCheckpointID, file: targetFile)
            }
            throw error
        }

        var checkpointWarning: String?
        let postCheckpointID: UUID?
        do {
            postCheckpointID = try await recordMCPCheckpoint(
                file: targetFile,
                fileState: fileState,
                source: .mcpPost,
                description: mcpCheckpointDescription(
                    phase: "MCP update",
                    clientUpdateID: clientUpdateID
                )
            )
        } catch {
            postCheckpointID = nil
            checkpointWarning = "MCP update succeeded, but post-update checkpoint failed: \(error.localizedDescription)"
        }

        let result = ApplyResult(
            targetFileID: targetFile.id,
            preCheckpointID: preCheckpointID,
            postCheckpointID: postCheckpointID,
            checkpointWarning: checkpointWarning
        )
        if let applyRequestKey {
            cacheApplyResult(result, for: applyRequestKey)
        }
        return result
    }

    func optimizedAppContext() async -> MCPJSONValue {
        guard let fileState else {
            return .object([
                "serviceMode": .string(ExcalidrawMCPServiceMode.optimized.rawValue),
                "app": appInfo(),
                "ready": .bool(false),
                "message": .string("ExcalidrawZ is not ready. Open the app window before using Optimized MCP.")
            ])
        }
        syncCoordinatorRegistry(fileState: fileState)

        let activeFile = fileState.currentActiveFile
        let allowsFileAccess = AIChatPreferences.shared.allowsFileAccess(for: activeFile)
        let lockedContentAllowsRead = await LockedContentAIGuard.canAIRead(activeFile: activeFile)
        let canReadCurrentFile = activeFile != nil && allowsFileAccess && lockedContentAllowsRead
        let canUpdateView = canUpdateView(
            activeFile: activeFile,
            canReadCurrentFile: canReadCurrentFile
        )
        let canvasTarget = canvasTarget(for: activeFile)
        let coordinator = ExcalidrawCoordinatorRegistry.shared.coordinator(for: canvasTarget)
        let canvasPreferences = await currentCanvasPreferencesValue(
            for: coordinator,
            canReadCurrentFile: canReadCurrentFile
        )
        let loadedFileID = coordinator?.documentSyncController.currentLoadedFileID
        let loadedFileMatchesCurrentFile = activeFile.map { $0.id == loadedFileID } ?? false

        return .object([
            "serviceMode": .string(ExcalidrawMCPServiceMode.optimized.rawValue),
            "app": appInfo(),
            "ready": .bool(true),
            "currentFile": currentFileInfo(
                activeFile,
                allowsFileAccess: allowsFileAccess,
                lockedContentAllowsRead: lockedContentAllowsRead,
                canReadCurrentFile: canReadCurrentFile,
                canUpdateView: canUpdateView
            ),
            "canvas": .object([
                "target": .string(canvasTarget.rawValue),
                "isReady": .bool(coordinator != nil && coordinator?.isLoading != true),
                "loadedFileId": optionalString(loadedFileMatchesCurrentFile ? loadedFileID : nil),
                "loadedFileMatchesCurrentFile": .bool(loadedFileMatchesCurrentFile),
                "preferences": canvasPreferences
            ])
        ])
    }

    func optimizedReadView(
        options: ExcalidrawMCPOptimizedToolHandler.CurrentCanvasOptions
    ) async throws -> MCPJSONValue {
        guard let fileState else {
            throw BridgeError.appContextUnavailable
        }
        syncCoordinatorRegistry(fileState: fileState)
        let activeFile = fileState.currentActiveFile
        try await ensureMCPCanAccessActiveFile(fileState.currentActiveFile)
        guard let data = try await CurrentExcalidrawDataResolver.resolve(
            fileState: fileState,
            canvasTarget: canvasTarget(for: activeFile)
        ) else {
            throw BridgeError.canvasUnavailable
        }

        let value = try MCPJSONValue.parse(from: data)
        guard case .object(var object) = value else {
            throw BridgeError.invalidGeneratedFile("Current canvas data is not a JSON object.")
        }

        if !options.includeElements {
            object.removeValue(forKey: "elements")
        }
        if !options.includeAppState {
            object.removeValue(forKey: "appState")
        }
        if !options.includeFiles {
            object.removeValue(forKey: "files")
        }
        let allowsFileAccess = AIChatPreferences.shared.allowsFileAccess(for: activeFile)
        let lockedContentAllowsRead = await LockedContentAIGuard.canAIRead(activeFile: activeFile)
        let canReadCurrentFile = activeFile != nil && allowsFileAccess && lockedContentAllowsRead
        object["metadata"] = .object([
            "source": .string("ExcalidrawZ Optimized MCP"),
            "currentFile": currentFileInfo(
                activeFile,
                allowsFileAccess: allowsFileAccess,
                lockedContentAllowsRead: lockedContentAllowsRead,
                canReadCurrentFile: canReadCurrentFile,
                canUpdateView: canUpdateView(
                    activeFile: activeFile,
                    canReadCurrentFile: canReadCurrentFile
                )
            )
        ])
        return .object(object)
    }

    func optimizedSetCanvasPreferences(_ update: CanvasPreferencesSnapshot) async throws -> MCPJSONValue {
        guard let fileState else {
            throw BridgeError.appContextUnavailable
        }
        syncCoordinatorRegistry(fileState: fileState)
        let targetFile = try await requireActiveFileForMCPUpdate(fileState: fileState)
        guard let coordinator = fileState.excalidrawWebCoordinator else {
            throw BridgeError.canvasUnavailable
        }
        try await waitForLoadedFile(targetFile.id, coordinator: coordinator)

        if update.isEmpty {
            return try canvasPreferencesResult(
                snapshot: await safeFetchCanvasPreferences(from: coordinator),
                checkpointStatus: "unchanged",
                warning: nil
            )
        }

        let preCheckpointID = try await recordMCPCheckpoint(
            file: targetFile,
            fileState: fileState,
            source: .mcpPre,
            description: "Before MCP canvas preference update"
        )

        fileState.mcpCheckpointSuppressionDepth += 1
        defer {
            fileState.mcpCheckpointSuppressionDepth = max(
                0,
                fileState.mcpCheckpointSuppressionDepth - 1
            )
        }
        do {
            try await coordinator.setCanvasPreferences(update)
        } catch {
            if let preCheckpointID {
                try? await deleteMCPCheckpoint(id: preCheckpointID, file: targetFile)
            }
            throw error
        }

        var warning: String?
        let postCheckpointID: UUID?
        do {
            postCheckpointID = try await recordMCPCheckpoint(
                file: targetFile,
                fileState: fileState,
                source: .mcpPost,
                description: "MCP canvas preference update"
            )
        } catch {
            postCheckpointID = nil
            warning = "Canvas preferences updated, but post-update checkpoint failed: \(error.localizedDescription)"
        }

        return try canvasPreferencesResult(
            snapshot: await safeFetchCanvasPreferences(from: coordinator),
            checkpointStatus: preCheckpointID != nil || postCheckpointID != nil ? "recorded" : "unavailable",
            warning: warning
        )
    }

    func optimizedMutationWithCheckpoints<Result: Sendable>(
        description: String,
        operation: () async throws -> Result
    ) async throws -> MutationCheckpointResult<Result> {
        guard let fileState else {
            throw BridgeError.appContextUnavailable
        }
        guard fileState.aiChatSession == nil else {
            throw BridgeError.aiGenerationInProgress
        }
        syncCoordinatorRegistry(fileState: fileState)
        let targetFile = try await requireActiveFileForMCPUpdate(fileState: fileState)
        let preCheckpointID = try await recordMCPCheckpoint(
            file: targetFile,
            fileState: fileState,
            source: .mcpPre,
            description: "Before \(description)"
        )

        fileState.mcpCheckpointSuppressionDepth += 1
        defer {
            fileState.mcpCheckpointSuppressionDepth = max(
                0,
                fileState.mcpCheckpointSuppressionDepth - 1
            )
        }
        let result: Result
        do {
            result = try await operation()
        } catch {
            if let preCheckpointID {
                try? await deleteMCPCheckpoint(id: preCheckpointID, file: targetFile)
            }
            throw error
        }

        var warning: String?
        let postCheckpointID: UUID?
        do {
            postCheckpointID = try await recordMCPCheckpoint(
                file: targetFile,
                fileState: fileState,
                source: .mcpPost,
                description: description
            )
        } catch {
            postCheckpointID = nil
            warning = "\(description) succeeded, but post-update checkpoint failed: \(error.localizedDescription)"
        }

        return MutationCheckpointResult(
            result: result,
            preCheckpointID: preCheckpointID,
            postCheckpointID: postCheckpointID,
            checkpointWarning: warning
        )
    }

    private func recordMCPCheckpoint(
        file: FileState.ActiveFile,
        fileState: FileState,
        source: FileCheckpointSource,
        description: String?
    ) async throws -> UUID? {
        switch file {
            case .file(let file):
                let content = try await currentSnapshotContent(
                    file: file,
                    fileState: fileState
                )
                return try await PersistenceController.shared.fileRepository.recordCheckpoint(
                    fileObjectID: file.objectID,
                    content: content,
                    source: source,
                    description: description
                )

            case .localFile(let url):
                let content = try await currentSnapshotContent(
                    localFileURL: url,
                    fileState: fileState
                )
                return try await recordLocalMCPCheckpoint(
                    url: url,
                    content: content,
                    source: source,
                    description: description
                )

            case .temporaryFile, .collaborationFile:
                return nil
        }
    }

    private func currentSnapshotContent(
        file: File,
        fileState: FileState
    ) async throws -> Data {
        if let liveContent = try await CurrentExcalidrawDataResolver.resolve(
            fileState: fileState,
            canvasTarget: canvasTarget(for: .file(file))
        ) {
            return liveContent
        }
        return try await file.loadContent()
    }

    private func currentSnapshotContent(
        localFileURL url: URL,
        fileState: FileState
    ) async throws -> Data {
        if let liveContent = try await CurrentExcalidrawDataResolver.resolve(
            fileState: fileState,
            canvasTarget: canvasTarget(for: .localFile(url))
        ) {
            return liveContent
        }
        return try await FileSyncCoordinator.shared.openFile(url)
    }

    private func recordLocalMCPCheckpoint(
        url: URL,
        content: Data,
        source: FileCheckpointSource,
        description: String?
    ) async throws -> UUID {
        let context = PersistenceController.shared.container.newBackgroundContext()
        return try await context.perform {
            let checkpoint = LocalFileCheckpoint(context: context)
            let checkpointID = UUID()
            checkpoint.id = checkpointID
            checkpoint.url = url
            checkpoint.content = content
            checkpoint.updatedAt = .now
            checkpoint.source = source.rawValue
            checkpoint.historyDescription = description
            context.insert(checkpoint)
            try context.save()
            return checkpointID
        }
    }

    private func deleteMCPCheckpoint(
        id: UUID,
        file: FileState.ActiveFile
    ) async throws {
        switch file {
            case .file(let file):
                guard let checkpointObjectID = try await fileCheckpointObjectID(
                    id: id,
                    fileObjectID: file.objectID
                ) else {
                    return
                }
                try await PersistenceController.shared.checkpointRepository.deleteCheckpoint(
                    checkpointObjectID: checkpointObjectID
                )

            case .localFile(let url):
                try await deleteLocalMCPCheckpoint(id: id, url: url)

            case .temporaryFile, .collaborationFile:
                break
        }
    }

    private func fileCheckpointObjectID(
        id: UUID,
        fileObjectID: NSManagedObjectID
    ) async throws -> NSManagedObjectID? {
        let context = PersistenceController.shared.newTaskContext()
        return try await context.perform {
            guard let file = context.object(with: fileObjectID) as? File else {
                return nil
            }
            let request = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
            request.predicate = NSPredicate(
                format: "file == %@ AND id == %@",
                file,
                id as CVarArg
            )
            request.fetchLimit = 1
            return try context.fetch(request).first?.objectID
        }
    }

    private func deleteLocalMCPCheckpoint(
        id: UUID,
        url: URL
    ) async throws {
        let context = PersistenceController.shared.container.newBackgroundContext()
        try await context.perform {
            let request: NSFetchRequest<LocalFileCheckpoint> = LocalFileCheckpoint.fetchRequest()
            request.predicate = NSPredicate(
                format: "url == %@ AND id == %@",
                url as CVarArg,
                id as CVarArg
            )
            request.fetchLimit = 1
            if let checkpoint = try context.fetch(request).first {
                context.delete(checkpoint)
                try context.save()
            }
        }
    }

    private func mcpCheckpointDescription(
        phase: String,
        clientUpdateID: String?
    ) -> String {
        guard let clientUpdateID,
              !clientUpdateID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return phase
        }
        return "\(phase) (\(clientUpdateID))"
    }

    private func applyRequestKey(
        targetFileID: String,
        clientUpdateID: String?
    ) -> ApplyRequestKey? {
        guard let clientUpdateID else { return nil }
        let trimmedClientUpdateID = clientUpdateID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientUpdateID.isEmpty else { return nil }
        return ApplyRequestKey(
            targetFileID: targetFileID,
            clientUpdateID: trimmedClientUpdateID
        )
    }

    private func cacheApplyResult(
        _ result: ApplyResult,
        for key: ApplyRequestKey
    ) {
        recentApplyResults[key] = result
        recentApplyResultKeys.removeAll { $0 == key }
        recentApplyResultKeys.append(key)

        while recentApplyResultKeys.count > Self.maxRecentApplyResultCount {
            let removedKey = recentApplyResultKeys.removeFirst()
            recentApplyResults.removeValue(forKey: removedKey)
        }
    }

    func optimizedCreateFile(name rawName: String?) async throws -> MCPJSONValue {
        guard let fileState,
              let context
        else {
            throw BridgeError.appContextUnavailable
        }
        guard fileState.aiChatSession == nil else {
            throw BridgeError.aiGenerationInProgress
        }
        let targetGroupID = try targetGroupID(
            fileState: fileState,
            context: context
        )
        guard let content = ExcalidrawFile().content else {
            throw BridgeError.invalidGeneratedFile("Unable to create an empty Excalidraw file.")
        }
        let name = {
            let trimmed = rawName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? String(localizable: .mcpGeneratedFileName) : trimmed
        }()
        let fileObjectID = try await PersistenceController.shared.fileRepository.createFile(
            name: name,
            content: content,
            groupObjectID: targetGroupID
        )

        guard let file = context.object(with: fileObjectID) as? File else {
            throw BridgeError.createdFileUnavailable
        }
        if let group = file.group {
            fileState.currentActiveGroup = .group(group)
        }

        let activeFile = FileState.ActiveFile.file(file)
        fileState.setActiveFile(activeFile)
        return currentFileInfo(
            activeFile,
            allowsFileAccess: true,
            lockedContentAllowsRead: true,
            canReadCurrentFile: true,
            canUpdateView: true
        )
    }

    func optimizedOpenFile(fileID rawFileID: String) async throws -> MCPJSONValue {
        guard let fileState,
              let context
        else {
            throw BridgeError.appContextUnavailable
        }
        guard fileState.aiChatSession == nil else {
            throw BridgeError.aiGenerationInProgress
        }
        guard let fileID = UUID(uuidString: rawFileID) else {
            throw BridgeError.fileNotFound(rawFileID)
        }

        let fileObjectID = try await libraryFileObjectID(fileID: fileID, includeTrash: false)
        guard try await LockedContentAIGuard.canToolAccess(fileObjectID: fileObjectID) else {
            throw BridgeError.currentFileAccessDenied
        }
        guard let file = context.object(with: fileObjectID) as? File else {
            throw BridgeError.fileNotFound(rawFileID)
        }
        if let group = file.group {
            fileState.currentActiveGroup = .group(group)
        }

        let activeFile = FileState.ActiveFile.file(file)
        fileState.setActiveFile(activeFile)
        return currentFileInfo(
            activeFile,
            allowsFileAccess: true,
            lockedContentAllowsRead: true,
            canReadCurrentFile: true,
            canUpdateView: true
        )
    }

    private func requireActiveFileForMCPUpdate(
        fileState: FileState
    ) async throws -> FileState.ActiveFile {
        guard let activeFile = fileState.currentActiveFile else {
            throw BridgeError.unsupportedActiveFile(
                "no file is open. Call list_files and open_file, or call create_file, before update_view."
            )
        }
        try validateMCPWritableActiveFile(activeFile, fileState: fileState)
        try await ensureMCPCanAccessActiveFile(activeFile)
        return activeFile
    }

    private func validateMCPWritableActiveFile(
        _ activeFile: FileState.ActiveFile,
        fileState: FileState
    ) throws {
        guard !fileState.currentActiveFileIsInTrash else {
            throw BridgeError.unsupportedActiveFile("file is in Trash.")
        }

        switch activeFile {
            case .file, .localFile, .temporaryFile:
                return
            case .collaborationFile:
                throw BridgeError.unsupportedActiveFile("collaboration files are not supported yet.")
        }
    }

    private func targetGroupID(
        fileState: FileState,
        context: NSManagedObjectContext
    ) throws -> NSManagedObjectID {
        if case .group(let group) = fileState.currentActiveGroup,
           group.groupType != .trash {
            return group.objectID
        }

        guard let defaultGroup = try PersistenceController.shared.getDefaultGroup(context: context) else {
            throw BridgeError.targetGroupUnavailable
        }

        return defaultGroup.objectID
    }

    private func libraryFileObjectID(
        fileID: UUID,
        includeTrash: Bool
    ) async throws -> NSManagedObjectID {
        let context = PersistenceController.shared.newTaskContext()
        return try await context.perform {
            let fetchRequest = NSFetchRequest<File>(entityName: "File")
            if includeTrash {
                fetchRequest.predicate = NSPredicate(format: "id == %@", fileID as CVarArg)
            } else {
                fetchRequest.predicate = NSPredicate(
                    format: "id == %@ AND (inTrash == NO OR inTrash == nil)",
                    fileID as CVarArg
                )
            }
            fetchRequest.fetchLimit = 1
            guard let file = try context.fetch(fetchRequest).first else {
                throw BridgeError.fileNotFound(fileID.uuidString)
            }
            return file.objectID
        }
    }

    private func elementsJSON(for session: ExcalidrawMCPDiagramSession) throws -> String {
        let elementsData = try MCPJSONValue.array(session.elements).mcpJSONData()
        guard (try JSONSerialization.jsonObject(with: elementsData)) is [Any] else {
            throw BridgeError.invalidGeneratedFile("elements is not a JSON array.")
        }
        guard let jsonString = String(data: elementsData, encoding: .utf8) else {
            throw BridgeError.invalidGeneratedFile("elements JSON is not valid UTF-8.")
        }
        return jsonString
    }

    private func replaceCanvasElements(
        _ elementsJSON: String,
        fileID: String,
        fileState: FileState
    ) async throws {
        guard let coordinator = fileState.excalidrawWebCoordinator else {
            throw BridgeError.canvasUnavailable
        }

        try await waitForLoadedFile(fileID, coordinator: coordinator)
        try await coordinator.replaceAllElements(rawElementsJSON: elementsJSON)
    }

    private func applyViewportUpdate(
        _ viewportUpdate: ExcalidrawMCPUpstreamViewportUpdate?,
        fileID: String,
        fileState: FileState
    ) async throws {
        guard let viewportUpdate else { return }
        guard let coordinator = fileState.excalidrawWebCoordinator else {
            throw BridgeError.canvasUnavailable
        }

        try await waitForLoadedFile(fileID, coordinator: coordinator)
        _ = try await coordinator.setViewportFrame(.init(
            x: viewportUpdate.x,
            y: viewportUpdate.y,
            width: viewportUpdate.width,
            height: viewportUpdate.height
        ))
    }

    private func waitForLoadedFile(
        _ fileID: String,
        coordinator: ExcalidrawCanvasView.Coordinator
    ) async throws {
        let deadline = Date().addingTimeInterval(5)
        while coordinator.documentSyncController.currentLoadedFileID != fileID {
            if Date() >= deadline {
                throw BridgeError.fileLoadTimedOut
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func ensureOptimizedRawUpdateAllowed() async throws {
        guard let fileState else {
            throw BridgeError.appContextUnavailable
        }
        guard fileState.aiChatSession == nil else {
            throw BridgeError.aiGenerationInProgress
        }
        if let activeFile = fileState.currentActiveFile {
            try validateMCPWritableActiveFile(activeFile, fileState: fileState)
        }
        try await ensureMCPCanAccessActiveFile(fileState.currentActiveFile)
    }

    func ensureOptimizedUpdateViewAllowed() async throws {
        guard let fileState else {
            throw BridgeError.appContextUnavailable
        }
        guard fileState.aiChatSession == nil else {
            throw BridgeError.aiGenerationInProgress
        }
        _ = try await requireActiveFileForMCPUpdate(fileState: fileState)
    }

    private func ensureMCPCanAccessActiveFile(_ activeFile: FileState.ActiveFile?) async throws {
        guard let activeFile else { return }
        guard AIChatPreferences.shared.allowsFileAccess(for: activeFile),
              await LockedContentAIGuard.canAIRead(activeFile: activeFile) else {
            throw BridgeError.currentFileAccessDenied
        }
    }

    func optimizedActiveLibraryFileID() async throws -> String {
        guard let fileState else {
            throw BridgeError.appContextUnavailable
        }
        guard case .file(let file) = fileState.currentActiveFile else {
            throw BridgeError.unsupportedActiveFile(
                "get_checkpoints requires a library file_id or an active library file."
            )
        }
        try await ensureMCPCanAccessActiveFile(fileState.currentActiveFile)
        guard let id = file.id?.uuidString else {
            throw BridgeError.fileNotFound("active file")
        }
        return id
    }

    func optimizedChatToolContext(
        requiresMutation: Bool,
        requiresActiveFile: Bool = false
    ) async throws -> ExcalidrawChatInvocationContext {
        guard let fileState else {
            throw BridgeError.appContextUnavailable
        }
        syncCoordinatorRegistry(fileState: fileState)
        let activeFile = fileState.currentActiveFile
        if requiresActiveFile, activeFile == nil {
            throw BridgeError.unsupportedActiveFile(
                "no file is open. Call list_files and open_file, or call create_file, before this tool."
            )
        }
        if requiresMutation {
            try await ensureOptimizedRawUpdateAllowed()
        } else {
            try await ensureMCPCanAccessActiveFile(fileState.currentActiveFile)
        }

        let currentFileID: UUID? = {
            if case .file(let file) = activeFile {
                return file.id
            }
            return nil
        }()
        let canvasTarget = canvasTarget(for: activeFile)
        let currentFileData: Data? = if activeFile != nil {
            try await CurrentExcalidrawDataResolver.resolve(
                fileState: fileState,
                canvasTarget: canvasTarget
            )
        } else {
            nil
        }

        return ExcalidrawChatInvocationContext(
            currentFileData: currentFileData,
            canvasTarget: canvasTarget,
            readCanvasTarget: canvasTarget,
            currentFileID: currentFileID,
            hasActiveFile: activeFile != nil
        )
    }

    func optimizedFileAccessStatusContext() async -> ExcalidrawChatInvocationContext {
        guard let fileState else {
            return ExcalidrawChatInvocationContext(
                currentFileData: nil,
                canvasTarget: .normal,
                readCanvasTarget: .normal,
                hasActiveFile: false,
                isCurrentFileContextProtected: false
            )
        }

        let activeFile = fileState.currentActiveFile
        let currentFileID: UUID? = {
            if case .file(let file) = activeFile {
                return file.id
            }
            return nil
        }()
        let allowsFileAccess = AIChatPreferences.shared.allowsFileAccess(for: activeFile)
        let lockedContentAllowsRead = await LockedContentAIGuard.canAIRead(activeFile: activeFile)
        let isProtected = activeFile != nil && !(allowsFileAccess && lockedContentAllowsRead)
        let canvasTarget = canvasTarget(for: activeFile)

        return ExcalidrawChatInvocationContext(
            currentFileData: nil,
            canvasTarget: canvasTarget,
            readCanvasTarget: canvasTarget,
            currentFileID: currentFileID,
            hasActiveFile: activeFile != nil,
            isCurrentFileContextProtected: isProtected
        )
    }

    private func syncCoordinatorRegistry(fileState: FileState) {
        ExcalidrawCoordinatorRegistry.shared.update(
            normal: fileState.excalidrawWebCoordinator,
            collaboration: fileState.excalidrawCollaborationWebCoordinator
        )
    }

    private func canvasTarget(
        for activeFile: FileState.ActiveFile?
    ) -> ExcalidrawCoordinatorRegistry.CanvasTarget {
        switch activeFile {
            case .collaborationFile:
                .collaboration
            default:
                .normal
        }
    }

    private func canUpdateView(
        activeFile: FileState.ActiveFile?,
        canReadCurrentFile: Bool
    ) -> Bool {
        guard let activeFile else { return false }
        guard canReadCurrentFile, !activeFile.isInTrash else { return false }
        if case .collaborationFile = activeFile {
            return false
        }
        return true
    }

    private func appInfo() -> MCPJSONValue {
        .object([
            "name": .string("ExcalidrawZ"),
            "version": .string(Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "0")
        ])
    }

    private func currentFileInfo(
        _ activeFile: FileState.ActiveFile?,
        allowsFileAccess: Bool,
        lockedContentAllowsRead: Bool,
        canReadCurrentFile: Bool,
        canUpdateView: Bool
    ) -> MCPJSONValue {
        guard let activeFile else {
            return .object([
                "isOpen": .bool(false),
                "canReadContent": .bool(false),
                "canUpdateView": .bool(false),
                "message": .string("No file is currently open. Call list_files and open_file, or call create_file, before update_view.")
            ])
        }

        return .object([
            "isOpen": .bool(true),
            "id": .string(activeFile.id),
            "name": optionalString(activeFile.name),
            "kind": .string(activeFileKind(activeFile)),
            "fileType": .string(activeFile.fileType.identifier),
            "updatedAt": optionalString(activeFile.updatedAt.map { Self.iso8601String(from: $0) }),
            "isInTrash": .bool(activeFile.isInTrash),
            "allowsFileAccess": .bool(allowsFileAccess),
            "lockedContentAllowsRead": .bool(lockedContentAllowsRead),
            "canReadContent": .bool(canReadCurrentFile),
            "canUpdateView": .bool(canUpdateView)
        ])
    }

    private func currentCanvasPreferencesValue(
        for coordinator: ExcalidrawCore?,
        canReadCurrentFile: Bool
    ) async -> MCPJSONValue {
        guard canReadCurrentFile,
              let coordinator,
              coordinator.isLoading != true,
              let snapshot = try? await coordinator.fetchCanvasPreferences(),
              let value = try? mcpJSONValue(from: snapshot) else {
            return .null
        }
        return value
    }

    private func safeFetchCanvasPreferences(
        from coordinator: ExcalidrawCore
    ) async -> CanvasPreferencesSnapshot? {
        do {
            return try await coordinator.fetchCanvasPreferences()
        } catch {
            return nil
        }
    }

    private func canvasPreferencesResult(
        snapshot: CanvasPreferencesSnapshot?,
        checkpointStatus: String,
        warning: String?
    ) throws -> MCPJSONValue {
        let message = checkpointStatus == "unchanged"
            ? "Canvas preferences unchanged."
            : "Canvas preferences updated."
        var object: [String: MCPJSONValue] = [
            "message": .string(message),
            "appFileHistoryCheckpointStatus": .string(checkpointStatus),
            "canvasPreferences": .null
        ]
        if let snapshot {
            object["canvasPreferences"] = try mcpJSONValue(from: snapshot)
        }
        if let warning {
            object["appCheckpointWarning"] = .string(warning)
        }
        return .object(object)
    }

    private func mcpJSONValue<T: Encodable>(from value: T) throws -> MCPJSONValue {
        try MCPJSONValue.parse(from: value.mcpJSONData())
    }

    private func activeFileKind(_ activeFile: FileState.ActiveFile) -> String {
        switch activeFile {
            case .file:
                return "libraryFile"
            case .localFile:
                return "localFile"
            case .temporaryFile:
                return "temporaryFile"
            case .collaborationFile:
                return "collaborationFile"
        }
    }

    private func optionalString(_ value: String?) -> MCPJSONValue {
        value.map(MCPJSONValue.string) ?? .null
    }

}

private extension ExcalidrawMCPAppBridge {
    nonisolated static func iso8601String(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
