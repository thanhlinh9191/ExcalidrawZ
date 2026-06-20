//
//  ExcalidrawMCPToolRouter.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/14.
//

import Foundation

actor ExcalidrawMCPToolRouter {
    private let store: ExcalidrawMCPDiagramSessionStore
    private var elementConverter: ExcalidrawMCPUpstreamToolHandler.ElementConverter?
    private var serviceMode: ExcalidrawMCPServiceMode

    init(
        serviceMode: ExcalidrawMCPServiceMode = .basic,
        store: ExcalidrawMCPDiagramSessionStore = ExcalidrawMCPDiagramSessionStore()
    ) {
        self.serviceMode = serviceMode
        self.store = store
    }

    func setServiceMode(_ mode: ExcalidrawMCPServiceMode) {
        serviceMode = mode
    }

    func setSessionUpdateHandler(
        _ handler: ExcalidrawMCPDiagramSessionStore.UpdateHandler?
    ) async {
        await store.setUpdateHandler(handler)
    }

    func setElementConverter(
        _ converter: ExcalidrawMCPUpstreamToolHandler.ElementConverter?
    ) async {
        elementConverter = converter
    }

    func handle(_ request: MCPJSONRPCRequest) async -> MCPJSONRPCResponse? {
        guard request.jsonrpc == nil || request.jsonrpc == "2.0" else {
            return .failure(
                id: request.id,
                error: .invalidRequest("Only JSON-RPC 2.0 requests are supported.")
            )
        }

        do {
            let result = try await result(for: request)
            guard request.expectsResponse else { return nil }
            return .success(id: request.id, result: result)
        } catch let error as MCPJSONRPCError {
            guard request.expectsResponse else { return nil }
            return .failure(id: request.id, error: error)
        } catch {
            guard request.expectsResponse else { return nil }
            return .failure(id: request.id, error: .internalError(error.localizedDescription))
        }
    }

    private func result(for request: MCPJSONRPCRequest) async throws -> MCPJSONValue {
        switch request.method {
            case "initialize":
                return initializeResult()
            case "notifications/initialized":
                return .object([:])
            case "ping":
                return .object([:])
            case "tools/list":
                return .object([
                    "tools": .array(toolsForCurrentMode.map(\.jsonValue))
                ])
            case "tools/call":
                return try await callTool(params: request.params)
            default:
                throw MCPJSONRPCError.methodNotFound(request.method)
        }
    }

    private func initializeResult() -> MCPJSONValue {
        .object([
            "protocolVersion": .string(ExcalidrawMCPUpstreamContract.protocolVersion),
            "capabilities": .object([
                "tools": .object([:])
            ]),
            "serverInfo": .object([
                "name": .string("ExcalidrawZ"),
                "version": .string(Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString"
                ) as? String ?? "0")
            ]),
            "instructions": .string(
                instructionsForCurrentMode
            )
        ])
    }

    private func callTool(params: MCPJSONValue?) async throws -> MCPJSONValue {
        guard let object = params?.objectValue,
              let name = object["name"]?.stringValue
        else {
            throw MCPJSONRPCError.invalidParams("tools/call requires params.name.")
        }

        let arguments = object["arguments"]?.objectValue ?? [:]
        let result: ExcalidrawMCPToolResult
        switch serviceMode {
            case .basic:
                result = try await makeUpstreamToolHandler().callTool(
                    name: name,
                    arguments: arguments
                )
            case .optimized:
                result = try await makeOptimizedToolHandler().callTool(
                    name: name,
                    arguments: arguments
                )
        }
        return result.jsonValue
    }

    private var toolsForCurrentMode: [ExcalidrawMCPTool] {
        switch serviceMode {
            case .basic:
                return ExcalidrawMCPUpstreamToolCatalog.tools
            case .optimized:
                return ExcalidrawMCPOptimizedToolCatalog.tools
        }
    }

    private var instructionsForCurrentMode: String {
        switch serviceMode {
            case .basic:
                return "Use read_me first, then create_view with Excalidraw elements JSON."
            case .optimized:
                return ExcalidrawMCPOptimizedContract.instructions
        }
    }

    private func makeUpstreamToolHandler() -> ExcalidrawMCPUpstreamToolHandler {
        let converter = elementConverter
        return ExcalidrawMCPUpstreamToolHandler(
            convertRawElements: { elements in
                guard let converter else {
                    throw MCPJSONRPCError.internalError("MCP element converter is unavailable.")
                }
                return try await converter(elements)
            },
            publishDiagram: { [store] elements, sourceElementCount, viewportUpdate in
                let session = try await store.publishSession(
                    elements: elements,
                    sourceElementCount: sourceElementCount,
                    viewportUpdate: viewportUpdate,
                    notifiesUpdateHandler: false
                )
                _ = try await ExcalidrawMCPAppBridge.shared.apply(
                    session,
                    createFileIfNeeded: .init(name: nil, groupID: nil)
                )
                return ExcalidrawMCPUpstreamToolHandler.PublishedDiagram(
                    checkpointID: session.checkpointID
                )
            },
            saveCheckpointData: { [store] id, data in
                _ = try await store.saveCheckpoint(id: id, data: data)
            },
            readCheckpointData: { [store] id in
                await store.checkpoint(id: id)?.dataValue
            },
            readCheckpointElements: { [store] id in
                await store.checkpoint(id: id)?.elements
            }
        )
    }

    private func makeOptimizedToolHandler() -> ExcalidrawMCPOptimizedToolHandler {
        let converter = elementConverter
        return ExcalidrawMCPOptimizedToolHandler(
            convertRawElements: { elements in
                guard let converter else {
                    throw MCPJSONRPCError.internalError("MCP element converter is unavailable.")
                }
                return try await converter(elements)
            },
            publishDiagram: { [store] elements, sourceElementCount, viewportUpdate, clientUpdateID in
                try await ExcalidrawMCPAppBridge.shared.ensureOptimizedUpdateViewAllowed()
                let session = try await store.publishSession(
                    elements: elements,
                    sourceElementCount: sourceElementCount,
                    viewportUpdate: viewportUpdate,
                    notifiesUpdateHandler: false
                )
                let applyResult = try await ExcalidrawMCPAppBridge.shared.apply(
                    session,
                    clientUpdateID: clientUpdateID
                )
                return ExcalidrawMCPOptimizedToolHandler.PublishedDiagram(
                    appPreCheckpointID: applyResult.preCheckpointID?.uuidString,
                    appPostCheckpointID: applyResult.postCheckpointID?.uuidString,
                    appCheckpointWarning: applyResult.checkpointWarning
                )
            },
            readCheckpointElements: { [store] id in
                await store.checkpoint(id: id)?.elements
            },
            getAppContext: {
                await ExcalidrawMCPAppBridge.shared.optimizedAppContext()
            },
            getCurrentFile: {
                await ExcalidrawMCPAppBridge.shared.optimizedCurrentFile()
            },
            listGroups: {
                try await ExcalidrawMCPAppBridge.shared.optimizedListGroups()
            },
            listLocalFolders: {
                try await ExcalidrawMCPAppBridge.shared.optimizedListLocalFolders()
            },
            listLocalFiles: { folderID, deep, limit in
                try await ExcalidrawMCPAppBridge.shared.optimizedListLocalFiles(
                    folderID: folderID,
                    deep: deep,
                    limit: limit
                )
            },
            readView: { options in
                try await ExcalidrawMCPAppBridge.shared.optimizedReadView(
                    options: options
                )
            },
            createFile: { name, groupID in
                try await ExcalidrawMCPAppBridge.shared.optimizedCreateFile(
                    name: name,
                    groupID: groupID
                )
            },
            createLocalFile: { name, localFolderID in
                try await ExcalidrawMCPAppBridge.shared.optimizedCreateLocalFile(
                    name: name,
                    localFolderID: localFolderID
                )
            },
            openFile: { fileID in
                try await ExcalidrawMCPAppBridge.shared.optimizedOpenFile(
                    fileID: fileID
                )
            },
            openLocalFile: { fileURL in
                try await ExcalidrawMCPAppBridge.shared.optimizedOpenLocalFile(
                    fileURL: fileURL
                )
            },
            setCanvasPreferences: { update in
                try await ExcalidrawMCPAppBridge.shared.optimizedSetCanvasPreferences(
                    update
                )
            }
        )
    }
}

private extension MCPJSONValue {
    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
}
