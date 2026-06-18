//
//  ExcalidrawMCPDiagramSessionStore.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/14.
//

import Foundation

struct ExcalidrawMCPDiagramSession: Identifiable, Codable, Sendable {
    let id: String
    let checkpointID: String
    let createdAt: Date
    let updatedAt: Date
    let elements: [MCPJSONValue]
    let sourceElementCount: Int
    let viewportUpdate: ExcalidrawMCPUpstreamViewportUpdate?
}

struct ExcalidrawMCPCheckpoint: Codable, Sendable {
    let id: String
    let createdAt: Date
    let data: MCPJSONValue

    var elements: [MCPJSONValue] {
        ExcalidrawMCPElementSanitizer.checkpointElements(from: data) ?? []
    }

    var dataValue: MCPJSONValue {
        data
    }
}

actor ExcalidrawMCPDiagramSessionStore {
    typealias UpdateHandler = @Sendable (ExcalidrawMCPDiagramSession) async throws -> Void

    private var checkpoints: [String: ExcalidrawMCPCheckpoint] = [:]
    private var currentSession: ExcalidrawMCPDiagramSession?
    private var updateHandler: UpdateHandler?

    func setUpdateHandler(_ handler: UpdateHandler?) {
        updateHandler = handler
    }

    func latestSession() -> ExcalidrawMCPDiagramSession? {
        currentSession
    }

    func checkpoint(id: String) -> ExcalidrawMCPCheckpoint? {
        checkpoints[id]
    }

    @discardableResult
    func saveCheckpoint(
        id: String = makeCheckpointID(),
        elements: [MCPJSONValue]
    ) throws -> ExcalidrawMCPCheckpoint {
        let sanitizedElements = try ExcalidrawMCPElementSanitizer.sanitizeElements(elements)
        let checkpoint = ExcalidrawMCPCheckpoint(
            id: id,
            createdAt: Date(),
            data: .object([
                "elements": .array(sanitizedElements)
            ])
        )
        checkpoints[checkpoint.id] = checkpoint
        return checkpoint
    }

    @discardableResult
    func saveCheckpoint(
        id: String,
        data: MCPJSONValue
    ) throws -> ExcalidrawMCPCheckpoint {
        let checkpoint = ExcalidrawMCPCheckpoint(
            id: id,
            createdAt: Date(),
            data: data
        )
        checkpoints[checkpoint.id] = checkpoint
        return checkpoint
    }

    @discardableResult
    func publishSession(
        elements: [MCPJSONValue],
        sourceElementCount: Int,
        viewportUpdate: ExcalidrawMCPUpstreamViewportUpdate? = nil,
        notifiesUpdateHandler: Bool = true
    ) async throws -> ExcalidrawMCPDiagramSession {
        let sanitizedElements = try ExcalidrawMCPElementSanitizer.sanitizeElements(elements)
        let checkpoint = try saveCheckpoint(elements: sanitizedElements)
        let now = Date()
        let session = ExcalidrawMCPDiagramSession(
            id: UUID().uuidString,
            checkpointID: checkpoint.id,
            createdAt: now,
            updatedAt: now,
            elements: sanitizedElements,
            sourceElementCount: sourceElementCount,
            viewportUpdate: viewportUpdate
        )
        if notifiesUpdateHandler {
            try await updateHandler?(session)
        }
        currentSession = session
        return session
    }

    private static func makeCheckpointID() -> String {
        UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
            .prefix(18)
            .description
    }

}
