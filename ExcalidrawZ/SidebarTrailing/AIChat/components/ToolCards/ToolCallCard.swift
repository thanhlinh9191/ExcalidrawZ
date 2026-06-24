//
//  ToolCallCard.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/4/26.
//

import SwiftUI
import LLMCore
import SFSafeSymbols

/// Header row for a tool call inside an assistant round. The tool name is
/// always visible; raw arguments fold open on tap. While the LLM is mid
/// tool-calling round, `isActive` shimmers the name to signal "in flight".
///
/// Visual chassis (chevron, tinted background, padding, expand toggle)
/// lives in `ToolEventCard`; this struct just plugs in the call-specific
/// icon, title, accent, and the JSON-arg foldout body. When the user
/// denied this call from the approval prompt we draw a small "Denied"
/// badge on the right of the header so the round reads as "AI tried X,
/// you stopped it" rather than just "AI tried X."
struct ToolCallCard: View {
    let call: ToolCall
    var isActive: Bool = false
    /// True when the matching `.tool` observation message is the
    /// "User denied execution of …" text our agent injects on
    /// `.deny(...)`. Decided upstream by `AssistantRoundView` since
    /// the deny status lives in a sibling tool message, not on the
    /// `ToolCall` itself.
    var isDenied: Bool = false

    var body: some View {
        let isStreamingArguments = isActive && !isDenied
        let style = ToolCallVisualStyle.style(for: call.name)
        ToolEventCard(
            icon: style.icon,
            // Resolve the snake_case `name` (LLM protocol payload) to the
            // tool's UI-friendly `displayName` via the sync cache. Falls
            // back to the raw name for tools the cache doesn't know
            // about (third-party / unregistered).
            title: ToolDisplayNameCache.displayName(for: call.name),
            accent: style.accent,
            isShimmering: isActive && !isDenied,
            isExpandable: !isStreamingArguments,
            showsLoadingIndicator: isStreamingArguments,
            trailing: {
                if isDenied {
                    deniedBadge
                }
            }
        ) { isExpanded in
            if isExpanded, !isStreamingArguments, !call.arguments.isEmpty {
                Text(call.arguments)
            }
        }
    }

    /// "Denied" pill drawn on the right of the header. Mirrors the
    /// approval prompt's destructive accent so the user can scan the
    /// round and tell at a glance which calls they blocked.
    @ViewBuilder
    private var deniedBadge: some View {
        HStack(spacing: 3) {
            Image(systemSymbol: .handRaisedFill)
            Text(localizable: .aiChatToolCallDeniedTitle)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.red)
    }
}

private struct ToolCallVisualStyle {
    let icon: SFSymbol
    let accent: Color

    static func style(for toolName: String) -> ToolCallVisualStyle {
        switch toolName {
            case "web_search":
                return ToolCallVisualStyle(icon: .magnifyingglass, accent: .blue)
            case "web_fetch":
                return ToolCallVisualStyle(icon: .globe, accent: .cyan)
            case "adjust_elements":
                return ToolCallVisualStyle(icon: .hammerFill, accent: .purple)
            case "navigate_canvas":
                return ToolCallVisualStyle(icon: .arrowUpLeftAndArrowDownRight, accent: .blue)
            case "set_canvas_preferences":
                return ToolCallVisualStyle(icon: .sliderHorizontal3, accent: .orange)
            case "get_current_file":
                return ToolCallVisualStyle(icon: .docText, accent: .indigo)
            case "read_file":
                return ToolCallVisualStyle(icon: .docText, accent: .indigo)
            case "read_canvas_image":
                return ToolCallVisualStyle(icon: .photo, accent: .teal)
            case "export":
                return ToolCallVisualStyle(icon: .docRichtext, accent: .teal)
            case "file_access_status":
                return ToolCallVisualStyle(icon: .eye, accent: .gray)
            case "rename_file":
                return ToolCallVisualStyle(icon: .pencil, accent: .orange)
            case "list_groups", "list_all_files", "list_local_folders", "list_local_files":
                return ToolCallVisualStyle(icon: .listBulletIndent, accent: .indigo)
            case "query_file_history":
                return ToolCallVisualStyle(icon: .clock, accent: .orange)
            case "restore_file_history":
                return ToolCallVisualStyle(icon: .clockArrowCirclepath, accent: .orange)
            case "list_libraries", "list_library_items", "query_library_item", "add_library_item_to_canvas":
                return ToolCallVisualStyle(icon: .book, accent: .mint)
            case "calculator":
                return ToolCallVisualStyle(icon: .xSquareroot, accent: .brown)
            case "datetime":
                return ToolCallVisualStyle(icon: .clock, accent: .brown)
            case "final_answer":
                return ToolCallVisualStyle(icon: .sparkles, accent: .accentColor)
            default:
                return ToolCallVisualStyle(icon: .hammerFill, accent: .purple)
        }
    }
}
