//
//  FeatureDiscoveryTips.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/02.
//

import SwiftUI

#if canImport(TipKit)
import TipKit
#endif

enum FeatureDiscoveryTips {
    @MainActor
    static func configureIfAvailable() {
#if canImport(TipKit)
        if #available(macOS 14.0, iOS 17.0, *) {
            try? Tips.configure([
                .datastoreLocation(.applicationDefault)
            ])
        }
#endif
    }
}

enum FeatureDiscoveryTipKind {
    case aiFileVisibility
    case lockFile
}

struct FeatureDiscoveryTipModifier: ViewModifier {
    let kind: FeatureDiscoveryTipKind
    var isEnabled: Bool = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
#if canImport(TipKit)
            if #available(macOS 14.0, iOS 17.0, *) {
                switch kind {
                    case .aiFileVisibility:
                        content.popoverTip(AIFileVisibilityDiscoveryTip())
                    case .lockFile:
                        content.popoverTip(LockFileDiscoveryTip())
                }
            } else {
                content
            }
#else
            content
#endif
        } else {
            content
        }
    }
}

#if canImport(TipKit)
@available(macOS 14.0, iOS 17.0, *)
private struct AIFileVisibilityDiscoveryTip: Tip {
    var title: Text {
        Text("AI File Visibility")
    }

    var message: Text? {
        Text("Control whether AI can read the current file. When hidden, AI can still answer general questions and create proposal edits.")
    }

    var image: Image? {
        Image(systemName: "eye.slash")
    }
}

@available(macOS 14.0, iOS 17.0, *)
private struct LockFileDiscoveryTip: Tip {
    var title: Text {
        Text("Lock File")
    }

    var message: Text? {
        Text("Encrypt this file to protect its saved content. Locked files also stay unavailable to AI.")
    }

    var image: Image? {
        Image(systemName: "lock.shield")
    }
}
#endif
