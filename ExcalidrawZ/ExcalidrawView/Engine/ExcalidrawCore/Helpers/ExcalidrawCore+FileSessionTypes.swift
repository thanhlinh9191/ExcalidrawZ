//
//  ExcalidrawCore+FileSessionTypes.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/18.
//

import Foundation

extension ExcalidrawCore {
    /// One-time copy of the current editor scene at the moment it was requested.
    /// This is not a persistent/live reference and must not drive autosave.
    struct CurrentFileSnapshot: Sendable {
        var revision: Int?
        var elementCount: Int
        var fileCount: Int
        private var bridgedDocumentData: Data

        init(
            revision: Int?,
            elementCount: Int,
            fileCount: Int,
            documentData: Data
        ) {
            self.revision = revision
            self.elementCount = elementCount
            self.fileCount = fileCount
            self.bridgedDocumentData = documentData
        }

        init(saveStreamResult: CurrentFileSaveStreamResult) {
            self.revision = saveStreamResult.revision
            self.elementCount = saveStreamResult.elementCount
            self.fileCount = saveStreamResult.fileCount
            self.bridgedDocumentData = saveStreamResult.documentData
        }

        func documentData(includeFiles: Bool = true) throws -> Data {
            guard !includeFiles else {
                return bridgedDocumentData
            }

            guard var payload = try JSONSerialization.jsonObject(with: bridgedDocumentData) as? [String: Any] else {
                throw InvalidJavaScriptResult()
            }
            payload.removeValue(forKey: "files")
            return try JSONSerialization.data(withJSONObject: payload)
        }

        static func fromJavaScriptResult(_ result: Any?) throws -> Self {
            if let string = result as? String {
                guard let data = string.data(using: .utf8) else {
                    throw InvalidJavaScriptResult()
                }
                return try fromJavaScriptResult(try JSONSerialization.jsonObject(with: data))
            }

            guard let dictionary = result as? [String: Any] else {
                throw InvalidJavaScriptResult()
            }

            let elementsObject: Any = dictionary["elements"] ?? [Any]()
            let appStateObject: Any = dictionary["appState"] ?? [String: Any]()
            let filesObject: Any = dictionary["files"] ?? [String: Any]()
            let documentPayload: [String: Any] = [
                "elements": elementsObject,
                "appState": appStateObject,
                "files": filesObject
            ]

            return .init(
                revision: intValue(from: dictionary["revision"]),
                elementCount: (elementsObject as? [Any])?.count ?? 0,
                fileCount: (filesObject as? [String: Any])?.count ?? 0,
                documentData: try JSONSerialization.data(withJSONObject: documentPayload)
            )
        }

        private static func intValue(from value: Any?) -> Int? {
            if let value = value as? Int {
                return value
            }
            if let value = value as? Double {
                return Int(value)
            }
            if let value = value as? NSNumber,
               CFGetTypeID(value) != CFBooleanGetTypeID() {
                return value.intValue
            }
            return nil
        }
    }
}
