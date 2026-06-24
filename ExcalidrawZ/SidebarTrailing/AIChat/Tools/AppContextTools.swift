//
//  AppContextTools.swift
//  ExcalidrawZ
//

import Foundation
import LLMCore

private enum AppContextToolJSON {
    static func text(_ value: MCPJSONValue) throws -> ToolResult {
        let data = try value.mcpJSONData()
        return .text(String(data: data, encoding: .utf8) ?? "{}")
    }

    static func parse<T: Decodable>(_ input: String, as type: T.Type) throws -> T {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try JSONDecoder().decode(T.self, from: Data("{}".utf8)) }
        guard let data = trimmed.data(using: .utf8) else {
            throw ToolError.invalidInput("Expected JSON object.")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ToolError.invalidInput("Invalid tool parameters JSON: \(error.localizedDescription)")
        }
    }
}

struct GetCurrentFileTool: Tool {
    var name: String { "get_current_file" }

    var displayName: String { String(localizable: .aiChatToolGetCurrentFileName) }

    var description: String {
        """
        Get the currently open ExcalidrawZ file status, including whether a
        file is open, whether AI can read/update it, what canvas target is
        active, and whether the loaded canvas matches the current file. Use
        this before file-sensitive actions when you need to confirm context.
        """
    }

    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(properties: [:], required: []))
    }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        try AIChatToolExecutionGate.ensureAIEnabled()
        return try AppContextToolJSON.text(
            await ExcalidrawMCPAppBridge.shared.optimizedCurrentFile()
        )
    }
}

struct ListGroupsTool: Tool {
    var name: String { "list_groups" }

    var displayName: String { String(localizable: .aiChatToolListGroupsName) }

    var description: String {
        """
        List ExcalidrawZ library groups/folders, including hierarchy, current
        group marker, file counts, and whether each group can accept new files.
        Use this when the user asks about organization or where a library file
        lives.
        """
    }

    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(properties: [:], required: []))
    }

    var approvalRequirement: ApprovalRequirement { .always }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        try AIChatToolExecutionGate.ensureAIEnabled()
        return try AppContextToolJSON.text(
            try await ExcalidrawMCPAppBridge.shared.optimizedListGroups()
        )
    }
}

struct ListLocalFoldersTool: Tool {
    var name: String { "list_local_folders" }

    var displayName: String { String(localizable: .aiChatToolListLocalFoldersName) }

    var description: String {
        """
        List registered local folders in ExcalidrawZ, including folder ids,
        paths, hierarchy, current-folder marker, and whether each folder can
        create local files.
        """
    }

    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(properties: [:], required: []))
    }

    var approvalRequirement: ApprovalRequirement { .always }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        try AIChatToolExecutionGate.ensureAIEnabled()
        return try AppContextToolJSON.text(
            try await ExcalidrawMCPAppBridge.shared.optimizedListLocalFolders()
        )
    }
}

struct ListLocalFilesTool: Tool {
    private struct Input: Decodable {
        var localFolderID: String?
        var deep: Bool?
        var limit: Int?

        enum CodingKeys: String, CodingKey {
            case localFolderID = "local_folder_id"
            case deep
            case limit
        }
    }

    var name: String { "list_local_files" }

    var displayName: String { String(localizable: .aiChatToolListLocalFilesName) }

    var description: String {
        """
        List Excalidraw files inside registered local folders. Optionally pass
        `local_folder_id`, `deep`, and `limit`. Use this when the user asks
        about local-folder files or wants to reference a local Excalidraw file.
        """
    }

    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(
            properties: [
                "local_folder_id": ParameterProperty(
                    type: "string",
                    description: "Optional local folder id from list_local_folders. If omitted, searches all registered local folders."
                ),
                "deep": ParameterProperty(
                    type: "boolean",
                    description: "Whether to include nested files. Defaults to true."
                ),
                "limit": ParameterProperty(
                    type: "integer",
                    description: "Maximum number of files to return. Defaults to 100, capped at 200."
                )
            ],
            required: []
        ))
    }

    var approvalRequirement: ApprovalRequirement { .always }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        try AIChatToolExecutionGate.ensureAIEnabled()
        let params = try AppContextToolJSON.parse(input, as: Input.self)
        return try AppContextToolJSON.text(
            try await ExcalidrawMCPAppBridge.shared.optimizedListLocalFiles(
                folderID: params.localFolderID,
                deep: params.deep ?? true,
                limit: min(max(params.limit ?? 100, 1), 200)
            )
        )
    }
}

struct SetCanvasPreferencesTool: Tool {
    private struct Input: Decodable {
        var theme: CanvasPreferencesState.Theme?
        var viewBackgroundColor: String?
        var gridModeEnabled: Bool?
        var zenModeEnabled: Bool?
        var viewModeEnabled: Bool?
        var objectsSnapModeEnabled: Bool?
        var isMidpointSnappingEnabled: Bool?
        var bindingPreference: CanvasPreferencesState.BindingPreference?
        var preferredSelectionTool: CanvasPreferencesState.PreferredSelectionTool?
        var boxSelectionMode: CanvasPreferencesState.BoxSelectionMode?
        var stats: Bool?
    }

    var name: String { "set_canvas_preferences" }

    var displayName: String { String(localizable: .aiChatToolSetCanvasPreferencesName) }

    var description: String {
        """
        Update current canvas preferences such as theme, background color,
        grid, view mode, snapping, binding, selection mode, and stats. Use
        this for explicit user requests about canvas appearance or interaction
        preferences. Changes are recorded in file history when possible.
        """
    }

    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(
            properties: [
                "theme": ParameterProperty(
                    type: "string",
                    description: "Canvas theme.",
                    enum: ["light", "dark"]
                ),
                "viewBackgroundColor": ParameterProperty(
                    type: "string",
                    description: "Canvas background hex color, e.g. #ffffff or #1e1e2e."
                ),
                "gridModeEnabled": ParameterProperty(type: "boolean", description: "Whether grid mode is enabled."),
                "zenModeEnabled": ParameterProperty(type: "boolean", description: "Whether zen mode is enabled."),
                "viewModeEnabled": ParameterProperty(type: "boolean", description: "Whether view mode is enabled."),
                "objectsSnapModeEnabled": ParameterProperty(type: "boolean", description: "Whether object snapping is enabled."),
                "isMidpointSnappingEnabled": ParameterProperty(type: "boolean", description: "Whether midpoint snapping is enabled."),
                "bindingPreference": ParameterProperty(
                    type: "string",
                    description: "Arrow binding preference.",
                    enum: ["enabled", "disabled"]
                ),
                "preferredSelectionTool": ParameterProperty(
                    type: "string",
                    description: "Preferred selection tool.",
                    enum: ["selection", "lasso"]
                ),
                "boxSelectionMode": ParameterProperty(
                    type: "string",
                    description: "Box selection mode.",
                    enum: ["contain", "overlap"]
                ),
                "stats": ParameterProperty(type: "boolean", description: "Whether stats display is enabled.")
            ],
            required: []
        ))
    }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        try AIChatToolExecutionGate.ensureAIEnabled()
        let params = try AppContextToolJSON.parse(input, as: Input.self)
        var update = CanvasPreferencesSnapshot()
        update.theme = params.theme
        update.viewBackgroundColor = try params.viewBackgroundColor.map(Self.validatedCanvasColor)
        update.gridModeEnabled = params.gridModeEnabled
        update.zenModeEnabled = params.zenModeEnabled
        update.viewModeEnabled = params.viewModeEnabled
        update.objectsSnapModeEnabled = params.objectsSnapModeEnabled
        update.isMidpointSnappingEnabled = params.isMidpointSnappingEnabled
        update.bindingPreference = params.bindingPreference
        update.preferredSelectionTool = params.preferredSelectionTool
        update.boxSelectionMode = params.boxSelectionMode
        update.stats = params.stats

        return try AppContextToolJSON.text(
            try await ExcalidrawMCPAppBridge.shared.optimizedSetCanvasPreferences(update)
        )
    }

    private static func validatedCanvasColor(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"#
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else {
            throw ToolError.invalidInput("viewBackgroundColor must be a hex color like #ffffff, #fff, or #1e1e2eff.")
        }
        return trimmed
    }
}
