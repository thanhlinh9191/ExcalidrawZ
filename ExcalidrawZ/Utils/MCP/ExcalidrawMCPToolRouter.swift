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
                if let appResult = try await callBasicAppTool(name: name, arguments: arguments) {
                    result = appResult
                } else {
                    result = try await makeUpstreamToolHandler().callTool(
                        name: name,
                        arguments: arguments
                    )
                }
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
                return ExcalidrawMCPUpstreamToolCatalog.tools + basicAppTools
            case .optimized:
                return ExcalidrawMCPOptimizedToolCatalog.tools
        }
    }

    private var basicAppTools: [ExcalidrawMCPTool] {
        [
            ExcalidrawMCPTool(
                name: ExcalidrawMCPOptimizedContract.ToolName.listGroups,
                title: "List Groups",
                description: "Lists ExcalidrawZ library groups. Pass a non-trash group id to create_view.group_id when the client should create a new file in a specific group.",
                inputSchema: ExcalidrawMCPToolSchemas.optimizedListGroups,
                annotations: ["readOnlyHint": .bool(true)]
            ),
            ExcalidrawMCPTool(
                name: ExcalidrawMCPOptimizedContract.ToolName.getCurrentFile,
                title: "Get Current File",
                description: "Returns the currently open ExcalidrawZ file, its library/local-folder location, writable state, and canvas loaded-file alignment.",
                inputSchema: ExcalidrawMCPToolSchemas.emptyObject,
                annotations: ["readOnlyHint": .bool(true)]
            ),
            ExcalidrawMCPTool(
                name: ExcalidrawMCPOptimizedContract.ToolName.listLocalFolders,
                title: "List Local Folders",
                description: "Lists user-authorized local folders. Pass local_folder_id to create_view.local_folder_id when the client should create a local file.",
                inputSchema: ExcalidrawMCPToolSchemas.optimizedListLocalFolders,
                annotations: ["readOnlyHint": .bool(true)]
            ),
            ExcalidrawMCPTool(
                name: ExcalidrawMCPOptimizedContract.ToolName.listLocalFiles,
                title: "List Local Files",
                description: "Lists .excalidraw files inside user-authorized local folders. Use file_url with open_local_file.",
                inputSchema: ExcalidrawMCPToolSchemas.optimizedListLocalFiles,
                annotations: ["readOnlyHint": .bool(true)]
            ),
            ExcalidrawMCPTool(
                name: ExcalidrawMCPOptimizedContract.ToolName.createLocalFile,
                title: "Create Local File",
                description: "Creates and opens a new .excalidraw file inside a user-authorized local folder.",
                inputSchema: ExcalidrawMCPToolSchemas.optimizedCreateLocalFile
            ),
            ExcalidrawMCPTool(
                name: ExcalidrawMCPOptimizedContract.ToolName.openLocalFile,
                title: "Open Local File",
                description: "Opens a .excalidraw file inside a user-authorized local folder. Use list_local_files first.",
                inputSchema: ExcalidrawMCPToolSchemas.optimizedOpenLocalFile
            ),
            basicListFilesAdapter.mcpTool
        ]
    }

    private var basicListFilesAdapter: ExcalidrawMCPLLMCoreToolAdapter {
        ExcalidrawMCPLLMCoreToolAdapter(
            tool: ListAllFilesTool(),
            exposedName: ExcalidrawMCPOptimizedContract.ToolName.listFiles,
            title: "List Files",
            description: "Lists readable ExcalidrawZ library files. Locked or protected files are omitted.",
            annotations: ["readOnlyHint": .bool(true)]
        )
    }

    private func callBasicAppTool(
        name: String,
        arguments: [String: MCPJSONValue]
    ) async throws -> ExcalidrawMCPToolResult? {
        switch name {
            case ExcalidrawMCPOptimizedContract.ToolName.listGroups:
                let groups = try await ExcalidrawMCPAppBridge.shared.optimizedListGroups()
                return try jsonToolResult(
                    value: groups,
                    fallbackText: "ExcalidrawZ library groups are available."
                )
            case ExcalidrawMCPOptimizedContract.ToolName.getCurrentFile:
                let file = await ExcalidrawMCPAppBridge.shared.optimizedCurrentFile()
                return try jsonToolResult(
                    value: file,
                    fallbackText: "Current ExcalidrawZ file status is available."
                )
            case ExcalidrawMCPOptimizedContract.ToolName.listLocalFolders:
                let folders = try await ExcalidrawMCPAppBridge.shared.optimizedListLocalFolders()
                return try jsonToolResult(
                    value: folders,
                    fallbackText: "ExcalidrawZ local folders are available."
                )
            case ExcalidrawMCPOptimizedContract.ToolName.listLocalFiles:
                let files = try await ExcalidrawMCPAppBridge.shared.optimizedListLocalFiles(
                    folderID: arguments["local_folder_id"]?.stringValue,
                    deep: arguments["deep"]?.boolValue ?? true,
                    limit: min(max(Int(arguments["limit"]?.numberValue ?? 100), 1), 200)
                )
                return try jsonToolResult(
                    value: files,
                    fallbackText: "ExcalidrawZ local files are available."
                )
            case ExcalidrawMCPOptimizedContract.ToolName.createLocalFile:
                guard let localFolderID = arguments["local_folder_id"]?.stringValue,
                      !localFolderID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw MCPJSONRPCError.invalidParams("create_local_file requires arguments.local_folder_id.")
                }
                let file = try await ExcalidrawMCPAppBridge.shared.optimizedCreateLocalFile(
                    name: arguments["name"]?.stringValue,
                    localFolderID: localFolderID
                )
                return try jsonToolResult(
                    value: .object([
                        "file": file,
                        "message": .string("Created and opened a new local Excalidraw file.")
                    ]),
                    fallbackText: "Created and opened a new local Excalidraw file."
                )
            case ExcalidrawMCPOptimizedContract.ToolName.openLocalFile:
                guard let fileURL = arguments["file_url"]?.stringValue,
                      !fileURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw MCPJSONRPCError.invalidParams("open_local_file requires arguments.file_url.")
                }
                let file = try await ExcalidrawMCPAppBridge.shared.optimizedOpenLocalFile(
                    fileURL: fileURL
                )
                return try jsonToolResult(
                    value: .object([
                        "file": file,
                        "message": .string("Opened the local Excalidraw file.")
                    ]),
                    fallbackText: "Opened the local Excalidraw file."
                )
            case ExcalidrawMCPOptimizedContract.ToolName.listFiles:
                return try await basicListFilesAdapter.call(arguments: arguments)
            default:
                return nil
        }
    }

    private func jsonToolResult(
        value: MCPJSONValue,
        fallbackText: String
    ) throws -> ExcalidrawMCPToolResult {
        let data = try value.mcpJSONData(prettyPrinted: true)
        let text = String(data: data, encoding: .utf8) ?? fallbackText
        return ExcalidrawMCPToolResult(text: text, structuredContent: value)
    }

    private var instructionsForCurrentMode: String {
        switch serviceMode {
            case .basic:
                return "Use read_me first, then create_view with Excalidraw elements JSON. Use get_current_file to confirm the active target, list_groups for library group targets, or list_local_folders/list_local_files/create_local_file/open_local_file for local folder files."
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
            publishDiagram: { [store] elements, sourceElementCount, viewportUpdate, target in
                let session = try await store.publishSession(
                    elements: elements,
                    sourceElementCount: sourceElementCount,
                    viewportUpdate: viewportUpdate,
                    notifiesUpdateHandler: false
                )
                _ = try await ExcalidrawMCPAppBridge.shared.apply(
                    session,
                    createFileIfNeeded: .init(
                        name: target.name,
                        groupID: target.groupID,
                        localFolderID: target.localFolderID
                    )
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
