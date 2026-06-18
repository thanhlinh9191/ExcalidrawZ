//
//  FileCheckpointRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import SwiftUI
import Logging
import ChocofordUI
import SFSafeSymbols

private let fileCheckpointRowLogger = Logger(label: "FileCheckpointRowView")

struct FileCheckpointRowView<Checkpoint: FileCheckpointRepresentable>: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    
    @Environment(\.colorScheme) var colorScheme
    
    @Environment(\.managedObjectContext) var managedObjectContext
    @EnvironmentObject var fileState: FileState
    
    var checkpoint: Checkpoint
    
    @State private var file: ExcalidrawFile?
    @State private var fileSize: Int = 0
    
    var body: some View {
        content()
            .task(id: checkpointMetadataLoadID) {
                do {
                    let content = try await loadContent(for: checkpoint)
                    let file = try? JSONDecoder().decode(ExcalidrawFile.self, from: content)
                    await MainActor.run {
                        self.fileSize = content.count
                        self.file = file
                    }
                } catch {
                    fileCheckpointRowLogger.warning("Failed to load checkpoint metadata: \(error)")
                }
            }
    }

    private var checkpointMetadataLoadID: String {
        "\(checkpoint.objectID.uriRepresentation().absoluteString)-\(checkpoint.updatedAt?.timeIntervalSinceReferenceDate ?? 0)"
    }
    
    @ViewBuilder
    private func content() -> some View {
#if os(iOS)
        NavigationLink {
            FileCheckpointDetailView(checkpoint: checkpoint)
        } label: {
            label()
        }
#elseif os(macOS)
        Popover(arrowEdge: .trailing) {
            FileCheckpointDetailView(checkpoint: checkpoint)
        } label: {
            label()
        }
        .buttonStyle(.fileCheckpointRow)
        
#endif
    }
    
    @ViewBuilder
    private func label() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text((checkpoint.filename ?? ""))
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                // AI-source badge (user-source rows show no badge — they're
                // the default and a "User" pill on every row would just be
                // visual noise).
                sourceBadge
            }
            
            // Git-style description, only when present. AI fills this on
            // `.aiPost` rows; user rows are nil unless the user explicitly
            // edits one (TBD UI). Allow up to 2 lines so the AI's summary
            // doesn't get clipped to a single line.
            if let description = checkpoint.historyDescription, !description.isEmpty {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    if let file {
                        let elementCount = file.elements.filter { !$0.isDeleted }.count
                        if #available(macOS 13.0, iOS 16.0, *) {
                            Text(.localizable(.checkpointsElementsDescription(elementCount)))
                        } else {
                            Text(elementCount.formatted())
                        }
                    }
                    Text(" · ")
                    
                    Text("\(fileSize.formatted(.byteCount(style: .file)))")
                    
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                
                Text(checkpoint.updatedAt?.formatted() ?? "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    @MainActor
    private func loadContent(for checkpoint: Checkpoint) async throws -> Data {
        if let fileCheckpoint = checkpoint as? FileCheckpoint {
            return try await fileCheckpoint.loadContent()
        }

        guard let content = checkpoint.content else {
            throw EmptyCheckpointContentError()
        }
        return content
    }
    
    /// Capsule badge for AI-authored result checkpoints. `.aiPre` is
    /// visible in history as the revert anchor, but should read like a
    /// normal checkpoint rather than an AI-produced result.
    @ViewBuilder
    private var sourceBadge: some View {
        switch checkpoint.checkpointSource {
        case .aiPost:
            BadgeLabel(
                text: "AI",
                icon: .sparkles,
                tint: .accentColor
            )
        case .mcpPost:
            BadgeLabel(
                text: "MCP",
                icon: .sparkles,
                tint: .accentColor
            )
        case .restorePost:
            BadgeLabel(
                text: "Restore",
                icon: .arrowCounterclockwise,
                tint: .accentColor
            )
        case .user, .aiPre, .mcpPre:
            EmptyView()
        }
    }
}

private struct EmptyCheckpointContentError: Error {}


/// Small capsule used by `FileCheckpointRowView` to surface AI vs user
/// source. Pulled into its own view so the row's body stays flat and so
/// the styling stays consistent if more sources get added later.
private struct BadgeLabel: View {
    let text: String
    let icon: SFSymbol
    let tint: Color
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemSymbol: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(tint)
        .background(
            Capsule()
                .fill(tint.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.3), lineWidth: 0.5)
        )
    }
}

private struct FileCheckpointRowButtonStyle: PrimitiveButtonStyle {
    @State private var isHovered = false
    
    private var cornerRadius: CGFloat {
        if #available(macOS 26.0, iOS 26.0, *) {
            18
        } else {
            8
        }
    }
    
    func makeBody(configuration: Configuration) -> some View {
        PrimitiveButtonWrapper {
            configuration.trigger()
        } content: { isPressed in
            HStack(spacing: 0) {
                configuration.label
                Spacer(minLength: 0)
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.16)) {
                    isHovered = hovering
                }
            }
            .background {
                rowBackground(isPressed: isPressed)
            }
            .animation(.easeInOut(duration: 0.16), value: isHovered)
        }
    }
    
    @ViewBuilder
    private func rowBackground(isPressed: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        
        if #available(macOS 26.0, iOS 26.0, *) {
            if isHovered || isPressed {
                shape
                    .fill(.clear)
                    .glassEffect(
                        Glass.regular
                            .tint(Color.primary.opacity(isPressed ? 0.10 : 0.06))
                            .interactive(),
                        in: shape
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        } else {
            shape
                .fill(Color.gray.opacity(isPressed ? 0.28 : 0.18))
                .opacity(isHovered || isPressed ? 1 : 0)
        }
    }
}

private extension PrimitiveButtonStyle where Self == FileCheckpointRowButtonStyle {
    static var fileCheckpointRow: FileCheckpointRowButtonStyle {
        FileCheckpointRowButtonStyle()
    }
}


#if DEBUG
#Preview {
    FileCheckpointRowView(checkpoint: FileCheckpoint.preview)
        .environmentObject(FileState())
}
#endif
