//
//  AdjustElementsTool operation module.
//

import Foundation

extension AdjustElementsMiddleware {
    func applyMermaidOp(
        _ op: MermaidOp,
        canvasActions: inout [CanvasAction]
    ) throws {
        let definition = op.definition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !definition.isEmpty else {
            throw AdjustmentError(message: "mermaid requires a non-empty definition.")
        }
        canvasActions.append(.insertMermaid(op))
    }

    func applyLatexOp(
        _ op: LatexOp,
        canvasActions: inout [CanvasAction]
    ) throws {
        let latex = op.latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latex.isEmpty else {
            throw AdjustmentError(message: "latex requires a non-empty LaTeX expression.")
        }
        let color = try normalizedMathColor(op.color)
        canvasActions.append(.insertLatex(LatexOp(op: op.op, latex: latex, color: color)))
    }

    private func normalizedMathColor(_ color: String?) throws -> String? {
        guard let color else { return nil }
        let trimmed = color.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let pattern = #"^#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{6})$"#
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else {
            throw AdjustmentError(message: "latex.color must be a hex color such as #1e1e1e or #fff.")
        }
        return trimmed
    }

    func applyConnectOp(
        _ op: ConnectOp,
        elements: [ExcalidrawElement],
        pendingElementIds: Set<String> = [],
        canvasActions: inout [CanvasAction]
    ) throws {
        let from = op.from.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = op.to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else {
            throw AdjustmentError(message: "connect requires non-empty `from` and `to` element ids.")
        }
        let availableElementIds = Set(elements.lazy.filter { !$0.isDeleted }.map(\.id))
            .union(pendingElementIds)
        guard availableElementIds.contains(from) else {
            throw AdjustmentError(message: "connect.from element \(from) not found or deleted.")
        }
        guard availableElementIds.contains(to) else {
            throw AdjustmentError(message: "connect.to element \(to) not found or deleted.")
        }
        if let arrow = op.arrow, case .object = arrow {
            // Valid custom arrow options.
        } else if op.arrow != nil {
            throw AdjustmentError(message: "connect.arrow must be an object when provided.")
        }
        canvasActions.append(.connect(ConnectOp(
            op: op.op,
            from: from,
            to: to,
            arrow: op.arrow,
            captureUpdate: op.captureUpdate
        )))
    }
}
