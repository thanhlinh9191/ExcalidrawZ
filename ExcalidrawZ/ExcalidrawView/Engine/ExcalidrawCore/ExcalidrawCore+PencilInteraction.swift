//
//  ExcalidrawCore+PencilInteraction.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 12/16/24.
//


#if os(iOS)
import UIKit

extension ExcalidrawCore: UIPencilInteractionDelegate {
    private var pencilToolToggleDebounceInterval: TimeInterval { 0.35 }
    
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        Task { @MainActor in
            await handlePencilToolToggle()
        }
    }
    
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
    }
    
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
    }

    @MainActor
    private func handlePencilToolToggle() async {
        guard shouldHandlePencilToolToggle() else { return }
        defer { isHandlingPencilToolToggle = false }

        guard let toolState = self.parent?.toolState,
              toolState.excalidrawWebCoordinator === self else { return }

        do {
            if !toolState.inPenMode {
                try await toolState.togglePenMode(enabled: true, pencilConnected: true)
                try await toolState.toggleTool(.freedraw)
                return
            }

            if toolState.activatedTool == .eraser {
                try await toolState.toggleTool(pencilReturnTool(from: toolState))
            } else {
                try await toolState.toggleTool(.eraser)
            }
        } catch {
            self.logger.warning("Failed to handle Apple Pencil double tap: \(error)")
        }
    }

    @MainActor
    private func shouldHandlePencilToolToggle() -> Bool {
        if isHandlingPencilToolToggle {
            logger.debug("Ignored duplicate Apple Pencil tool toggle while previous toggle is still running")
            return false
        }

        let now = Date()
        guard now.timeIntervalSince(lastPencilToolToggleAt) >= pencilToolToggleDebounceInterval else {
            logger.debug("Ignored duplicate Apple Pencil tool toggle within debounce interval")
            return false
        }

        lastPencilToolToggleAt = now
        isHandlingPencilToolToggle = true
        return true
    }

    @MainActor
    private func pencilReturnTool(from toolState: ToolState) -> ExcalidrawTool {
        let previousTool = toolState.previousActivatedTool
        if toolState.pencilInteractionMode == .fingerSelect,
           previousTool == .cursor {
            return .freedraw
        } else if let previousTool,
                  previousTool != .eraser,
                  previousTool != .hand {
            return previousTool
        } else {
            return .freedraw
        }
    }
}
#endif
