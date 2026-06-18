//
//  ExportTool.swift
//  ExcalidrawZ
//
//  Created by Codex
//

import Foundation
import LLMCore
import SwiftUI

/// Export the current canvas as an artifact. This is intentionally separate
/// from `read_canvas_image`: image reads are for model inspection, while export
/// returns a user/client-facing file.
struct ExportTool: Tool {
    struct ExportContext: ToolContext {
        var currentFileData: Data?
        var canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
        var readCanvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget?
        var currentFileID: UUID? = nil
        var isCurrentFileContextProtected: Bool = false
    }

    struct Input: Decodable {
        var kind: String
        var format: String?
        var editable: Bool?
        var withBackground: Bool?
        var colorScheme: String?
        var exportScale: Int?

        enum CodingKeys: String, CodingKey {
            case kind
            case format
            case editable
            case withBackground = "with_background"
            case colorScheme = "color_scheme"
            case exportScale = "export_scale"
        }
    }

    struct Output: Encodable {
        var message: String
        var kind: String
        var format: String?
        var fileName: String
        var mimeType: String
        var sizeBytes: Int
        var elementCount: Int
        var url: String
    }

    private enum ExportKind: String {
        case image
        case file
        case pdf
    }

    private enum ImageFormat: String {
        case png
        case svg
    }

    var name: String { "export" }

    var displayName: String { "Export" }

    var description: String {
        """
        Export the current Excalidraw canvas as an artifact. Set kind to \
        image, file, or pdf. Image export supports png/svg, optional editable \
        Excalidraw scene embedding, background, color scheme, and PNG scale. \
        File export returns a .excalidraw file. PDF export returns a lossless \
        application/pdf artifact. Use read_canvas_image for ordinary model \
        visual inspection; use export only when the user or MCP client needs a \
        file artifact.
        """
    }

    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(
            properties: [
                "kind": ParameterProperty(
                    type: "string",
                    description: "Export artifact kind.",
                    enum: ["image", "file", "pdf"]
                ),
                "format": ParameterProperty(
                    type: "string",
                    description: "Image format when kind is image. Defaults to png.",
                    enum: ["png", "svg"]
                ),
                "editable": ParameterProperty(
                    type: "boolean",
                    description: "For image export, embed the Excalidraw scene in PNG/SVG so it remains editable. Defaults to false."
                ),
                "with_background": ParameterProperty(
                    type: "boolean",
                    description: "Whether image/PDF export includes the canvas background. Defaults to true."
                ),
                "color_scheme": ParameterProperty(
                    type: "string",
                    description: "Export color scheme for image/PDF. Defaults to light.",
                    enum: ["light", "dark"]
                ),
                "export_scale": ParameterProperty(
                    type: "integer",
                    description: "PNG scale, 1, 2, or 3. Only applies to image png export. Defaults to 1."
                )
            ],
            required: ["kind"]
        ))
    }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        try AIChatToolExecutionGate.ensureAIEnabled()

        let params = try parseInput(input)
        let kind = try exportKind(from: params.kind)
        guard let context else {
            throw ToolError.executionFailed("Missing ExportContext")
        }
        let exportContext = try context.resolve(ExportContext.self)
        guard !exportContext.isCurrentFileContextProtected else {
            return LockedContentAIGuard.lockedToolResult
        }

        let canvasTarget = exportContext.readCanvasTarget ?? exportContext.canvasTarget
        guard try await LockedContentAIGuard.canToolAccess(
            canvasTarget: canvasTarget,
            currentFileID: exportContext.currentFileID
        ) else {
            return LockedContentAIGuard.lockedToolResult
        }

        let coordinator = try await ExcalidrawCoordinatorRegistry.shared.resolvedCoordinator(
            for: canvasTarget
        )
        guard let coordinator else {
            throw ToolError.executionFailed("Missing active Excalidraw coordinator")
        }

        var file = try await currentFile(
            context: exportContext,
            canvasTarget: canvasTarget
        )
        if file.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            file.name = await MainActor.run {
                coordinator.parent?.file?.name
            }
        }
        let visibleElementCount = file.elements.filter { !$0.isDeleted }.count

        switch kind {
            case .image:
                guard visibleElementCount > 0 else {
                    return .text("Canvas is empty — nothing to export.")
                }
                return try await exportImage(
                    params: params,
                    file: file,
                    elementCount: visibleElementCount,
                    coordinator: coordinator
                )
            case .file:
                return try exportFile(
                    file: file,
                    elementCount: visibleElementCount
                )
            case .pdf:
                guard visibleElementCount > 0 else {
                    return .text("Canvas is empty — nothing to export.")
                }
                return try await exportPDF(
                    params: params,
                    file: file,
                    elementCount: visibleElementCount,
                    coordinator: coordinator
                )
        }
    }

    private func exportImage(
        params: Input,
        file: ExcalidrawFile,
        elementCount: Int,
        coordinator: ExcalidrawCanvasView.Coordinator
    ) async throws -> ToolResult {
        let format = try imageFormat(from: params.format)
        let withBackground = params.withBackground ?? true
        let colorScheme = try colorScheme(from: params.colorScheme)
        let editable = params.editable ?? false
        let exportScale = try pngExportScale(from: params.exportScale)
        let data: Data
        let fileName: String
        let mimeType: String

        switch format {
            case .png:
                data = try await coordinator.exportElementsToPNGData(
                    elements: file.elements,
                    files: file.files,
                    embedScene: editable,
                    withBackground: withBackground,
                    colorScheme: colorScheme,
                    exportScale: exportScale
                )
                fileName = artifactFileName(
                    baseName: file.name,
                    fileExtension: editable ? "excalidraw.png" : "png"
                )
                mimeType = "image/png"
            case .svg:
                data = try await coordinator.exportElementsToSVGData(
                    elements: file.elements,
                    files: file.files,
                    embedScene: editable,
                    withBackground: withBackground,
                    colorScheme: colorScheme
                )
                fileName = artifactFileName(
                    baseName: file.name,
                    fileExtension: editable ? "excalidraw.svg" : "svg"
                )
                mimeType = "image/svg+xml"
        }

        let url = try writeArtifact(data: data, fileName: fileName)
        return try outputResult(
            kind: "image",
            format: format.rawValue,
            fileName: fileName,
            mimeType: mimeType,
            data: data,
            elementCount: elementCount,
            url: url
        )
    }

    private func exportFile(
        file: ExcalidrawFile,
        elementCount: Int
    ) throws -> ToolResult {
        guard let data = file.content ?? (try? JSONEncoder().encode(file)) else {
            throw ToolError.executionFailed("The file has no data.")
        }
        let fileName = artifactFileName(
            baseName: file.name,
            fileExtension: "excalidraw"
        )
        let url = try writeArtifact(data: data, fileName: fileName)
        return try outputResult(
            kind: "file",
            format: "excalidraw",
            fileName: fileName,
            mimeType: "application/vnd.excalidraw+json",
            data: data,
            elementCount: elementCount,
            url: url
        )
    }

    private func exportPDF(
        params: Input,
        file: ExcalidrawFile,
        elementCount: Int,
        coordinator: ExcalidrawCanvasView.Coordinator
    ) async throws -> ToolResult {
        let data = try await coordinator.exportElementsToPDFData(
            elements: file.elements,
            files: file.files,
            withBackground: params.withBackground ?? true,
            colorScheme: try colorScheme(from: params.colorScheme)
        )
        let fileName = artifactFileName(
            baseName: file.name,
            fileExtension: "pdf"
        )
        let url = try writeArtifact(data: data, fileName: fileName)
        return try outputResult(
            kind: "pdf",
            format: "pdf",
            fileName: fileName,
            mimeType: "application/pdf",
            data: data,
            elementCount: elementCount,
            url: url
        )
    }

    private func currentFile(
        context: ExportContext,
        canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    ) async throws -> ExcalidrawFile {
        guard let data = try await CurrentExcalidrawDataResolver.resolveLiveSnapshot(
            canvasTarget: canvasTarget,
            baseContent: context.currentFileData,
            currentFileID: context.currentFileID
        ) else {
            throw ToolError.executionFailed("Missing current file data.")
        }
        return try ExcalidrawFile(
            data: data,
            id: context.currentFileID?.uuidString
        )
    }

    private func outputResult(
        kind: String,
        format: String?,
        fileName: String,
        mimeType: String,
        data: Data,
        elementCount: Int,
        url: URL
    ) throws -> ToolResult {
        let output = Output(
            message: "Canvas exported.",
            kind: kind,
            format: format,
            fileName: fileName,
            mimeType: mimeType,
            sizeBytes: data.count,
            elementCount: elementCount,
            url: url.absoluteString
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(output)
        return .text(String(data: encoded, encoding: .utf8) ?? "Canvas exported: \(url.absoluteString)")
    }

    private func parseInput(_ input: String) throws -> Input {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8) else {
            throw ToolError.invalidInput("Expected export parameters JSON object.")
        }
        do {
            return try JSONDecoder().decode(Input.self, from: data)
        } catch {
            throw ToolError.invalidInput("Expected export parameters JSON object: \(error.localizedDescription)")
        }
    }

    private func exportKind(from rawValue: String) throws -> ExportKind {
        guard let kind = ExportKind(rawValue: rawValue.lowercased()) else {
            throw ToolError.invalidInput("kind must be one of: image, file, pdf.")
        }
        return kind
    }

    private func imageFormat(from rawValue: String?) throws -> ImageFormat {
        guard let rawValue else { return .png }
        guard let format = ImageFormat(rawValue: rawValue.lowercased()) else {
            throw ToolError.invalidInput("format must be one of: png, svg.")
        }
        return format
    }

    private func colorScheme(from rawValue: String?) throws -> ColorScheme {
        switch rawValue?.lowercased() {
            case nil, "light":
                return .light
            case "dark":
                return .dark
            default:
                throw ToolError.invalidInput("color_scheme must be one of: light, dark.")
        }
    }

    private func pngExportScale(from value: Int?) throws -> Int {
        let scale = value ?? 1
        guard (1...3).contains(scale) else {
            throw ToolError.invalidInput("export_scale must be 1, 2, or 3.")
        }
        return scale
    }

    private func artifactFileName(
        baseName rawBaseName: String?,
        fileExtension: String
    ) -> String {
        let trimmedName = rawBaseName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let baseName = sanitizedFileBaseName(
            trimmedName.isEmpty ? "ExcalidrawZ Canvas" : trimmedName
        )
        return "\(baseName).\(fileExtension)"
    }

    private func sanitizedFileBaseName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:")
        var baseName = name
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
        let knownSuffixes = [
            ".excalidraw.png",
            ".excalidraw.svg",
            ".excalidraw",
            ".png",
            ".svg",
            ".pdf"
        ]
        for suffix in knownSuffixes where baseName.lowercased().hasSuffix(suffix) {
            baseName.removeLast(suffix.count)
            break
        }
        return baseName.isEmpty ? "ExcalidrawZ Canvas" : baseName
    }

    private func writeArtifact(data: Data, fileName: String) throws -> URL {
        let directory = try getTempDirectory()
        let url = directory.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
        try data.write(to: url, options: .atomic)
        return url
    }
}
