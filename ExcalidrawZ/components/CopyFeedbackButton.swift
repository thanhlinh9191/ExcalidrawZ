//
//  CopyFeedbackButton.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/05/27.
//

import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct CopyFeedbackButton: View {
    let text: String
    var help: String = String(localizable: .generalButtonCopy)
    var iconFrame: CGSize = CGSize(width: 14, height: 14)
    var iconFont: Font = .caption
    var normalColor: Color = .secondary
    var copiedColor: Color = .green

    @State private var copied = false
    @State private var revertTask: Task<Void, Never>?

    private static let revertDelay: Duration = .seconds(1.4)

    var body: some View {
        Button {
            copyToClipboard(text)
            withAnimation(.easeInOut(duration: 0.15)) {
                copied = true
            }
            revertTask?.cancel()
            revertTask = Task { @MainActor in
                try? await Task.sleep(for: Self.revertDelay)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    copied = false
                }
            }
        } label: {
            icon
                .frame(width: iconFrame.width, height: iconFrame.height)
                .font(iconFont)
        }
        .foregroundStyle(copied ? copiedColor : normalColor)
        .help(help)
        .copySensoryFeedback(trigger: copied)
    }

    @ViewBuilder
    private var icon: some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
        } else {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
        }
    }

    private func copyToClipboard(_ text: String) {
#if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
#elseif canImport(UIKit)
        UIPasteboard.general.string = text
#endif
    }
}

private struct CopySensoryFeedbackModifier: ViewModifier {
    let trigger: Bool

    func body(content: Content) -> some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            content
                .sensoryFeedback(.success, trigger: trigger) { _, newValue in
                    newValue
                }
        } else {
            content
        }
    }
}

private extension View {
    func copySensoryFeedback(trigger: Bool) -> some View {
        modifier(CopySensoryFeedbackModifier(trigger: trigger))
    }
}
