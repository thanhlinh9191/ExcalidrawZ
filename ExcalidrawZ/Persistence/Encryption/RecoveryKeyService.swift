//
//  RecoveryKeyService.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/05/27.
//

import CryptoKit
import Foundation
import Security

enum RecoveryKeyError: LocalizedError, Equatable {
    case invalidFormat
    case invalidLength
    case invalidCharacter(Character)
    case randomGenerationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
            case .invalidFormat:
                String(localizable: .recoveryKeyErrorInvalidFormat)
            case .invalidLength:
                String(localizable: .recoveryKeyErrorInvalidLength)
            case .invalidCharacter(let character):
                String(localizable: .recoveryKeyErrorInvalidCharacter(String(character)))
            case .randomGenerationFailed:
                String(localizable: .recoveryKeyErrorRandomGenerationFailed)
        }
    }

    var recoverySuggestion: String? {
        switch self {
            case .invalidFormat, .invalidLength, .invalidCharacter:
                String(localizable: .recoveryKeySuggestionPasteFullKey)
            case .randomGenerationFailed:
                String(localizable: .recoveryKeySuggestionTryAgainRestart)
        }
    }
}

struct RecoveryKey: Equatable, Sendable {
    fileprivate static let byteCount = 20

    fileprivate let rawData: Data

    var displayString: String {
        RecoveryKeyService.format(rawData)
    }

    var storageData: Data {
        rawData
    }

    init(displayString: String) throws {
        self.rawData = try RecoveryKeyService.decode(displayString)
    }

    init(storageData: Data) throws {
        try self.init(rawData: storageData)
    }

    fileprivate init(rawData: Data) throws {
        guard rawData.count == Self.byteCount else {
            throw RecoveryKeyError.invalidLength
        }
        self.rawData = rawData
    }
}

enum RecoveryKeyService {
    static let prefix = "EDZ2"

    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    private static let encodedCharacterCount = 32
    private static let derivedKeyByteCount = 32
    private static let derivationInfo = Data("ExcalidrawZ locked content recovery v1".utf8)

    static func generate() throws -> RecoveryKey {
        try RecoveryKey(rawData: randomData(byteCount: RecoveryKey.byteCount))
    }

    static func randomSalt(byteCount: Int = 32) throws -> Data {
        try randomData(byteCount: byteCount)
    }

    static func deriveWrappingKey(
        from recoveryKey: RecoveryKey,
        salt: Data,
        outputByteCount: Int = derivedKeyByteCount
    ) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: recoveryKey.rawData),
            salt: salt,
            info: derivationInfo,
            outputByteCount: outputByteCount
        )
    }

    fileprivate static func format(_ data: Data) -> String {
        let body = encode(data)
        let groups = stride(from: 0, to: body.count, by: 4).map { offset in
            let start = body.index(body.startIndex, offsetBy: offset)
            let end = body.index(start, offsetBy: min(4, body.distance(from: start, to: body.endIndex)))
            return String(body[start..<end])
        }
        return ([prefix] + groups).joined(separator: "-")
    }

    fileprivate static func decode(_ displayString: String) throws -> Data {
        let compact = displayString
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }

        guard compact.hasPrefix(prefix) else {
            throw RecoveryKeyError.invalidFormat
        }

        let body = String(compact.dropFirst(prefix.count))
        guard body.count == encodedCharacterCount else {
            throw RecoveryKeyError.invalidLength
        }

        return try decodeBody(body)
    }

    private static func encode(_ data: Data) -> String {
        var output = ""
        var buffer = 0
        var bitsLeft = 0

        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bitsLeft += 8

            while bitsLeft >= 5 {
                let index = (buffer >> (bitsLeft - 5)) & 0x1F
                output.append(alphabet[index])
                bitsLeft -= 5
            }
        }

        if bitsLeft > 0 {
            let index = (buffer << (5 - bitsLeft)) & 0x1F
            output.append(alphabet[index])
        }

        return output
    }

    private static func decodeBody(_ body: String) throws -> Data {
        var output: [UInt8] = []
        var buffer = 0
        var bitsLeft = 0

        for character in body {
            let value = try decodeValue(character)
            buffer = (buffer << 5) | value
            bitsLeft += 5

            while bitsLeft >= 8 {
                let byte = (buffer >> (bitsLeft - 8)) & 0xFF
                output.append(UInt8(byte))
                bitsLeft -= 8
            }
        }

        let data = Data(output)
        guard data.count == RecoveryKey.byteCount else {
            throw RecoveryKeyError.invalidLength
        }
        return data
    }

    private static func decodeValue(_ character: Character) throws -> Int {
        let normalized: Character
        switch character {
            case "O":
                normalized = "0"
            case "I", "L":
                normalized = "1"
            default:
                normalized = character
        }

        guard let index = alphabet.firstIndex(of: normalized) else {
            throw RecoveryKeyError.invalidCharacter(character)
        }
        return index
    }

    private static func randomData(byteCount: Int) throws -> Data {
        var data = Data(count: byteCount)
        let status = data.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(kSecRandomDefault, byteCount, baseAddress)
        }

        guard status == errSecSuccess else {
            throw RecoveryKeyError.randomGenerationFailed(status)
        }
        return data
    }
}
