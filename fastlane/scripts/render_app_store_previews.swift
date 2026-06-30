#!/usr/bin/env swift

import AppKit
import CoreText
import Foundation

struct PreviewConfig: Decodable {
    let template: String?
    let templates: [String]?
    let fontDirectories: [String]?
    let fontFiles: [String]?
    let output: String
    let sliceWidth: CGFloat
    let gapWidth: CGFloat?
    let defaultStyle: TextStyle
    let boxes: [TextBox]
    let locales: [String: LocaleConfig]
}

struct LocaleConfig: Decodable {
    let direction: String?
    let fontNames: [String]?
    let fontSize: CGFloat?
    let minFontSize: CGFloat?
    let lineHeight: CGFloat?
    let texts: [String: String]
}

struct TextStyle: Decodable {
    let fontNames: [String]?
    let fontSize: CGFloat?
    let minFontSize: CGFloat?
    let lineHeight: CGFloat?
    let color: String?
    let alignment: String?
    let verticalAlignment: String?
    let weight: String?
}

struct TextBox: Decodable {
    let slide: Int
    let key: String
    let x: CGFloat?
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let fontNames: [String]?
    let fontSize: CGFloat?
    let minFontSize: CGFloat?
    let lineHeight: CGFloat?
    let color: String?
    let alignment: String?
    let horizontalPlacement: String?
    let verticalAlignment: String?
    let weight: String?
}

struct Arguments {
    var configPath = "fastlane/previews/iphone.json"
    var repoRoot: String?
    var templateOverride: String?
    var outputOverride: String?
    var locales: Set<String>?
    var dryRun = false
}

let arguments = try parseArguments(CommandLine.arguments.dropFirst())
let repoRoot = URL(
    fileURLWithPath: arguments.repoRoot ?? FileManager.default.currentDirectoryPath,
    isDirectory: true
)
let configURL = resolvePath(arguments.configPath, relativeTo: repoRoot)
let configData = try Data(contentsOf: configURL)
let config = try JSONDecoder().decode(PreviewConfig.self, from: configData)
registerConfiguredFonts(config: config, repoRoot: repoRoot)
let enabledLocales = arguments.locales ?? Set(config.locales.keys)

if arguments.dryRun {
    for locale in config.locales.keys.sorted() where enabledLocales.contains(locale) {
        let outputPattern = arguments.outputOverride ?? config.output
        let outputPath = outputPattern.replacingOccurrences(of: "{locale}", with: locale)
        let outputURL = resolvePath(outputPath, relativeTo: repoRoot)
        let templateURL = selectTemplateURL(for: locale, config: config, arguments: arguments, repoRoot: repoRoot, allowMissing: true)
        print("Would render \(locale) using \(templateURL.path) -> \(outputURL.path)")
    }
    exit(0)
}

var templateCache: [String: (image: NSImage, canvasSize: NSSize)] = [:]

for locale in config.locales.keys.sorted() where enabledLocales.contains(locale) {
    guard let localeConfig = config.locales[locale] else { continue }
    let templateURL = selectTemplateURL(for: locale, config: config, arguments: arguments, repoRoot: repoRoot)
    let template = loadTemplate(templateURL, cache: &templateCache)
    let outputPattern = arguments.outputOverride ?? config.output
    let outputPath = outputPattern.replacingOccurrences(of: "{locale}", with: locale)
    let outputURL = resolvePath(outputPath, relativeTo: repoRoot)

    let bitmap = makeBitmapImageRep(size: template.canvasSize)
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fail("Failed to create bitmap context for \(outputURL.path)")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.shouldAntialias = true
    context.imageInterpolation = .high

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: template.canvasSize).fill()

    template.image.draw(
        in: NSRect(origin: .zero, size: template.canvasSize),
        from: NSRect(origin: .zero, size: template.image.size),
        operation: .copy,
        fraction: 1
    )

    for box in config.boxes {
        guard let text = localeConfig.texts[box.key] else {
            continue
        }
        draw(text: text, in: box, locale: localeConfig, config: config, canvasSize: template.canvasSize)
    }

    NSGraphicsContext.restoreGraphicsState()

    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try writePNG(bitmap, to: outputURL)
    print("Wrote \(outputURL.path)")
}

func selectTemplateURL(
    for locale: String,
    config: PreviewConfig,
    arguments: Arguments,
    repoRoot: URL,
    allowMissing: Bool = false
) -> URL {
    let patterns = templatePatterns(config: config, arguments: arguments)
    let candidateURLs = patterns.map {
        resolvePath($0.replacingOccurrences(of: "{locale}", with: locale), relativeTo: repoRoot)
    }

    if let existingURL = candidateURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
        return existingURL
    }

    guard allowMissing, let firstURL = candidateURLs.first else {
        fail("Template image does not exist for \(locale). Tried: \(candidateURLs.map(\.path).joined(separator: ", "))")
    }

    return firstURL
}

func templatePatterns(config: PreviewConfig, arguments: Arguments) -> [String] {
    if let templateOverride = arguments.templateOverride {
        return [templateOverride]
    }

    var patterns = config.templates ?? []
    if let template = config.template {
        patterns.append(template)
    }

    guard !patterns.isEmpty else {
        fail("Preview config must define template or templates.")
    }

    return patterns
}

func loadTemplate(
    _ url: URL,
    cache: inout [String: (image: NSImage, canvasSize: NSSize)]
) -> (image: NSImage, canvasSize: NSSize) {
    if let cached = cache[url.path] {
        return cached
    }

    guard let templateImage = NSImage(contentsOf: url) else {
        fail("Failed to read template image: \(url.path)")
    }

    guard let templateCGImage = templateImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fail("Failed to read template pixels: \(url.path)")
    }

    let canvasSize = NSSize(width: templateCGImage.width, height: templateCGImage.height)
    guard canvasSize.width > 0, canvasSize.height > 0 else {
        fail("Template image has invalid size: \(canvasSize)")
    }

    let loaded = (image: templateImage, canvasSize: canvasSize)
    cache[url.path] = loaded
    return loaded
}

func registerConfiguredFonts(config: PreviewConfig, repoRoot: URL) {
    let fileManager = FileManager.default
    var fontURLs: [URL] = []

    for path in config.fontFiles ?? [] {
        fontURLs.append(resolvePath(path, relativeTo: repoRoot))
    }

    for path in config.fontDirectories ?? [] {
        let directoryURL = resolvePath(path, relativeTo: repoRoot)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            warn("Font directory does not exist: \(directoryURL.path)")
            continue
        }

        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            warn("Could not enumerate font directory: \(directoryURL.path)")
            continue
        }

        for case let fontURL as URL in enumerator where isFontFile(fontURL) {
            fontURLs.append(fontURL)
        }
    }

    var registeredPaths = Set<String>()
    for fontURL in fontURLs where registeredPaths.insert(fontURL.path).inserted {
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error),
           let error = error?.takeRetainedValue() {
            warn("Could not register font \(fontURL.path): \(error)")
        }
    }
}

func isFontFile(_ url: URL) -> Bool {
    switch url.pathExtension.lowercased() {
        case "otf", "ttf", "woff", "woff2":
            return true
        default:
            return false
    }
}

func draw(
    text: String,
    in box: TextBox,
    locale: LocaleConfig,
    config: PreviewConfig,
    canvasSize: NSSize
) {
    let slideStride = config.sliceWidth + (config.gapWidth ?? 0)
    let localX = horizontalOrigin(for: box, in: config)
    let absoluteX = CGFloat(max(0, box.slide - 1)) * slideStride + localX
    let rect = NSRect(
        x: absoluteX,
        y: canvasSize.height - box.y - box.height,
        width: box.width,
        height: box.height
    )
    let fontSize = fittingFontSize(text: text, box: box, locale: locale, config: config)
    let attributedText = makeAttributedString(
        text: text,
        fontSize: fontSize,
        box: box,
        locale: locale,
        config: config
    )
    let measured = attributedText.boundingRect(
        with: NSSize(width: rect.width, height: CGFloat.greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    ).integral
    let verticalAlignment = box.verticalAlignment
        ?? config.defaultStyle.verticalAlignment
        ?? "middle"
    let drawY: CGFloat

    switch verticalAlignment {
        case "top":
            drawY = rect.maxY - measured.height
        case "bottom":
            drawY = rect.minY
        default:
            drawY = rect.minY + max(0, (rect.height - measured.height) / 2)
    }

    attributedText.draw(
        with: NSRect(x: rect.minX, y: drawY, width: rect.width, height: rect.height),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
}

func horizontalOrigin(for box: TextBox, in config: PreviewConfig) -> CGFloat {
    let offset = box.x ?? 0

    switch box.horizontalPlacement {
        case "center":
            return max(0, (config.sliceWidth - box.width) / 2) + offset
        case "right", "trailing":
            return max(0, config.sliceWidth - box.width) - offset
        default:
            return offset
    }
}

func fittingFontSize(
    text: String,
    box: TextBox,
    locale: LocaleConfig,
    config: PreviewConfig
) -> CGFloat {
    let start = box.fontSize
        ?? locale.fontSize
        ?? config.defaultStyle.fontSize
        ?? 78
    let minimum = box.minFontSize
        ?? locale.minFontSize
        ?? config.defaultStyle.minFontSize
        ?? 42

    var candidate = start
    while candidate >= minimum {
        let attributedText = makeAttributedString(
            text: text,
            fontSize: candidate,
            box: box,
            locale: locale,
            config: config
        )
        let measured = attributedText.boundingRect(
            with: NSSize(width: box.width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        if measured.width <= box.width + 1, measured.height <= box.height + 1 {
            return candidate
        }

        candidate -= 2
    }

    return minimum
}

func makeAttributedString(
    text: String,
    fontSize: CGFloat,
    box: TextBox,
    locale: LocaleConfig,
    config: PreviewConfig
) -> NSAttributedString {
    let paragraphStyle = NSMutableParagraphStyle()
    let lineHeight = box.lineHeight
        ?? locale.lineHeight
        ?? config.defaultStyle.lineHeight
        ?? 1.08

    paragraphStyle.alignment = textAlignment(
        box.alignment
            ?? config.defaultStyle.alignment
            ?? "center"
    )
    paragraphStyle.baseWritingDirection = locale.direction == "rtl"
        ? .rightToLeft
        : .leftToRight
    paragraphStyle.minimumLineHeight = fontSize * lineHeight
    paragraphStyle.maximumLineHeight = fontSize * lineHeight

    let textColor = nsColor(
        box.color
            ?? config.defaultStyle.color
            ?? "#FFFFFF"
    )
    let baseFont = font(for: fontSize, box: box, locale: locale, config: config)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: baseFont,
        .foregroundColor: textColor,
        .paragraphStyle: paragraphStyle
    ]

    let attributedText = NSMutableAttributedString(string: text, attributes: attributes)
    applyScriptFontOverrides(
        to: attributedText,
        text: text,
        fontSize: fontSize,
        box: box,
        locale: locale,
        config: config
    )
    return attributedText
}

func font(
    for size: CGFloat,
    box: TextBox,
    locale: LocaleConfig,
    config: PreviewConfig
) -> NSFont {
    let candidates = box.fontNames
        ?? locale.fontNames
        ?? config.defaultStyle.fontNames
        ?? []

    for name in candidates {
        if let font = NSFont(name: name, size: size) {
            return font
        }
    }

    return NSFont.systemFont(
        ofSize: size,
        weight: fontWeight(
            box.weight
                ?? config.defaultStyle.weight
                ?? "semibold"
        )
    )
}

func applyScriptFontOverrides(
    to attributedText: NSMutableAttributedString,
    text: String,
    fontSize: CGFloat,
    box: TextBox,
    locale: LocaleConfig,
    config: PreviewConfig
) {
    let candidates = box.fontNames
        ?? locale.fontNames
        ?? config.defaultStyle.fontNames
        ?? []
    guard candidates.contains(where: { $0 == "XiaolaiSC" || $0 == "Xiaolai SC" }),
          let cjkFont = candidates.lazy.compactMap({ NSFont(name: $0, size: fontSize) }).first(where: { $0.fontName == "XiaolaiSC" }),
          let latinFont = candidates.lazy.compactMap({ NSFont(name: $0, size: fontSize) }).first(where: { $0.fontName == "Excalifont-Regular" }) else {
        return
    }

    var location = 0
    for character in text {
        let range = NSRange(location: location, length: String(character).utf16.count)
        attributedText.addAttribute(
            .font,
            value: character.containsCJKScalar ? cjkFont : latinFont,
            range: range
        )
        location += range.length
    }
}

extension Character {
    var containsCJKScalar: Bool {
        unicodeScalars.contains { scalar in
            let value = scalar.value
            switch value {
                case 0x3000...0x303F,
                     0x3400...0x4DBF,
                     0x4E00...0x9FFF,
                     0xF900...0xFAFF,
                     0xFF00...0xFFEF,
                     0x20000...0x2A6DF,
                     0x2A700...0x2B73F,
                     0x2B740...0x2B81F,
                     0x2B820...0x2CEAF,
                     0x2CEB0...0x2EBEF:
                    return true
                default:
                    return false
            }
        }
    }
}

func textAlignment(_ value: String) -> NSTextAlignment {
    switch value {
        case "left":
            return .left
        case "right":
            return .right
        case "natural":
            return .natural
        default:
            return .center
    }
}

func fontWeight(_ value: String) -> NSFont.Weight {
    switch value {
        case "regular":
            return .regular
        case "medium":
            return .medium
        case "bold":
            return .bold
        case "heavy":
            return .heavy
        default:
            return .semibold
    }
}

func nsColor(_ hex: String) -> NSColor {
    let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard trimmed.count == 6,
          let value = Int(trimmed, radix: 16) else {
        return .white
    }

    return NSColor(
        calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
    )
}

func makeBitmapImageRep(size: NSSize) -> NSBitmapImageRep {
    let width = Int(size.width.rounded())
    let height = Int(size.height.rounded())
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [.alphaFirst],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fail("Failed to allocate bitmap \(width)x\(height)")
    }

    bitmap.size = size
    return bitmap
}

func writePNG(_ bitmap: NSBitmapImageRep, to url: URL) throws {
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fail("Failed to encode PNG: \(url.path)")
    }

    try png.write(to: url)
}

func resolvePath(_ path: String, relativeTo root: URL) -> URL {
    if path.hasPrefix("/") {
        return URL(fileURLWithPath: path)
    }
    return root.appendingPathComponent(path)
}

func parseArguments(_ values: ArraySlice<String>) throws -> Arguments {
    var result = Arguments()
    var iterator = values.makeIterator()

    while let argument = iterator.next() {
        switch argument {
            case "--config":
                result.configPath = try requireValue(for: argument, iterator: &iterator)
            case "--repo-root":
                result.repoRoot = try requireValue(for: argument, iterator: &iterator)
            case "--template":
                result.templateOverride = try requireValue(for: argument, iterator: &iterator)
            case "--output":
                result.outputOverride = try requireValue(for: argument, iterator: &iterator)
            case "--locales":
                let value = try requireValue(for: argument, iterator: &iterator)
                result.locales = Set(
                    value
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                )
            case "--dry-run":
                result.dryRun = true
            case "--help", "-h":
                printUsage()
                exit(0)
            default:
                fail("Unknown argument: \(argument)")
        }
    }

    return result
}

func requireValue(
    for argument: String,
    iterator: inout IndexingIterator<ArraySlice<String>>
) throws -> String {
    guard let value = iterator.next() else {
        fail("Missing value for \(argument)")
    }
    return value
}

func printUsage() {
    print(
        """
        Usage:
          swift fastlane/scripts/render_app_store_previews.swift [options]

        Options:
          --config PATH      Defaults to fastlane/previews/iphone.json
          --repo-root PATH   Defaults to the current working directory
          --template PATH    Override template image path
          --output PATTERN   Override output pattern, use {locale}
          --locales LIST     Comma-separated locale allow-list
          --dry-run          Print outputs without writing files
        """
    )
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func warn(_ message: String) {
    FileHandle.standardError.write(Data(("Warning: " + message + "\n").utf8))
}
