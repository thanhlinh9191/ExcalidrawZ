//
//  ExcalidrawCore+JavaScriptBridge.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/18.
//

import Foundation

extension ExcalidrawCore {
    struct JSONEncodingFailed: Error {}

    struct InvalidJavaScriptResult: LocalizedError, Sendable {
        var errorDescription: String? {
            "The Excalidraw web view did not return a valid JavaScript result."
        }
    }

    enum JSONValue: Codable, Hashable, Sendable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case object([String: JSONValue])
        case array([JSONValue])
        case null

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([String: JSONValue].self) {
                self = .object(value)
            } else if let value = try? container.decode([JSONValue].self) {
                self = .array(value)
            } else {
                throw InvalidJavaScriptResult()
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
                case .string(let value):
                    try container.encode(value)
                case .number(let value):
                    try container.encode(value)
                case .bool(let value):
                    try container.encode(value)
                case .object(let value):
                    try container.encode(value)
                case .array(let value):
                    try container.encode(value)
                case .null:
                    try container.encodeNil()
            }
        }

        var foundationObject: Any {
            switch self {
                case .string(let value):
                    return value
                case .number(let value):
                    return value
                case .bool(let value):
                    return value
                case .object(let value):
                    return value.mapValues(\.foundationObject)
                case .array(let value):
                    return value.map(\.foundationObject)
                case .null:
                    return NSNull()
            }
        }
    }

    func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw JSONEncodingFailed()
        }
        return jsonString
    }

    func decodeJavaScriptResult<T: Decodable>(_ result: Any?, as type: T.Type) throws -> T {
        if let string = result as? String,
           let data = string.data(using: .utf8) {
            do {
                return try JSONDecoder().decode(type, from: data)
            } catch {
                throw JavaScriptResultDecodingError(
                    targetType: String(describing: type),
                    reason: Self.describeDecodingFailure(error),
                    rawJSON: string
                )
            }
        }
        if let result,
           JSONSerialization.isValidJSONObject(result) {
            let data = try JSONSerialization.data(withJSONObject: result)
            do {
                return try JSONDecoder().decode(type, from: data)
            } catch {
                throw JavaScriptResultDecodingError(
                    targetType: String(describing: type),
                    reason: Self.describeDecodingFailure(error),
                    rawJSON: String(data: data, encoding: .utf8)
                )
            }
        }
        throw InvalidJavaScriptResult()
    }

    func makeJavaScriptHelperCall(_ expression: String) -> String {
        """
        const __excalidrawZHelperCall = async () => {
            try {
                const value = await \(expression);
                return JSON.stringify({ ok: true, value });
            } catch (error) {
                const name = error && error.name ? String(error.name) : null;
                const message = error && error.message ? String(error.message) : String(error);
                const stack = error && error.stack ? String(error.stack) : null;
                return JSON.stringify({
                    ok: false,
                    error: { name, message, stack }
                });
            }
        };
        return await __excalidrawZHelperCall();
        """
    }

    func decodeJavaScriptHelperResult<T: Decodable>(_ result: Any?, as type: T.Type) throws -> T {
        let envelope = try decodeJavaScriptResult(result, as: JavaScriptHelperResult<T>.self)
        if envelope.ok, let value = envelope.value {
            return value
        }
        throw JavaScriptHelperExecutionError(payload: envelope.error)
    }

    private struct JavaScriptResultDecodingError: LocalizedError, Sendable {
        let targetType: String
        let reason: String
        let rawJSON: String?

        var errorDescription: String? {
            var message = "Failed to decode JavaScript result as \(targetType): \(reason)"
            if let rawJSON {
                message += "\nRaw result: \(Self.preview(rawJSON))"
            }
            return message
        }

        private static func preview(_ rawJSON: String) -> String {
            let limit = 2000
            if rawJSON.count <= limit {
                return rawJSON
            }
            return String(rawJSON.prefix(limit)) + "...(truncated)"
        }
    }

    private struct JavaScriptHelperResult<T: Decodable>: Decodable {
        let ok: Bool
        let value: T?
        let error: JavaScriptHelperErrorPayload?
    }

    private struct JavaScriptHelperErrorPayload: Decodable {
        let name: String?
        let message: String?
        let stack: String?
    }

    private struct JavaScriptHelperExecutionError: LocalizedError {
        let payload: JavaScriptHelperErrorPayload?

        var errorDescription: String? {
            guard let payload else {
                return "JavaScript helper execution failed without an error payload."
            }

            var message = "JavaScript helper execution failed"
            if let name = payload.name, !name.isEmpty {
                message += ": \(name)"
            }
            if let errorMessage = payload.message, !errorMessage.isEmpty {
                message += " - \(errorMessage)"
            }
            if let stack = payload.stack, !stack.isEmpty {
                message += "\nStack: \(Self.preview(stack))"
            }
            return message
        }

        private static func preview(_ value: String) -> String {
            let limit = 2000
            if value.count <= limit {
                return value
            }
            return String(value.prefix(limit)) + "...(truncated)"
        }
    }

    private static func describeDecodingFailure(_ error: Error) -> String {
        switch error {
            case DecodingError.keyNotFound(let key, let context):
                return "missing key `\(key.stringValue)` at \(formatCodingPath(context.codingPath, appending: key)); \(context.debugDescription)"
            case DecodingError.valueNotFound(let type, let context):
                return "missing value for \(type) at \(formatCodingPath(context.codingPath)); \(context.debugDescription)"
            case DecodingError.typeMismatch(let type, let context):
                return "type mismatch for \(type) at \(formatCodingPath(context.codingPath)); \(context.debugDescription)"
            case DecodingError.dataCorrupted(let context):
                return "data corrupted at \(formatCodingPath(context.codingPath)); \(context.debugDescription)"
            default:
                return error.localizedDescription
        }
    }

    private static func formatCodingPath(_ path: [any CodingKey], appending key: (any CodingKey)? = nil) -> String {
        let fullPath = key.map { path + [$0] } ?? path
        guard !fullPath.isEmpty else { return "$" }
        return "$." + fullPath.map(\.stringValue).joined(separator: ".")
    }
}

#if DEBUG
extension ExcalidrawCore {
    @MainActor
    func debugThrowJavaScriptErrorForToastProbe() async throws {
        do {
            _ = try await webView.callAsyncJavaScript(
                """
                throw new Error("ExcalidrawZ debug JavaScript error propagation probe");
                """,
                arguments: [:],
                contentWorld: .page
            )
        } catch {
            publishError(error)
            throw error
        }
    }
}
#endif
