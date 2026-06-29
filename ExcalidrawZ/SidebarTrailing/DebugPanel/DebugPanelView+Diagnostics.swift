//
//  DebugPanelView+Diagnostics.swift
//  ExcalidrawZ
//
//  Created by Codex
//

#if DEBUG
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension DebugPanelView {
    @ViewBuilder
    var diagnosticsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Trigger a JavaScript exception inside the active Excalidraw WebView and publish it through the normal canvas error stream.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                debugActionButton("Throw JS Error Toast") {
                    runCameraAction("JS Error Toast Probe") {
                        try await requireCoordinator().debugThrowJavaScriptErrorForToastProbe()
                        return "Unexpected success: JavaScript did not throw."
                    }
                }
                .disabled(isRunning)

                debugCard("Pencil State", systemImage: "pencil.tip") {
                    Text("Compare Swift ToolState with excalidrawZHelper and Excalidraw appState.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    debugActionButton("Get Pencil State") {
                        runCameraAction("Pencil State") {
                            try await debugPencilState()
                        }
                    }
                    .disabled(isRunning)
                }

                debugCard("Viewport Capture", systemImage: "photo") {
                    Text("Export the active WebView viewport through excalidrawZHelper.exportViewportToBlob().")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    debugActionButton("Capture Viewport Image") {
                        runViewportCapture()
                    }
                    .disabled(isRunning)

                    if let viewportCaptureImage {
                        Image(platformImage: viewportCaptureImage)
                            .resizable()
                            .aspectRatio(
                                Self.aspectRatio(for: viewportCaptureImage),
                                contentMode: .fit
                            )
                            .frame(maxWidth: .infinity)
                            .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if !viewportCaptureSummary.isEmpty {
                        ScrollView {
                            Text(viewportCaptureSummary)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 80, maxHeight: 180)
                        .padding(8)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        } label: {
            Label("Diagnostics", systemImage: "exclamationmark.triangle")
                .font(.headline)
        }
    }

    private func debugPencilState() async throws -> String {
        let coordinator = try requireCoordinator()
        let swiftState = await MainActor.run {
            """
            Swift:
              inPenMode=\(toolState.inPenMode)
              pencilInteractionMode=\(String(describing: toolState.pencilInteractionMode)) (\(toolState.pencilInteractionMode.rawValue))
              activatedTool=\(String(describing: toolState.activatedTool))
              previousActivatedTool=\(String(describing: toolState.previousActivatedTool))
              isToolLocked=\(toolState.isToolLocked)
            """
        }
        let jsState = try await coordinator.webView.callAsyncJavaScript(
            """
            return JSON.stringify((() => {
              const helper = window.excalidrawZHelper;
              const appState = helper?._api?.getAppState?.();
              return {
                helper: helper ? {
                  inPencilMode: helper.inPencilMode,
                  pencilConnected: helper.pencilConnected,
                  pencilInterationMode: helper.pencilInterationMode,
                  pointerInputPolicy: helper.getPointerInputPolicy?.() ?? null,
                  lastToggleToolKey: helper.lastToggleToolKey
                } : null,
                appState: appState ? {
                  penMode: appState.penMode,
                  penDetected: appState.penDetected,
                  activeTool: appState.activeTool,
                  lastPointerDownWith: appState.lastPointerDownWith,
                  cursorButton: appState.cursorButton
                } : null,
                document: {
                  activeElement: document.activeElement?.tagName ?? null
                }
              };
            })(), null, 2);
            """,
            arguments: [:],
            contentWorld: .page
        )
        return """
        \(swiftState)

        JS:
        \((jsState as? String) ?? String(describing: jsState))
        """
    }

    private func runViewportCapture() {
        isRunning = true
        lastError = ""

        Task {
            do {
                let coordinator = try requireCoordinator()
                let result = try await coordinator.exportCurrentViewportToPNGData()
                guard let image = PlatformImage(data: result.data) else {
                    struct InvalidViewportImage: LocalizedError {
                        var errorDescription: String? { "Failed to decode viewport PNG data." }
                    }
                    throw InvalidViewportImage()
                }
                let webRuntimeInfo = try await viewportRuntimeInfo(from: coordinator)
                let summary = Self.describeViewportCapture(
                    result: result,
                    image: image,
                    webRuntimeInfo: webRuntimeInfo
                )

                await MainActor.run {
                    viewportCaptureImage = image
                    viewportCaptureSummary = summary
                    lastResult = "[Viewport Capture]\n\(summary)"
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    lastError = "[Viewport Capture]\n\(error.localizedDescription)"
                    isRunning = false
                }
            }
        }
    }

    private func viewportRuntimeInfo(
        from coordinator: ExcalidrawCanvasView.Coordinator
    ) async throws -> String {
        let result = try await coordinator.webView.callAsyncJavaScript(
            """
            return JSON.stringify((() => {
              const appState = window.excalidrawZHelper?._api?.getAppState?.();
              const container = document.querySelector(".excalidraw-container");
              const containerRect = container?.getBoundingClientRect?.();
              return {
                window: {
                  innerWidth: window.innerWidth,
                  innerHeight: window.innerHeight,
                  devicePixelRatio: window.devicePixelRatio
                },
                appState: {
                  width: appState?.width,
                  height: appState?.height,
                  scrollX: appState?.scrollX,
                  scrollY: appState?.scrollY,
                  zoom: appState?.zoom?.value
                },
                containerRect: containerRect ? {
                  x: containerRect.x,
                  y: containerRect.y,
                  width: containerRect.width,
                  height: containerRect.height
                } : null
              };
            })(), null, 2);
            """,
            arguments: [:],
            contentWorld: .page
        )
        return (result as? String) ?? String(describing: result)
    }

    private static func describeViewportCapture(
        result: ExcalidrawCore.ViewportImageExportResult,
        image: PlatformImage,
        webRuntimeInfo: String
    ) -> String {
        let pointSize = image.size
        let pixelSize = imagePixelSize(image)
        return """
        exportedWidth=\(format(result.width))
        exportedHeight=\(format(result.height))
        decodedPointSize=\(format(pointSize.width)) x \(format(pointSize.height))
        decodedPixelSize=\(format(pixelSize.width)) x \(format(pixelSize.height))
        actualScale=\(format(result.actualScale))
        scaleClamped=\(result.scaleClamped.map(String.init) ?? "nil")
        elementCount=\(result.elementCount.map(String.init) ?? "nil")
        fileCount=\(result.fileCount.map(String.init) ?? "nil")
        mimeType=\(result.mimeType ?? "nil")
        pngBytes=\(result.data.count)

        webRuntimeInfo:
        \(webRuntimeInfo)
        """
    }

    private static func imagePixelSize(_ image: PlatformImage) -> CGSize {
#if canImport(UIKit)
        if let cgImage = image.cgImage {
            return CGSize(
                width: CGFloat(cgImage.width),
                height: CGFloat(cgImage.height)
            )
        }
        return CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
#elseif canImport(AppKit)
        var proposedRect = CGRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            return CGSize(
                width: CGFloat(cgImage.width),
                height: CGFloat(cgImage.height)
            )
        }
        return image.size
#else
        return image.size
#endif
    }

    private static func aspectRatio(for image: PlatformImage) -> CGFloat? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        return size.width / size.height
    }

    private static func format(_ value: Double?) -> String {
        guard let value else { return "nil" }
        return format(value)
    }

    private static func format(_ value: CGFloat) -> String {
        format(Double(value))
    }

    private static func format(_ value: Double) -> String {
        guard value.isFinite else { return String(value) }
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}

#endif
