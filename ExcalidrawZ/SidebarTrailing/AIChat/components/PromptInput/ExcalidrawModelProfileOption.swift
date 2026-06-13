//
//  ExcalidrawModelProfileOption.swift
//  ExcalidrawZ
//
//  Created by Codex on 6/13/26.
//

import Foundation
import LLMCore

struct ExcalidrawModelProfileOption: Identifiable, Equatable {
    let profileID: String
    let tier: ExcalidrawModelTier
    let model: SupportedModel
    let rank: Int
    let isVisible: Bool
    let requiresMaxAIPlan: Bool
    let supportsImageInput: Bool
    let maxContextTokens: Int?

    var id: String { profileID }
    var title: String { tier.name }
}

extension ExcalidrawModelTier {
    init?(profileID: String) {
        self.init(rawValue: profileID)
    }
}

extension ModelProfileRequirements {
    var requiresExcalidrawMaxAIPlan: Bool {
        plan == "max"
    }
}

extension DomainModelProfile {
    var excalidrawModelProfileOption: ExcalidrawModelProfileOption? {
        guard let tier = ExcalidrawModelTier(profileID: id) else { return nil }
        return ExcalidrawModelProfileOption(
            profileID: id,
            tier: tier,
            model: model,
            rank: rank,
            isVisible: isVisible,
            requiresMaxAIPlan: requirements.requiresExcalidrawMaxAIPlan,
            supportsImageInput: capabilities.supportsImageInput ?? model.supportsExcalidrawImageInput,
            maxContextTokens: capabilities.maxContextTokens ?? model.maxContextTokens
        )
    }
}

extension DomainAgentConfigResponse {
    var excalidrawModelOptions: [ExcalidrawModelProfileOption] {
        modelProfiles?.compactMap(\.excalidrawModelProfileOption) ?? []
    }
}
