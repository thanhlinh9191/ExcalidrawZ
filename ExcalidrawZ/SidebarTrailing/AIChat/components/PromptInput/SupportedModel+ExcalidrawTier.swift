//
//  SupportedModel+ExcalidrawTier.swift
//  ExcalidrawZ
//
//  Maps the upstream `SupportedModel` cases to ExcalidrawZ's
//  user-facing tier vocabulary (Low / Medium / High / Extra High).
//
//  Rationale: the model picker in the chat input shouldn't expose
//  vendor / version names like "Claude Sonnet 4.6" — most users
//  don't have a frame of reference for those, and the lineup will
//  rotate over time as we upgrade. Tier labels stay stable and
//  communicate the cost / capability tradeoff directly.
//
//  We deliberately don't extend `SupportedModel.displayName` itself
//  (it's defined upstream in LLMCore and Swift extensions can't
//  override existing methods on imported types). Instead the chat UI
//  reaches for `excalidrawTierName`; everything else (settings, raw
//  identifiers, server-bound config) keeps using the upstream
//  `displayName` / `rawValue`.
//
//  Server-defined `DomainModelProfile.id` is the source of truth for
//  current model selection. The upstream-model mapping below only exists
//  for legacy preference migration and usage-history display.
//

import Foundation
import LLMCore

enum ExcalidrawModelTier: String, Codable, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high
    case extraHigh

    static var pickerOrder: [Self] {
        [.extraHigh, .high, .medium, .low]
    }

    var id: String { rawValue }

    var name: String {
        switch self {
            case .low:
                return String(localizable: .aiChatModelTierLow)
            case .medium:
                return String(localizable: .aiChatModelTierMedium)
            case .high:
                return String(localizable: .aiChatModelTierHigh)
            case .extraHigh:
                return String(localizable: .aiChatModelTierExtraHigh)
        }
    }

}

extension SupportedModel {
    var excalidrawTier: ExcalidrawModelTier? {
        switch self {
            case .hy3Preview:
                return .low
            case .qwen3_6Plus:
                return .medium
            case .claudeSonnet4_6:
                return .high
            case .claudeOpus4_7:
                return .extraHigh
            default:
                return nil
        }
    }

    /// User-facing tier label used by the chat input's model picker.
    /// DEBUG builds expose the upstream `displayName` for unmapped models
    /// so newly added cases are easy to spot during development. Release
    /// builds keep the picker on stable tier vocabulary.
    var excalidrawTierName: String {
        if let tier = excalidrawTier {
            return tier.name
        }
#if DEBUG
        return displayName
#else
        return "Experimental"
#endif
    }

    var supportsExcalidrawImageInput: Bool {
        supportsImageInput
    }

}
