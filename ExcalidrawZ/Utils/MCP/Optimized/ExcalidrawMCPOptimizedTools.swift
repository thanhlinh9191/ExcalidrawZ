//
//  ExcalidrawMCPOptimizedTools.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/16.
//

import Foundation
import LLMCore

enum ExcalidrawMCPOptimizedContract {
    static let instructions = """
    Use read_me first. It includes the full upstream excalidraw-mcp drawing guide
    plus ExcalidrawZ Optimized notes. Open or create a file first, then use
    update_view with Excalidraw raw elements JSON. update_view only updates the
    user's current ExcalidrawZ file.
    After update_view changes visible content, call read_canvas_image once to
    inspect the rendered canvas before giving the user a final answer.
    Use get_app_context, get_current_file, file_access_status, list_groups,
    list_files, list_local_folders, list_local_files, create_file,
    create_local_file, open_file, open_local_file, read_file, read_view,
    set_canvas_preferences, export, navigate_canvas,
    get_current_file_checkpoints, rename_file, restore_file_history,
    list_libraries, list_library_items, query_library_item,
    add_library_item_to_canvas, read_canvas_image, and adjust_elements when you
    need app, file, history, library, visual, export, or canvas context.
    """

    enum ToolName {
        static let readMe = ExcalidrawMCPUpstreamContract.ToolName.readMe
        static let readView = "read_view"
        static let updateView = "update_view"
        static let getAppContext = "get_app_context"
        static let getCurrentFile = "get_current_file"
        static let listGroups = "list_groups"
        static let listFiles = "list_files"
        static let listLocalFolders = "list_local_folders"
        static let listLocalFiles = "list_local_files"
        static let getCurrentFileCheckpoints = "get_current_file_checkpoints"
        static let createFile = "create_file"
        static let createLocalFile = "create_local_file"
        static let openFile = "open_file"
        static let openLocalFile = "open_local_file"
        static let setCanvasPreferences = "set_canvas_preferences"
    }
}

enum ExcalidrawMCPOptimizedRecall {
    static let guide = """
    # ExcalidrawZ Optimized MCP

    This mode uses the upstream excalidraw-mcp raw Excalidraw element workflow
    as its drawing foundation. The full upstream guide is included below and
    remains the primary reference for colors, cameraUpdate, examples, animation,
    and common mistakes.

    Default flow:
    1. Read the upstream guide below.
    2. Generate raw Excalidraw elements using the same format.
    3. If no file is open, call list_files and open_file, or call create_file.
       Use list_groups first when the user asks to create the file in a
       particular ExcalidrawZ group. Use list_local_folders / create_local_file
       / open_local_file when the target should be a user-authorized local
       folder file.
    4. Call update_view, not create_view.
    5. After update_view changes visible content, call read_canvas_image once
       before the final answer.
    6. Inspect the image for obvious layout, spacing, overlap, text, contrast,
       and rendering issues. If something is wrong, usually fix it with
       update_view; use adjust_elements only for small targeted patches.

    ExcalidrawZ differences:
    - update_view updates the user's current ExcalidrawZ file.
    - update_view does not create or open files. If no file is open, call
      list_files and open_file, call create_file, or use the local-folder tools
      for local files. Pass create_file.group_id when the user wants the new
      library file in a specific ExcalidrawZ group. list_files omits locked or
      protected files that MCP cannot access.
    - get_current_file is the quickest way to confirm the current file and its
      location before a mutation. get_app_context.currentFile is the broader
      app-context source of truth for whether a file is open/readable/writable.
      canvas.loadedFileId is only populated when the WebView loaded file is
      aligned with currentFile.
    - update_view records ExcalidrawZ File History checkpoints around the
      mutation when the target supports history: mcp_pre before the update and
      mcp_post after the update. update_view does not return checkpoint ids.
      Call get_current_file_checkpoints when you need current-file App
      checkpoint ids for context or rollback, then use restore_file_history
      only when the user asks to roll back a saved library file state.
    - Pass client_update_id to update_view when available. ExcalidrawZ stores it
      in File History checkpoint descriptions and treats repeated requests with
      the same current file + client_update_id as idempotent retries.
    - If the user asks to change canvas-level preferences such as theme,
      background color, grid, zen mode, view mode, snap settings, arrow
      binding, lasso selection, or canvas stats, call set_canvas_preferences.
      Do not add a giant background rectangle to simulate canvas theme.
      Theme and viewBackgroundColor are separate canvas preferences; dark
      theme may still report a white viewBackgroundColor. Use
      read_canvas_image to inspect the actual rendered appearance.

    Optional app tools:
    - Use read_file for targeted structural reads of the current canvas.
    - Use read_canvas_image as the normal visual self-check after update_view.
      Skip it only when the user explicitly asks for speed/no visual check, when
      no visible canvas content changed, or when the tool reports that the
      canvas cannot be captured.
    - Use export when the user asks for an artifact: kind=image for PNG/SVG,
      kind=file for an .excalidraw file, or kind=pdf for vector/lossless PDF.
      For visual inspection, normally use read_canvas_image. Use export
      kind=pdf for inspection only when the canvas is too large or detailed for
      read_canvas_image and the MCP client/model can inspect PDF documents or
      specific PDF regions.
    - Use read_view only when you need the broader Excalidraw payload.
    - Use set_canvas_preferences for canvas-level preferences such as
      theme, viewBackgroundColor, gridModeEnabled, zenModeEnabled,
      viewModeEnabled, objectsSnapModeEnabled, isMidpointSnappingEnabled,
      bindingPreference, preferredSelectionTool, boxSelectionMode, and stats.
    - update_view is the primary drawing mutation tool. Use it for new drawings,
      whole-scene replacement, or any edit where you can provide the complete
      revised raw elements array.
    - Use insert_math for LaTeX formulas and function plots. It renders the
      math as a canvas image and inserts it into the currently open file.
    - Use adjust_elements only for small targeted patches to the currently open
      file, such as adding a few elements, editing known element ids, deleting a
      small set, or inserting Mermaid content. Do not use adjust_elements for
      math insertion, whole-scene creation, or replacement.
    - Use navigate_canvas for viewport/camera changes.
    - Use list_groups, list_files, create_file, open_file, list_local_folders,
      list_local_files, create_local_file, open_local_file, and
      get_current_file_checkpoints for file, group, folder, and history
      context.
    - Use list_libraries, list_library_items, query_library_item, and
      add_library_item_to_canvas for reusable library content.
    - Use rename_file and restore_file_history only when the user explicitly
      asks for those file-level changes.

    Important:
    - Do not replace the upstream layout/camera guidance with these notes.
      These notes only tell you which ExcalidrawZ tool to use.
    - The raw element examples below should be sent through update_view in this
      Optimized mode.

    \(upstreamGuideForOptimizedMode)
    """

    private static let upstreamGuideForOptimizedMode = optimizedUpstreamGuide()

    private static func optimizedUpstreamGuide() -> String {
        var guide = ExcalidrawMCPUpstreamRecall.cheatSheet
        guide = guide.replacingOccurrences(
            of: "Now use create_view to draw.",
            with: "Now use update_view to draw."
        )
        .replacingOccurrences(
            of: "using create_view for the first time.",
            with: "using update_view for the first time."
        )
        .replacingOccurrences(
            of: "Every create_view call returns a `checkpointId` in its response. To continue from a previous diagram state, start your elements array with a restoreCheckpoint element:",
            with: "Optimized update_view records ExcalidrawZ File History checkpoints instead of returning a restoreCheckpoint id. To inspect current-file history, call get_current_file_checkpoints. To roll back a library file, use restore_file_history with an App checkpoint id. For ordinary revisions, inspect the current result with read_view or read_canvas_image, then send the complete revised elements array to update_view."
        )
        .replacingOccurrences(
            of: "`[{\"type\":\"restoreCheckpoint\",\"id\":\"<checkpointId>\"}, ...additional new elements...]`",
            with: "Do not rely on update_view to return a `checkpointId` in Optimized mode."
        )
        .replacingOccurrences(
            of: "The saved state (including any user edits made in fullscreen) is loaded from the client, and your new elements are appended on top. This saves tokens — you don't need to re-send the entire diagram.",
            with: "ExcalidrawZ owns File History checkpoints. Use get_current_file_checkpoints when the user asks about current-file history, rollback, or previous states."
        )
        .replacingOccurrences(
            of: "- **With restoreCheckpoint**: restore a saved state, then surgically remove specific elements before adding new ones",
            with: "- **With App File History**: call get_current_file_checkpoints / restore_file_history when the user asks to roll back a saved library file state"
        )
        .replacingOccurrences(
            of: "If the user asks to revise, call create_view again",
            with: "If the user asks to revise, call update_view again"
        )
        return replacingDarkModeWorkaround(in: guide)
    }

    private static func replacingDarkModeWorkaround(in guide: String) -> String {
        guard let darkModeTitle = guide.range(of: "## Dark Mode"),
              let tipsTitle = guide.range(
                of: "## Tips",
                range: darkModeTitle.upperBound..<guide.endIndex
              )
        else {
            return guide
        }

        let start = guide[..<darkModeTitle.lowerBound].lastIndex(of: "\n")
            ?? guide.startIndex
        let end = guide[..<tipsTitle.lowerBound].lastIndex(of: "\n")
            ?? tipsTitle.lowerBound
        var result = guide
        result.replaceSubrange(
            start..<end,
            with: """

            ## Canvas Preferences

            In Optimized mode, use set_canvas_preferences for canvas-level
            preferences such as theme, background color, grid, zen mode, view
            mode, snapping, arrow binding, selection mode, or stats. Do not
            simulate canvas theme with a giant background rectangle.
            When changing theme or canvas background, choose text and stroke
            colors that contrast with the resulting background. Do not rely on
            Excalidraw's default text/stroke color unless it remains readable.

            """
        )
        return result
    }
}

extension ExcalidrawMCPToolSchemas {
    static let optimizedReadView: MCPJSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "include_elements": .object([
                "type": .string("boolean"),
                "description": .string("Include the current Excalidraw elements array. Defaults to true.")
            ]),
            "include_app_state": .object([
                "type": .string("boolean"),
                "description": .string("Include the current Excalidraw appState object. Defaults to true.")
            ]),
            "include_files": .object([
                "type": .string("boolean"),
                "description": .string("Include Excalidraw binary file metadata/data. Defaults to false to keep responses compact.")
            ])
        ]),
        "additionalProperties": .bool(false)
    ])

    static let optimizedUpdateView: MCPJSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "elements": .object([
                "type": .string("string"),
                "description": .string(
                    "JSON array string of Excalidraw raw elements. Must be valid JSON — no comments, no trailing commas. Keep compact.\nCall read_me first for format reference."
                )
            ]),
            "client_update_id": .object([
                "type": .string("string"),
                "description": .string("Optional MCP client request/message id. ExcalidrawZ stores it in App file-history checkpoint descriptions for easier client-side correlation.")
            ])
        ]),
        "required": .array([.string("elements")]),
        "additionalProperties": .bool(false)
    ])

    static let optimizedCreateFile: MCPJSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "name": .object([
                "type": .string("string"),
                "description": .string("Optional name for the new ExcalidrawZ file. The new file is opened immediately.")
            ]),
            "group_id": .object([
                "type": .string("string"),
                "description": .string("Optional UUID of a non-trash ExcalidrawZ library group returned by list_groups. If omitted, ExcalidrawZ uses the current active group or the default group.")
            ])
        ]),
        "additionalProperties": .bool(false)
    ])

    static let optimizedListGroups: MCPJSONValue = .object([
        "type": .string("object"),
        "properties": .object([:]),
        "additionalProperties": .bool(false)
    ])

    static let optimizedListLocalFolders: MCPJSONValue = .object([
        "type": .string("object"),
        "properties": .object([:]),
        "additionalProperties": .bool(false)
    ])

    static let optimizedListLocalFiles: MCPJSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "local_folder_id": .object([
                "type": .string("string"),
                "description": .string("Optional local folder id returned by list_local_folders. If omitted, searches all registered local folders.")
            ]),
            "deep": .object([
                "type": .string("boolean"),
                "description": .string("Whether to include nested subfolders. Defaults to true.")
            ]),
            "limit": .object([
                "type": .string("integer"),
                "description": .string("Maximum local files to return, capped at 200. Defaults to 100.")
            ])
        ]),
        "additionalProperties": .bool(false)
    ])

    static let optimizedCreateLocalFile: MCPJSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "local_folder_id": .object([
                "type": .string("string"),
                "description": .string("Local folder id returned by list_local_folders. The folder must still be accessible.")
            ]),
            "name": .object([
                "type": .string("string"),
                "description": .string("Optional file name. `.excalidraw` is added automatically when omitted.")
            ])
        ]),
        "required": .array([.string("local_folder_id")]),
        "additionalProperties": .bool(false)
    ])

    static let optimizedOpenLocalFile: MCPJSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "file_url": .object([
                "type": .string("string"),
                "description": .string("Local file URL returned by list_local_files. Plain absolute paths are also accepted when they are inside a registered local folder.")
            ])
        ]),
        "required": .array([.string("file_url")]),
        "additionalProperties": .bool(false)
    ])

    static let optimizedOpenFile: MCPJSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "file_id": .object([
                "type": .string("string"),
                "description": .string("UUID of a readable library file returned by list_files. Locked or protected files are omitted by list_files and cannot be opened for MCP.")
            ])
        ]),
        "required": .array([.string("file_id")]),
        "additionalProperties": .bool(false)
    ])

    static let optimizedSetCanvasPreferences: MCPJSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "theme": .object([
                "type": .string("string"),
                "description": .string("Canvas theme."),
                "enum": .array([.string("light"), .string("dark")])
            ]),
            "viewBackgroundColor": .object([
                "type": .string("string"),
                "description": .string("Canvas background color as a hex color such as #ffffff or #1e1e2e."),
                "pattern": .string(#"^#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"#)
            ]),
            "gridModeEnabled": .object([
                "type": .string("boolean"),
                "description": .string("Show or hide the canvas grid.")
            ]),
            "zenModeEnabled": .object([
                "type": .string("boolean"),
                "description": .string("Enable or disable Excalidraw zen mode.")
            ]),
            "viewModeEnabled": .object([
                "type": .string("boolean"),
                "description": .string("Enable or disable view mode.")
            ]),
            "objectsSnapModeEnabled": .object([
                "type": .string("boolean"),
                "description": .string("Enable or disable object snapping.")
            ]),
            "isMidpointSnappingEnabled": .object([
                "type": .string("boolean"),
                "description": .string("Enable or disable midpoint snapping.")
            ]),
            "bindingPreference": .object([
                "type": .string("string"),
                "description": .string("Arrow binding preference."),
                "enum": .array([.string("enabled"), .string("disabled")])
            ]),
            "preferredSelectionTool": .object([
                "type": .string("string"),
                "description": .string("Selection tool preference."),
                "enum": .array([.string("selection"), .string("lasso")])
            ]),
            "boxSelectionMode": .object([
                "type": .string("string"),
                "description": .string("Box selection behavior: contain requires full containment; overlap selects intersecting elements."),
                "enum": .array([.string("contain"), .string("overlap")])
            ]),
            "stats": .object([
                "type": .string("boolean"),
                "description": .string("Show or hide Excalidraw canvas stats.")
            ])
        ]),
        "additionalProperties": .bool(false)
    ])

    static let optimizedExport: MCPJSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "kind": .object([
                "type": .string("string"),
                "description": .string("Export artifact kind: image, file, or pdf."),
                "enum": .array([.string("image"), .string("file"), .string("pdf")])
            ]),
            "format": .object([
                "type": .string("string"),
                "description": .string("Image format when kind is image. Defaults to png."),
                "enum": .array([.string("png"), .string("svg")])
            ]),
            "editable": .object([
                "type": .string("boolean"),
                "description": .string("For image export, embed the Excalidraw scene in PNG/SVG so it remains editable. Defaults to false.")
            ]),
            "with_background": .object([
                "type": .string("boolean"),
                "description": .string("Whether image/PDF export includes the canvas background. Defaults to true.")
            ]),
            "color_scheme": .object([
                "type": .string("string"),
                "description": .string("Export color scheme for image/PDF. Defaults to light."),
                "enum": .array([.string("light"), .string("dark")])
            ]),
            "export_scale": .object([
                "type": .string("integer"),
                "description": .string("PNG scale, 1, 2, or 3. Only applies to image png export. Defaults to 1.")
            ])
        ]),
        "required": .array([.string("kind")]),
        "additionalProperties": .bool(false)
    ])

    static let optimizedGetCurrentFileCheckpoints: MCPJSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "limit": .object([
                "type": .string("integer"),
                "description": .string("Maximum checkpoints to return, capped at 200. Defaults to 50.")
            ]),
            "ai_only": .object([
                "type": .string("boolean"),
                "description": .string("If true, only return automated checkpoints. Defaults to false.")
            ])
        ]),
        "additionalProperties": .bool(false)
    ])

    static let optimizedRenameFile: MCPJSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "new_name": .object([
                "type": .string("string"),
                "description": .string("New visible filename, without `.excalidraw`.")
            ]),
            "file_id": .object([
                "type": .string("string"),
                "description": .string("Optional UUID of a library file returned by list_files. If omitted, uses the current library file.")
            ])
        ]),
        "required": .array([.string("new_name")]),
        "additionalProperties": .bool(false)
    ])
}

enum ExcalidrawMCPOptimizedToolCatalog {
    static var tools: [ExcalidrawMCPTool] {
        baseTools + appToolAdapters.map(\.mcpTool) + [updateViewTool]
    }

    static let appToolAdapters: [ExcalidrawMCPLLMCoreToolAdapter] = [
        ExcalidrawMCPLLMCoreToolAdapter(
            tool: FileAccessStatusTool(),
            title: "File Access Status",
            annotations: ["readOnlyHint": .bool(true)],
            contextProvider: {
                await ExcalidrawMCPAppBridge.shared.optimizedFileAccessStatusContext()
            }
        ),
        ExcalidrawMCPLLMCoreToolAdapter(
            tool: ReadFileTool(),
            title: "Read File",
            annotations: ["readOnlyHint": .bool(true)],
            contextProvider: {
                try await ExcalidrawMCPAppBridge.shared.optimizedChatToolContext(
                    requiresMutation: false
                )
            }
        ),
        ExcalidrawMCPLLMCoreToolAdapter(
            tool: ReadCanvasImageTool(),
            title: "Read Canvas Image",
            description: "Exports the active ExcalidrawZ canvas as a PNG image. After update_view changes visible content, call this once before the final answer to inspect layout, colors, spacing, text, and rendering quality.",
            annotations: ["readOnlyHint": .bool(true)],
            contextProvider: {
                try await ExcalidrawMCPAppBridge.shared.optimizedChatToolContext(
                    requiresMutation: false
                )
            }
        ),
        ExcalidrawMCPLLMCoreToolAdapter(
            tool: ExportTool(),
            title: "Export",
            description: "Exports the active ExcalidrawZ canvas as an artifact. Use kind=image for PNG/SVG, kind=file for .excalidraw, or kind=pdf for lossless PDF. Use read_canvas_image for ordinary visual inspection.",
            schemaOverride: ExcalidrawMCPToolSchemas.optimizedExport,
            annotations: ["readOnlyHint": .bool(true)],
            contextProvider: {
                try await ExcalidrawMCPAppBridge.shared.optimizedChatToolContext(
                    requiresMutation: false,
                    requiresActiveFile: true
                )
            }
        ),
        ExcalidrawMCPLLMCoreToolAdapter(
            tool: NavigateCanvasTool(),
            title: "Navigate Canvas",
            contextProvider: {
                try await ExcalidrawMCPAppBridge.shared.optimizedChatToolContext(
                    requiresMutation: false
                )
            }
        ),
        ExcalidrawMCPLLMCoreToolAdapter(
            tool: InsertMathTool(),
            title: "Math",
            description: "Insert math content into the active ExcalidrawZ file. Use mode=formula for LaTeX equations and mode=function for plotted function graphs. Prefer this over adjust_elements for formula or graph insertion.",
            contextProvider: {
                try await ExcalidrawMCPAppBridge.shared.optimizedChatToolContext(
                    requiresMutation: true,
                    requiresActiveFile: true
                )
            },
            mutationCheckpointDescription: "MCP insert_math"
        ),
        ExcalidrawMCPLLMCoreToolAdapter(
            tool: AdjustElementsTool(),
            title: "Adjust Elements",
            description: "Targeted patch tool for the currently open ExcalidrawZ file. Use update_view for new drawings, whole-scene replacement, or complete raw-elements updates. Use adjust_elements only for small incremental add/update/delete/Mermaid edits when preserving the rest of the canvas is important.",
            contextProvider: {
                try await ExcalidrawMCPAppBridge.shared.optimizedChatToolContext(
                    requiresMutation: true,
                    requiresActiveFile: true
                )
            },
            mutationCheckpointDescription: "MCP adjust_elements"
        ),
        ExcalidrawMCPLLMCoreToolAdapter(
            tool: RenameFileTool(),
            title: "Rename File",
            description: "Rename a drawing file in the user's iCloud-synced library. If file_id is omitted, this renames the currently open library file. Use list_files first when the user wants to rename a different file.",
            schemaOverride: ExcalidrawMCPToolSchemas.optimizedRenameFile,
            contextProvider: {
                try await ExcalidrawMCPAppBridge.shared.optimizedChatToolContext(
                    requiresMutation: true
                )
            }
        ),
        ExcalidrawMCPLLMCoreToolAdapter(
            tool: ListAllFilesTool(),
            exposedName: ExcalidrawMCPOptimizedContract.ToolName.listFiles,
            title: "List Files",
            description: "Lists readable library files so the MCP client can choose a file for follow-up work.",
            annotations: ["readOnlyHint": .bool(true)]
        ),
        ExcalidrawMCPLLMCoreToolAdapter(
            tool: QueryFileHistoryTool(),
            exposedName: ExcalidrawMCPOptimizedContract.ToolName.getCurrentFileCheckpoints,
            title: "Get Current File Checkpoints",
            description: "Lists checkpoint metadata for the currently open library or local file.",
            schemaOverride: ExcalidrawMCPToolSchemas.optimizedGetCurrentFileCheckpoints,
            annotations: ["readOnlyHint": .bool(true)],
            normalizeArguments: { arguments in
                var normalized = arguments
                normalized.removeValue(forKey: "file_id")
                normalized.removeValue(forKey: "file_url")
                for (key, value) in try await ExcalidrawMCPAppBridge.shared.optimizedActiveCheckpointTargetArguments() {
                    normalized[key] = value
                }
                return normalized
            }
        ),
        ExcalidrawMCPLLMCoreToolAdapter(
            tool: ListLibrariesTool(),
            title: "List Libraries",
            annotations: ["readOnlyHint": .bool(true)]
        ),
        ExcalidrawMCPLLMCoreToolAdapter(
            tool: ListLibraryItemsTool(),
            title: "List Library Items",
            description: "List items inside a library. Get library_id values from list_libraries. Use query_library_item when you need one item's full raw element payload.",
            annotations: ["readOnlyHint": .bool(true)]
        ),
        ExcalidrawMCPLLMCoreToolAdapter(
            tool: QueryLibraryItemTool(),
            title: "Query Library Item",
            annotations: ["readOnlyHint": .bool(true)]
        ),
        ExcalidrawMCPLLMCoreToolAdapter(
            tool: AddLibraryItemToCanvasTool(),
            title: "Add Library Item to Canvas",
            contextProvider: {
                try await ExcalidrawMCPAppBridge.shared.optimizedChatToolContext(
                    requiresMutation: true
                )
            }
        ),
        ExcalidrawMCPLLMCoreToolAdapter(
            tool: RestoreFileHistoryTool(),
            title: "Restore File History",
            description: "Restore the current library file to a specific checkpoint. Get checkpoint_id from get_current_file_checkpoints. This overwrites the file's current content.",
            contextProvider: {
                try await ExcalidrawMCPAppBridge.shared.optimizedChatToolContext(
                    requiresMutation: true
                )
            }
        )
    ]

    private static let baseTools: [ExcalidrawMCPTool] = [
        ExcalidrawMCPTool(
            name: ExcalidrawMCPOptimizedContract.ToolName.readMe,
            title: "Read ExcalidrawZ Optimized MCP Guide",
            description: "Returns the full upstream excalidraw-mcp drawing guide plus ExcalidrawZ Optimized update workflow notes. Call this first when using Optimized MCP.",
            inputSchema: ExcalidrawMCPToolSchemas.emptyObject,
            annotations: ["readOnlyHint": .bool(true)]
        ),
        ExcalidrawMCPTool(
            name: ExcalidrawMCPOptimizedContract.ToolName.getAppContext,
            title: "Get App Context",
            description: "Returns the current window, file, canvas, and access state for MCP clients.",
            inputSchema: ExcalidrawMCPToolSchemas.emptyObject,
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
            name: ExcalidrawMCPOptimizedContract.ToolName.listGroups,
            title: "List Groups",
            description: "Lists ExcalidrawZ library groups. Pass a non-trash group id to create_file.group_id when creating a new library file in a specific group.",
            inputSchema: ExcalidrawMCPToolSchemas.optimizedListGroups,
            annotations: ["readOnlyHint": .bool(true)]
        ),
        ExcalidrawMCPTool(
            name: ExcalidrawMCPOptimizedContract.ToolName.listLocalFolders,
            title: "List Local Folders",
            description: "Lists user-authorized local folders. Use local_folder_id with list_local_files or create_local_file.",
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
            name: ExcalidrawMCPOptimizedContract.ToolName.createFile,
            title: "Create File",
            description: "Creates and opens a new ExcalidrawZ library file. Use group_id from list_groups when the user wants the file in a specific group.",
            inputSchema: ExcalidrawMCPToolSchemas.optimizedCreateFile
        ),
        ExcalidrawMCPTool(
            name: ExcalidrawMCPOptimizedContract.ToolName.createLocalFile,
            title: "Create Local File",
            description: "Creates and opens a new .excalidraw file inside a user-authorized local folder.",
            inputSchema: ExcalidrawMCPToolSchemas.optimizedCreateLocalFile
        ),
        ExcalidrawMCPTool(
            name: ExcalidrawMCPOptimizedContract.ToolName.openFile,
            title: "Open File",
            description: "Opens a readable ExcalidrawZ library file by id. Use list_files first; locked or protected files are omitted and cannot be opened for MCP.",
            inputSchema: ExcalidrawMCPToolSchemas.optimizedOpenFile
        ),
        ExcalidrawMCPTool(
            name: ExcalidrawMCPOptimizedContract.ToolName.openLocalFile,
            title: "Open Local File",
            description: "Opens a .excalidraw file inside a user-authorized local folder. Use list_local_files first.",
            inputSchema: ExcalidrawMCPToolSchemas.optimizedOpenLocalFile
        ),
        ExcalidrawMCPTool(
            name: ExcalidrawMCPOptimizedContract.ToolName.readView,
            title: "Read View",
            description: "Reads the active ExcalidrawZ canvas when the current file allows AI/MCP access.",
            inputSchema: ExcalidrawMCPToolSchemas.optimizedReadView,
            annotations: ["readOnlyHint": .bool(true)]
        ),
        ExcalidrawMCPTool(
            name: ExcalidrawMCPOptimizedContract.ToolName.setCanvasPreferences,
            title: "Set Canvas Preferences",
            description: "Updates canvas-level preferences for the currently open ExcalidrawZ file, such as theme, background color, grid, zen mode, view mode, snapping, arrow binding, selection mode, and stats.",
            inputSchema: ExcalidrawMCPToolSchemas.optimizedSetCanvasPreferences
        )
    ]

    private static let updateViewTool = ExcalidrawMCPTool(
        name: ExcalidrawMCPOptimizedContract.ToolName.updateView,
        title: "Update View",
        description: "Updates the currently open ExcalidrawZ file with raw Excalidraw elements. Call list_files/open_file, list_local_files/open_local_file, create_file, or create_local_file first when no file is open.",
        inputSchema: ExcalidrawMCPToolSchemas.optimizedUpdateView
    )
}

struct ExcalidrawMCPOptimizedToolHandler {
    struct PublishedDiagram: Sendable {
        let appPreCheckpointID: String?
        let appPostCheckpointID: String?
        let appCheckpointWarning: String?

        init(
            appPreCheckpointID: String? = nil,
            appPostCheckpointID: String? = nil,
            appCheckpointWarning: String? = nil
        ) {
            self.appPreCheckpointID = appPreCheckpointID
            self.appPostCheckpointID = appPostCheckpointID
            self.appCheckpointWarning = appCheckpointWarning
        }
    }

    struct CurrentCanvasOptions: Sendable {
        var includeElements: Bool = true
        var includeAppState: Bool = true
        var includeFiles: Bool = false
    }

    typealias ElementConverter = @Sendable ([MCPJSONValue]) async throws -> [MCPJSONValue]
    typealias PublishDiagram = @Sendable (
        _ elements: [MCPJSONValue],
        _ sourceElementCount: Int,
        _ viewportUpdate: ExcalidrawMCPUpstreamViewportUpdate?,
        _ clientUpdateID: String?
    ) async throws -> PublishedDiagram
    typealias ReadCheckpointElements = @Sendable (_ id: String) async -> [MCPJSONValue]?
    typealias GetAppContext = @Sendable () async throws -> MCPJSONValue
    typealias GetCurrentFile = @Sendable () async throws -> MCPJSONValue
    typealias ListGroups = @Sendable () async throws -> MCPJSONValue
    typealias ListLocalFolders = @Sendable () async throws -> MCPJSONValue
    typealias ListLocalFiles = @Sendable (_ folderID: String?, _ deep: Bool, _ limit: Int) async throws -> MCPJSONValue
    typealias ReadView = @Sendable (_ options: CurrentCanvasOptions) async throws -> MCPJSONValue
    typealias CreateFile = @Sendable (_ name: String?, _ groupID: String?) async throws -> MCPJSONValue
    typealias CreateLocalFile = @Sendable (_ name: String?, _ localFolderID: String) async throws -> MCPJSONValue
    typealias OpenFile = @Sendable (_ fileID: String) async throws -> MCPJSONValue
    typealias OpenLocalFile = @Sendable (_ fileURL: String) async throws -> MCPJSONValue
    typealias SetCanvasPreferences = @Sendable (_ update: CanvasPreferencesSnapshot) async throws -> MCPJSONValue

    var convertRawElements: ElementConverter
    var publishDiagram: PublishDiagram
    var readCheckpointElements: ReadCheckpointElements
    var getAppContext: GetAppContext
    var getCurrentFile: GetCurrentFile
    var listGroups: ListGroups
    var listLocalFolders: ListLocalFolders
    var listLocalFiles: ListLocalFiles
    var readView: ReadView
    var createFile: CreateFile
    var createLocalFile: CreateLocalFile
    var openFile: OpenFile
    var openLocalFile: OpenLocalFile
    var setCanvasPreferences: SetCanvasPreferences
    var appToolAdapters: [String: ExcalidrawMCPLLMCoreToolAdapter] = Dictionary(
        uniqueKeysWithValues: ExcalidrawMCPOptimizedToolCatalog.appToolAdapters.map {
            ($0.exposedName, $0)
        }
    )

    func callTool(
        name: String,
        arguments: [String: MCPJSONValue]
    ) async throws -> ExcalidrawMCPToolResult {
        switch name {
            case ExcalidrawMCPOptimizedContract.ToolName.readMe:
                return ExcalidrawMCPToolResult(text: ExcalidrawMCPOptimizedRecall.guide)

            case ExcalidrawMCPOptimizedContract.ToolName.getAppContext:
                return try await appContext()

            case ExcalidrawMCPOptimizedContract.ToolName.getCurrentFile:
                return try await currentFile()

            case ExcalidrawMCPOptimizedContract.ToolName.listGroups:
                return try await listGroupsTool(arguments: arguments)

            case ExcalidrawMCPOptimizedContract.ToolName.listLocalFolders:
                return try await listLocalFoldersTool(arguments: arguments)

            case ExcalidrawMCPOptimizedContract.ToolName.listLocalFiles:
                return try await listLocalFilesTool(arguments: arguments)

            case ExcalidrawMCPOptimizedContract.ToolName.readView:
                return try await readView(arguments: arguments)

            case ExcalidrawMCPOptimizedContract.ToolName.createFile:
                return try await createFileTool(arguments: arguments)

            case ExcalidrawMCPOptimizedContract.ToolName.createLocalFile:
                return try await createLocalFileTool(arguments: arguments)

            case ExcalidrawMCPOptimizedContract.ToolName.openFile:
                return try await openFileTool(arguments: arguments)

            case ExcalidrawMCPOptimizedContract.ToolName.openLocalFile:
                return try await openLocalFileTool(arguments: arguments)

            case ExcalidrawMCPOptimizedContract.ToolName.setCanvasPreferences:
                return try await setCanvasPreferencesTool(arguments: arguments)

            case ExcalidrawMCPOptimizedContract.ToolName.updateView:
                return try await updateView(arguments: arguments)

            default:
                if let adapter = appToolAdapters[name] {
                    return try await adapter.call(arguments: arguments)
                }
                throw MCPJSONRPCError.invalidParams("Unknown tool: \(name)")
        }
    }

    private func appContext() async throws -> ExcalidrawMCPToolResult {
        let context = try await getAppContext()
        return try jsonToolResult(
            value: context,
            fallbackText: "ExcalidrawZ app context is available."
        )
    }

    private func currentFile() async throws -> ExcalidrawMCPToolResult {
        let file = try await getCurrentFile()
        return try jsonToolResult(
            value: file,
            fallbackText: "Current ExcalidrawZ file status is available."
        )
    }

    private func listGroupsTool(arguments: [String: MCPJSONValue]) async throws -> ExcalidrawMCPToolResult {
        let groups = try await listGroups()
        return try jsonToolResult(
            value: groups,
            fallbackText: "ExcalidrawZ library groups are available."
        )
    }

    private func listLocalFoldersTool(arguments: [String: MCPJSONValue]) async throws -> ExcalidrawMCPToolResult {
        let folders = try await listLocalFolders()
        return try jsonToolResult(
            value: folders,
            fallbackText: "ExcalidrawZ local folders are available."
        )
    }

    private func listLocalFilesTool(arguments: [String: MCPJSONValue]) async throws -> ExcalidrawMCPToolResult {
        let files = try await listLocalFiles(
            arguments["local_folder_id"]?.stringValue,
            arguments["deep"]?.boolValue ?? true,
            min(max(Int(arguments["limit"]?.numberValue ?? 100), 1), 200)
        )
        return try jsonToolResult(
            value: files,
            fallbackText: "ExcalidrawZ local files are available."
        )
    }

    private func readView(arguments: [String: MCPJSONValue]) async throws -> ExcalidrawMCPToolResult {
        let options = CurrentCanvasOptions(
            includeElements: arguments["include_elements"]?.boolValue ?? true,
            includeAppState: arguments["include_app_state"]?.boolValue ?? true,
            includeFiles: arguments["include_files"]?.boolValue ?? false
        )
        let canvas = try await readView(options)
        return try jsonToolResult(
            value: canvas,
            fallbackText: "Current ExcalidrawZ view is available."
        )
    }

    private func createFileTool(arguments: [String: MCPJSONValue]) async throws -> ExcalidrawMCPToolResult {
        if arguments["local_folder_id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            throw MCPJSONRPCError.invalidParams("create_file creates library files. Use create_local_file with local_folder_id for local folder files.")
        }
        let file = try await createFile(
            arguments["name"]?.stringValue,
            arguments["group_id"]?.stringValue
        )
        return try jsonToolResult(
            value: .object([
                "file": file,
                "message": .string("Created and opened a new ExcalidrawZ file. You can now call update_view.")
            ]),
            fallbackText: "Created and opened a new ExcalidrawZ file."
        )
    }

    private func createLocalFileTool(arguments: [String: MCPJSONValue]) async throws -> ExcalidrawMCPToolResult {
        guard let localFolderID = arguments["local_folder_id"]?.stringValue,
              !localFolderID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPJSONRPCError.invalidParams("create_local_file requires arguments.local_folder_id.")
        }
        let file = try await createLocalFile(arguments["name"]?.stringValue, localFolderID)
        return try jsonToolResult(
            value: .object([
                "file": file,
                "message": .string("Created and opened a new local Excalidraw file. You can now call update_view.")
            ]),
            fallbackText: "Created and opened a new local Excalidraw file."
        )
    }

    private func openFileTool(arguments: [String: MCPJSONValue]) async throws -> ExcalidrawMCPToolResult {
        guard let fileID = arguments["file_id"]?.stringValue,
              !fileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPJSONRPCError.invalidParams("open_file requires arguments.file_id.")
        }
        let file = try await openFile(fileID)
        return try jsonToolResult(
            value: .object([
                "file": file,
                "message": .string("Opened the ExcalidrawZ file. You can now call update_view.")
            ]),
            fallbackText: "Opened the ExcalidrawZ file."
        )
    }

    private func openLocalFileTool(arguments: [String: MCPJSONValue]) async throws -> ExcalidrawMCPToolResult {
        guard let fileURL = arguments["file_url"]?.stringValue,
              !fileURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPJSONRPCError.invalidParams("open_local_file requires arguments.file_url.")
        }
        let file = try await openLocalFile(fileURL)
        return try jsonToolResult(
            value: .object([
                "file": file,
                "message": .string("Opened the local Excalidraw file. You can now call update_view.")
            ]),
            fallbackText: "Opened the local Excalidraw file."
        )
    }

    private func setCanvasPreferencesTool(arguments: [String: MCPJSONValue]) async throws -> ExcalidrawMCPToolResult {
        let update = try canvasPreferencesUpdate(from: arguments)
        let result = try await setCanvasPreferences(update)
        return try jsonToolResult(
            value: result,
            fallbackText: "Canvas preferences updated."
        )
    }

    private func updateView(arguments: [String: MCPJSONValue]) async throws -> ExcalidrawMCPToolResult {
        guard let elementsString = arguments["elements"]?.stringValue else {
            throw MCPJSONRPCError.invalidParams("update_view requires arguments.elements.")
        }
        let clientUpdateID = arguments["client_update_id"]?.stringValue

        let inputData = Data(elementsString.utf8)
        guard inputData.count <= ExcalidrawMCPUpstreamContract.maxInputBytes else {
            return ExcalidrawMCPToolResult(
                text: "Elements input exceeds \(ExcalidrawMCPUpstreamContract.maxInputBytes) byte limit. Reduce the number of elements or use checkpoints to build incrementally.",
                isError: true
            )
        }

        let parsedElements: [MCPJSONValue]
        do {
            parsedElements = try MCPJSONValue.parseJSONArray(from: inputData)
        } catch {
            return ExcalidrawMCPToolResult(
                text: "Invalid JSON in elements. Ensure the value is a JSON array string with no comments or trailing commas.",
                isError: true
            )
        }

        let resolver = ExcalidrawMCPUpstreamElementResolver(
            loadCheckpointElements: readCheckpointElements
        )
        let resolved = try await resolver.resolve(parsedElements)
        let convertedElements = try await convertRawElements(resolved.elements)
        let published = try await publishDiagram(
            convertedElements,
            parsedElements.count,
            resolved.viewportUpdate,
            clientUpdateID
        )
        let appCheckpointText = appCheckpointSummary(for: published)

        return ExcalidrawMCPToolResult(
            text: """
            View updated in ExcalidrawZ.
            \(appCheckpointText)
            Next, call read_canvas_image once to inspect the rendered canvas before your final answer.
            If you need App checkpoint ids for current-file history or rollback, call get_current_file_checkpoints.
            """,
            structuredContent: structuredUpdateViewContent(
                published: published,
                clientUpdateID: clientUpdateID
            )
        )
    }

    private func canvasPreferencesUpdate(from arguments: [String: MCPJSONValue]) throws -> CanvasPreferencesSnapshot {
        var update = CanvasPreferencesSnapshot()

        if let rawValue = try stringArgument("theme", in: arguments) {
            guard let value = CanvasPreferencesState.Theme(rawValue: rawValue) else {
                throw MCPJSONRPCError.invalidParams("theme must be one of: light, dark.")
            }
            update.theme = value
        }
        if let value = try stringArgument("viewBackgroundColor", in: arguments) {
            update.viewBackgroundColor = try validatedCanvasColor(
                value,
                key: "viewBackgroundColor"
            )
        }
        if let value = try boolArgument("gridModeEnabled", in: arguments) {
            update.gridModeEnabled = value
        }
        if let value = try boolArgument("zenModeEnabled", in: arguments) {
            update.zenModeEnabled = value
        }
        if let value = try boolArgument("viewModeEnabled", in: arguments) {
            update.viewModeEnabled = value
        }
        if let value = try boolArgument("objectsSnapModeEnabled", in: arguments) {
            update.objectsSnapModeEnabled = value
        }
        if let value = try boolArgument("isMidpointSnappingEnabled", in: arguments) {
            update.isMidpointSnappingEnabled = value
        }
        if let rawValue = try stringArgument("bindingPreference", in: arguments) {
            guard let value = CanvasPreferencesState.BindingPreference(rawValue: rawValue) else {
                throw MCPJSONRPCError.invalidParams("bindingPreference must be one of: enabled, disabled.")
            }
            update.bindingPreference = value
        }
        if let rawValue = try stringArgument("preferredSelectionTool", in: arguments) {
            guard let value = CanvasPreferencesState.PreferredSelectionTool(rawValue: rawValue) else {
                throw MCPJSONRPCError.invalidParams("preferredSelectionTool must be one of: selection, lasso.")
            }
            update.preferredSelectionTool = value
        }
        if let rawValue = try stringArgument("boxSelectionMode", in: arguments) {
            guard let value = CanvasPreferencesState.BoxSelectionMode(rawValue: rawValue) else {
                throw MCPJSONRPCError.invalidParams("boxSelectionMode must be one of: contain, overlap.")
            }
            update.boxSelectionMode = value
        }
        if let value = try boolArgument("stats", in: arguments) {
            update.stats = value
        }

        return update
    }

    private func validatedCanvasColor(_ value: String, key: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"#
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else {
            throw MCPJSONRPCError.invalidParams(
                "\(key) must be a hex color like #ffffff, #fff, or #1e1e2eff."
            )
        }
        return trimmed
    }

    private func stringArgument(
        _ key: String,
        in arguments: [String: MCPJSONValue]
    ) throws -> String? {
        guard let value = arguments[key] else { return nil }
        guard let string = value.stringValue else {
            throw MCPJSONRPCError.invalidParams("\(key) must be a string.")
        }
        return string
    }

    private func boolArgument(
        _ key: String,
        in arguments: [String: MCPJSONValue]
    ) throws -> Bool? {
        guard let value = arguments[key] else { return nil }
        guard case .bool(let bool) = value else {
            throw MCPJSONRPCError.invalidParams("\(key) must be a boolean.")
        }
        return bool
    }

    private func appCheckpointSummary(for published: PublishedDiagram) -> String {
        let hasAppCheckpoint = published.appPreCheckpointID != nil || published.appPostCheckpointID != nil
        if !hasAppCheckpoint {
            return published.appCheckpointWarning ?? "App file-history checkpoints: unavailable for this target."
        }
        if let warning = published.appCheckpointWarning {
            return "App file-history checkpoints recorded. Call get_current_file_checkpoints to retrieve their ids. \(warning)"
        }
        return "App file-history checkpoints recorded. Call get_current_file_checkpoints to retrieve their ids."
    }

    private func structuredUpdateViewContent(
        published: PublishedDiagram,
        clientUpdateID: String?
    ) -> MCPJSONValue {
        var object: [String: MCPJSONValue] = [:]
        if let clientUpdateID {
            object["clientUpdateId"] = .string(clientUpdateID)
        }
        let hasAppCheckpoint = published.appPreCheckpointID != nil || published.appPostCheckpointID != nil
        let appCheckpointStatus = hasAppCheckpoint ? "recorded" : "unavailable"
        object["appFileHistoryCheckpointStatus"] = .string(appCheckpointStatus)
        if let warning = published.appCheckpointWarning {
            object["appCheckpointWarning"] = .string(warning)
        }
        return .object(object)
    }

    private func jsonToolResult(
        value: MCPJSONValue,
        fallbackText: String
    ) throws -> ExcalidrawMCPToolResult {
        let data = try value.mcpJSONData()
        let text = String(data: data, encoding: .utf8) ?? fallbackText
        return ExcalidrawMCPToolResult(
            text: text,
            structuredContent: value
        )
    }
}

private extension MCPJSONValue {
    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
}
