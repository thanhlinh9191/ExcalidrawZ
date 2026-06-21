//
//  ExcalidrawMCPOptimizedResources.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/21.
//

import Foundation

enum ExcalidrawMCPOptimizedResources {
    static func text(named resourceName: String, fallback: String) -> String {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return fallback
        }
        return text
    }

    static func schema(named key: String) -> MCPJSONValue {
        schemas[key] ?? ExcalidrawMCPToolSchemas.emptyObject
    }

    static func description(named key: String, fallback: String = "Optimized MCP tool.") -> String {
        descriptions[key]?.stringValue ?? fallback
    }

    private static let schemas: [String: MCPJSONValue] = {
        guard case .object(let object) = jsonResource(named: "ExcalidrawMCPOptimizedSchemas") else {
            return [:]
        }
        return object
    }()

    private static let descriptions: [String: MCPJSONValue] = {
        guard case .object(let object) = jsonResource(named: "ExcalidrawMCPOptimizedToolDescriptions") else {
            return [:]
        }
        return object
    }()

    private static func jsonResource(named resourceName: String) -> MCPJSONValue? {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? MCPJSONValue.parse(from: data) else {
            return nil
        }
        return value
    }
}
