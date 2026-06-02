//
//  FileAccessStatusTool.swift
//  ExcalidrawZ
//
//  Created by Codex
//

import Foundation
import LLMCore

/// Exposes the file-access state to the model without exposing any file data.
/// This tool is only included in no-file-access rosters, so its schema doubles as
/// a hidden context note for the current request.
struct FileAccessStatusTool: Tool {
    struct FileAccessStatusContext: ToolContext {
        var hasActiveFile: Bool = false
        var isCurrentFileContextProtected: Bool = false
    }

    var name: String { "file_access_status" }

    var displayName: String { "File Access Status" }

    var description: String {
        """
        Current ExcalidrawZ file access status. Use this when the user asks \
        whether a file is open or why file content is unavailable. It reports \
        whether no file is open, or whether a file is open but unavailable to \
        AI. This tool never exposes file content. When it reports protected \
        content, create visual changes on the AI proposal canvas.
        """
    }

    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(properties: [:], required: []))
    }

    var approvalRequirement: ApprovalRequirement { .never }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        try AIChatToolExecutionGate.ensureAIEnabled()

        let status = try? context?.resolve(FileAccessStatusContext.self)
        guard status?.hasActiveFile == true else {
            return .text(AIFileAccessStatusMessage.noActiveFile)
        }
        guard status?.isCurrentFileContextProtected == true else {
            return .text(AIFileAccessStatusMessage.activeFileReadable)
        }

        return .text(AIFileAccessStatusMessage.protectedContentAccessDenied)
    }
}
