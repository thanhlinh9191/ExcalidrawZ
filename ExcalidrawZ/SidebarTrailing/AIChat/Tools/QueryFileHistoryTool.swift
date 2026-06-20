//
//  QueryFileHistoryTool.swift
//  ExcalidrawZ
//
//  Lists checkpoint history for a given file. Each entry surfaces the
//  AI-history fields (`source`, `historyDescription`) so the AI / UI can
//  present "revert to this point" affordances and understand which
//  checkpoints were AI-generated vs user edits.
//
//  Scope: database `File` entities and URL-keyed `LocalFileCheckpoint`
//  entities. MCP uses the same surface for both so update_view's checkpoint
//  status can be inspected consistently.
//

import Foundation
import CoreData
import LLMCore

struct QueryFileHistoryTool: Tool {
    var name: String { "query_file_history" }

    var displayName: String { String(localizable: .aiChatToolQueryFileHistoryName) }

    var description: String {
        """
        List the checkpoint history of a drawing file. Each entry returns \
        checkpoint id, source ("user" / "ai_pre" / "ai_post"), an optional \
        description, and the timestamp. For library files, use this to find a \
        checkpoint id for `restore_file_history`. Get library file ids from \
        `list_all_files`.
        """
    }

    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(
            properties: [
                "file_id": ParameterProperty(
                    type: "string",
                    description: "UUID of a library file (from `list_all_files`)."
                ),
                "limit": ParameterProperty(
                    type: "integer",
                    description: "Max checkpoints to return, capped at 200. Default: 50, ordered most-recent first."
                ),
                "ai_only": ParameterProperty(
                    type: "boolean",
                    description: "If true, only return automated checkpoints (`ai_pre` / `ai_post` / `mcp_pre` / `mcp_post` / `restore_post`). Default: false."
                )
            ],
            required: ["file_id"]
        ))
    }

    /// Reading a file's checkpoint history exposes when it was edited
    /// and which edits came from prior automated rounds — both pieces of user
    /// data that the user should explicitly authorize before the AI
    /// pulls them into the chat.
    var approvalRequirement: ApprovalRequirement { .always }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        try AIChatToolExecutionGate.ensureAIEnabled()

        let params = try parseInput(input)
        let limit = min(max(params.limit, 1), 200)

        let history: CheckpointList
        if let fileID = params.fileID {
            history = try await checkpointList(
                fileID: fileID,
                limit: limit,
                aiOnly: params.aiOnly
            )
        } else if let fileURL = params.fileURL {
            history = try await checkpointList(
                fileURL: fileURL,
                limit: limit,
                aiOnly: params.aiOnly
            )
        } else {
            throw ToolError.invalidInput("Expected `file_id` or `file_url`.")
        }

        var entries: [CheckpointEntry] = []
        for checkpoint in history.checkpoints {
            let contentSize = await contentSize(for: checkpoint)
            entries.append(
                CheckpointEntry(
                    id: checkpoint.id,
                    source: checkpoint.source,
                    description: checkpoint.description,
                    updatedAt: checkpoint.updatedAt,
                    contentSize: contentSize
                )
            )
        }

        let payload = Output(
            fileID: params.fileID,
            fileURL: params.fileURL?.absoluteString,
            fileKind: history.fileKind,
            fileName: history.fileName,
            history: entries,
            returned: entries.count,
            limit: limit
        )

        let data = try JSONEncoder().encode(payload)
        return .text(String(data: data, encoding: .utf8) ?? "{}")
    }

    private func checkpointList(
        fileID: UUID,
        limit: Int,
        aiOnly: Bool
    ) async throws -> CheckpointList {
        let ctx = PersistenceController.shared.newTaskContext()
        let fileObjectID: NSManagedObjectID = try await ctx.perform {
            let fileFetch = NSFetchRequest<File>(entityName: "File")
            fileFetch.predicate = NSPredicate(format: "id == %@", fileID as CVarArg)
            fileFetch.fetchLimit = 1
            guard let file = try ctx.fetch(fileFetch).first else {
                throw ToolError.executionFailed("File not found: \(fileID)")
            }
            return file.objectID
        }
        guard try await LockedContentAIGuard.canToolAccess(fileObjectID: fileObjectID) else {
            throw ToolError.executionFailed(AIFileAccessStatusMessage.protectedContentAccessDenied)
        }

        let checkpointList: CheckpointList = try await ctx.perform {
            guard let file = try ctx.existingObject(with: fileObjectID) as? File else {
                throw ToolError.executionFailed("File not found: \(fileID)")
            }

            // Fetch checkpoints.
            let cpFetch = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
            if aiOnly {
                let automatedSources = [
                    FileCheckpointSource.aiPre.rawValue,
                    FileCheckpointSource.aiPost.rawValue,
                    FileCheckpointSource.mcpPre.rawValue,
                    FileCheckpointSource.mcpPost.rawValue,
                    FileCheckpointSource.restorePost.rawValue
                ]
                cpFetch.predicate = NSPredicate(
                    format: "file == %@ AND source IN %@",
                    file,
                    automatedSources
                )
            } else {
                cpFetch.predicate = NSPredicate(format: "file == %@", file)
            }
            cpFetch.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            cpFetch.fetchLimit = limit

            let candidates = try ctx.fetch(cpFetch).map { cp in
                CheckpointCandidate(
                    objectID: cp.objectID,
                    storage: .library,
                    id: cp.id?.uuidString ?? "",
                    source: cp.checkpointSource.rawValue,
                    description: cp.historyDescription,
                    updatedAt: cp.updatedAt.map(ISO8601DateFormatter.shared.string(from:)),
                    fallbackContentSize: cp.content?.count ?? 0
                )
            }

            return CheckpointList(
                fileKind: "libraryFile",
                fileName: file.name ?? "Untitled",
                checkpoints: candidates
            )
        }
        return checkpointList
    }

    private func checkpointList(
        fileURL: URL,
        limit: Int,
        aiOnly: Bool
    ) async throws -> CheckpointList {
        let standardizedURL = fileURL.standardizedFileURL
        let ctx = PersistenceController.shared.newTaskContext()
        return try await ctx.perform {
            let cpFetch = NSFetchRequest<LocalFileCheckpoint>(entityName: "LocalFileCheckpoint")
            if aiOnly {
                let automatedSources = [
                    FileCheckpointSource.aiPre.rawValue,
                    FileCheckpointSource.aiPost.rawValue,
                    FileCheckpointSource.mcpPre.rawValue,
                    FileCheckpointSource.mcpPost.rawValue,
                    FileCheckpointSource.restorePost.rawValue
                ]
                cpFetch.predicate = NSPredicate(
                    format: "url == %@ AND source IN %@",
                    standardizedURL as CVarArg,
                    automatedSources
                )
            } else {
                cpFetch.predicate = NSPredicate(
                    format: "url == %@",
                    standardizedURL as CVarArg
                )
            }
            cpFetch.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            cpFetch.fetchLimit = limit

            let candidates = try ctx.fetch(cpFetch).map { cp in
                CheckpointCandidate(
                    objectID: cp.objectID,
                    storage: .local,
                    id: cp.id?.uuidString ?? "",
                    source: FileCheckpointSource(rawValue: cp.source ?? "")?.rawValue
                        ?? cp.source
                        ?? FileCheckpointSource.user.rawValue,
                    description: cp.historyDescription,
                    updatedAt: cp.updatedAt.map(ISO8601DateFormatter.shared.string(from:)),
                    fallbackContentSize: cp.content?.count ?? 0
                )
            }

            return CheckpointList(
                fileKind: "localFile",
                fileName: standardizedURL.deletingPathExtension().lastPathComponent,
                checkpoints: candidates
            )
        }
    }

    // MARK: - Input

    private struct Params {
        var fileID: UUID?
        var fileURL: URL?
        var limit: Int
        var aiOnly: Bool
    }

    private func parseInput(_ input: String) throws -> Params {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolError.invalidInput("Expected JSON object with `file_id` or `file_url`.")
        }
        let fileID: UUID? = {
            guard let value = json["file_id"] as? String,
                  !value.isEmpty else {
                return nil
            }
            return UUID(uuidString: value)
        }()
        if let value = json["file_id"] as? String,
           !value.isEmpty,
           fileID == nil {
            throw ToolError.invalidInput("file_id must be a UUID.")
        }
        let fileURL = try localFileURL(from: json["file_url"] as? String)
        guard fileID != nil || fileURL != nil else {
            throw ToolError.invalidInput("Missing required parameter: file_id or file_url.")
        }
        guard fileID == nil || fileURL == nil else {
            throw ToolError.invalidInput("Use either file_id or file_url, not both.")
        }
        return Params(
            fileID: fileID,
            fileURL: fileURL,
            limit: (json["limit"] as? Int) ?? 50,
            aiOnly: (json["ai_only"] as? Bool) ?? false
        )
    }

    private func localFileURL(from value: String?) throws -> URL? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.isFileURL {
            return url.standardizedFileURL
        }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).standardizedFileURL
        }
        throw ToolError.invalidInput("file_url must be a file URL or absolute path.")
    }

    // MARK: - Output

    private struct Output: Encodable {
        let fileID: UUID?
        let fileURL: String?
        let fileKind: String
        let fileName: String
        let history: [CheckpointEntry]
        let returned: Int
        let limit: Int

        enum CodingKeys: String, CodingKey {
            case fileID = "file_id"
            case fileURL = "file_url"
            case fileKind = "file_kind"
            case fileName = "file_name"
            case history
            case returned
            case limit
        }
    }

    private struct CheckpointList {
        let fileKind: String
        let fileName: String
        let checkpoints: [CheckpointCandidate]
    }

    private enum CheckpointStorage: Equatable {
        case library
        case local
    }

    private struct CheckpointCandidate {
        let objectID: NSManagedObjectID
        let storage: CheckpointStorage
        let id: String
        let source: String
        let description: String?
        let updatedAt: String?
        let fallbackContentSize: Int
    }

    private struct CheckpointEntry: Encodable {
        let id: String
        let source: String
        let description: String?
        let updatedAt: String?
        let contentSize: Int

        enum CodingKeys: String, CodingKey {
            case id
            case source
            case description
            case updatedAt = "updated_at"
            case contentSize = "content_size"
        }
    }

    private func contentSize(for checkpoint: CheckpointCandidate) async -> Int {
        guard checkpoint.storage == .library else {
            return checkpoint.fallbackContentSize
        }
        do {
            let content = try await PersistenceController.shared.checkpointRepository
                .loadCheckpointContent(checkpointObjectID: checkpoint.objectID)
            return content.count
        } catch {
            return checkpoint.fallbackContentSize
        }
    }
}
