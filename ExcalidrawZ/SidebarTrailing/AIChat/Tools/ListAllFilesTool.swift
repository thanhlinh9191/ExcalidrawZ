//
//  ListAllFilesTool.swift
//  ExcalidrawZ
//
//  Lists all available drawing files in the user's library so the AI can
//  pick a target for follow-up tools (`query_file_history`,
//  `restore_file_history`, etc.). Scope: database `File` entities only —
//  iCloud-synced library, not local-folder URLs or temporary files.
//  Local files are URL-keyed so they need a separate tool (or a unified
//  surface with a `type` discriminator); we punt on that until the
//  AI's actually asking for it.
//

import Foundation
import CoreData
import LLMCore

struct ListAllFilesTool: Tool {
    var name: String { "list_all_files" }

    var displayName: String { String(localizable: .aiChatToolListAllFilesName) }

    var description: String {
        """
        List available drawing files in the user's library (iCloud-synced \
        files only; local-folder files are not included). \
        Each entry returns id, name, group, last-modified, and trash status. \
        Use this to pick a file id for `query_file_history` / \
        `restore_file_history`.
        """
    }

    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(
            properties: [
                "include_trashed": ParameterProperty(
                    type: "boolean",
                    description: "Include files in trash. Default: false."
                ),
                "limit": ParameterProperty(
                    type: "integer",
                    description: "Max items to return, capped server-side at 200. Default: 100."
                )
            ],
            required: []
        ))
    }

    /// Enumerating the user's whole file library is a privacy boundary —
    /// the AI shouldn't be able to silently survey what drawings exist.
    /// Always require explicit approval before listing.
    var approvalRequirement: ApprovalRequirement { .always }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        try AIChatToolExecutionGate.ensureAIEnabled()

        let params = parseInput(input)
        let limit = min(max(params.limit, 1), 200)

        let context = PersistenceController.shared.newTaskContext()
        let candidates: [FileEntryCandidate] = try await context.perform {
            let fetchRequest = NSFetchRequest<File>(entityName: "File")
            if !params.includeTrashed {
                fetchRequest.predicate = NSPredicate(format: "inTrash == NO OR inTrash == nil")
            }
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(key: "updatedAt", ascending: false),
                NSSortDescriptor(key: "createdAt", ascending: false),
            ]
            fetchRequest.fetchLimit = limit

            let files = try context.fetch(fetchRequest)
            return files.map { f in
                let groupPath = Self.groupPath(for: f.group)
                return FileEntryCandidate(
                    objectID: f.objectID,
                    id: f.id?.uuidString ?? "",
                    name: f.name ?? "Untitled",
                    groupID: f.group?.id?.uuidString,
                    group: f.group?.name,
                    groupPath: groupPath.isEmpty ? nil : groupPath,
                    groupType: f.group?.groupType.rawValue,
                    updatedAt: f.updatedAt.map(ISO8601DateFormatter.shared.string(from:)),
                    inTrash: f.inTrash
                )
            }
        }

        var entries: [FileEntry] = []
        var omittedUnreadableFiles = 0
        for candidate in candidates {
            let isReadable: Bool
            do {
                isReadable = try await LockedContentAIGuard.isAIReadable(fileObjectID: candidate.objectID)
            } catch {
                isReadable = false
            }
            if isReadable {
                entries.append(candidate.entry)
            } else {
                omittedUnreadableFiles += 1
            }
        }

        let payload = Output(
            files: entries,
            returned: entries.count,
            limit: limit,
            omittedUnreadableFiles: omittedUnreadableFiles,
            unreadableFilesPolicy: AIFileAccessStatusMessage.unreadableFilesOmitted
        )
        let data = try JSONEncoder().encode(payload)
        return .text(String(data: data, encoding: .utf8) ?? "[]")
    }

    // MARK: - Input

    private struct Params {
        var includeTrashed: Bool
        var limit: Int
    }

    private func parseInput(_ input: String) -> Params {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Params(includeTrashed: false, limit: 100)
        }
        return Params(
            includeTrashed: json["include_trashed"] as? Bool ?? false,
            limit: (json["limit"] as? Int) ?? 100
        )
    }

    // MARK: - Output

    private struct Output: Encodable {
        let files: [FileEntry]
        let returned: Int
        let limit: Int
        let omittedUnreadableFiles: Int
        let unreadableFilesPolicy: String

        enum CodingKeys: String, CodingKey {
            case files
            case returned
            case limit
            case omittedUnreadableFiles = "omitted_unreadable_files"
            case unreadableFilesPolicy = "unreadable_files_policy"
        }
    }

    private struct FileEntryCandidate {
        let objectID: NSManagedObjectID
        let id: String
        let name: String
        let groupID: String?
        let group: String?
        let groupPath: [String]?
        let groupType: String?
        let updatedAt: String?
        let inTrash: Bool

        var entry: FileEntry {
            FileEntry(
                id: id,
                name: name,
                groupID: groupID,
                group: group,
                groupPath: groupPath,
                groupType: groupType,
                updatedAt: updatedAt,
                inTrash: inTrash
            )
        }
    }

    private struct FileEntry: Encodable {
        let id: String
        let name: String
        let groupID: String?
        let group: String?
        let groupPath: [String]?
        let groupType: String?
        let updatedAt: String?
        let inTrash: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case groupID = "group_id"
            case group
            case groupPath = "group_path"
            case groupType = "group_type"
            case updatedAt
            case inTrash
        }
    }

    private static func groupPath(for group: Group?) -> [String] {
        var current = group
        var path: [String] = []
        while let group = current {
            path.insert(group.name ?? "Untitled", at: 0)
            current = group.parent
        }
        return path
    }
}

// Shared formatter so tools don't each spin up their own. ISO8601 is what
// LLMs handle most reliably across providers — drop locale/timezone
// ambiguity entirely.
extension ISO8601DateFormatter {
    static let shared: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
