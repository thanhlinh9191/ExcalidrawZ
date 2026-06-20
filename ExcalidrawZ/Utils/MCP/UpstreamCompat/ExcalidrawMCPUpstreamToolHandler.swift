//
//  ExcalidrawMCPUpstreamToolHandler.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/16.
//

import Foundation

struct ExcalidrawMCPUpstreamToolHandler {
    struct PublishedDiagram: Sendable {
        let checkpointID: String
    }

    typealias ElementConverter = @Sendable ([MCPJSONValue]) async throws -> [MCPJSONValue]
    typealias PublishDiagram = @Sendable (
        _ elements: [MCPJSONValue],
        _ sourceElementCount: Int,
        _ viewportUpdate: ExcalidrawMCPUpstreamViewportUpdate?
    ) async throws -> PublishedDiagram
    typealias SaveCheckpoint = @Sendable (_ id: String, _ data: MCPJSONValue) async throws -> Void
    typealias ReadCheckpointData = @Sendable (_ id: String) async -> MCPJSONValue?
    typealias ReadCheckpointElements = @Sendable (_ id: String) async -> [MCPJSONValue]?

    var convertRawElements: ElementConverter
    var publishDiagram: PublishDiagram
    var saveCheckpointData: SaveCheckpoint
    var readCheckpointData: ReadCheckpointData
    var readCheckpointElements: ReadCheckpointElements

    func callTool(
        name: String,
        arguments: [String: MCPJSONValue]
    ) async throws -> ExcalidrawMCPToolResult {
        switch name {
            case ExcalidrawMCPUpstreamContract.ToolName.readMe:
                return ExcalidrawMCPToolResult(text: ExcalidrawMCPUpstreamRecall.cheatSheet)
            case ExcalidrawMCPUpstreamContract.ToolName.createView:
                return try await createView(arguments: arguments)
            case ExcalidrawMCPUpstreamContract.ToolName.saveCheckpoint:
                return try await saveCheckpoint(arguments: arguments)
            case ExcalidrawMCPUpstreamContract.ToolName.readCheckpoint:
                return try await readCheckpoint(arguments: arguments)
            default:
                throw MCPJSONRPCError.invalidParams("Unknown tool: \(name)")
        }
    }

    private func createView(
        arguments: [String: MCPJSONValue]
    ) async throws -> ExcalidrawMCPToolResult {
        guard let elementsString = arguments["elements"]?.stringValue else {
            throw MCPJSONRPCError.invalidParams("create_view requires arguments.elements.")
        }

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
            resolved.viewportUpdate
        )

        return ExcalidrawMCPToolResult(
            text: """
            Diagram received by ExcalidrawZ and applied to a file. Checkpoint id: "\(published.checkpointID)".
            If the user asks to revise this diagram, call create_view again with a restoreCheckpoint pseudo-element using that id.
            """,
            structuredContent: .object([
                "checkpointId": .string(published.checkpointID)
            ])
        )
    }

    private func saveCheckpoint(
        arguments: [String: MCPJSONValue]
    ) async throws -> ExcalidrawMCPToolResult {
        guard let id = arguments["id"]?.stringValue else {
            throw MCPJSONRPCError.invalidParams("save_checkpoint requires arguments.id.")
        }
        guard let dataString = arguments["data"]?.stringValue else {
            throw MCPJSONRPCError.invalidParams("save_checkpoint requires arguments.data.")
        }
        guard Data(dataString.utf8).count <= ExcalidrawMCPUpstreamContract.maxInputBytes else {
            return ExcalidrawMCPToolResult(
                text: "Checkpoint data exceeds \(ExcalidrawMCPUpstreamContract.maxInputBytes) byte limit.",
                isError: true
            )
        }

        do {
            let data = try MCPJSONValue.parse(from: Data(dataString.utf8))
            try await saveCheckpointData(id, data)
            return ExcalidrawMCPToolResult(text: "ok")
        } catch {
            return ExcalidrawMCPToolResult(
                text: "save failed: \(error.localizedDescription)",
                isError: true
            )
        }
    }

    private func readCheckpoint(
        arguments: [String: MCPJSONValue]
    ) async throws -> ExcalidrawMCPToolResult {
        guard let id = arguments["id"]?.stringValue else {
            throw MCPJSONRPCError.invalidParams("read_checkpoint requires arguments.id.")
        }
        guard let data = await readCheckpointData(id) else {
            return ExcalidrawMCPToolResult(text: "")
        }

        let jsonData = try data.mcpJSONData()
        let json = String(data: jsonData, encoding: .utf8) ?? "[]"
        return ExcalidrawMCPToolResult(text: json)
    }
}
