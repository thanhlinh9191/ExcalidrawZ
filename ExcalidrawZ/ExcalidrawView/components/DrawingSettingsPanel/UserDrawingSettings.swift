//
//  UserDrawingSettings.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/04.
//

import Foundation

/// User drawing settings for Excalidraw
struct UserDrawingSettings: Codable, Equatable {
    var currentItemStrokeWidthKey: StrokeWidthKey?
    var currentItemStrokeVariability: StrokeVariability?
    var currentItemStrokeColor: String?
    var currentItemBackgroundColor: String?
    var currentItemStrokeStyle: ExcalidrawStrokeStyle?
    var currentItemFillStyle: ExcalidrawFillStyle?
    var currentItemRoughness: Double?
    var currentItemOpacity: Double?
    var currentItemFontFamily: FontFamily?
    var currentItemFontSize: Double?
    var currentItemTextAlign: String?
    var currentItemRoundness: ExcalidrawStrokeSharpness?
    var currentItemArrowType: ArrowType?
    var currentItemStartArrowhead: Nullable<Arrowhead>?
    var currentItemEndArrowhead: Nullable<Arrowhead>?

    var strokeWidth: Double? {
        currentItemStrokeWidthKey?.strokeWidth
    }

    mutating func setStrokeWidth(_ strokeWidth: Double?) {
        currentItemStrokeWidthKey = strokeWidth.flatMap(StrokeWidthKey.init(strokeWidth:))
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.currentItemStrokeWidthKey = try container.decodeIfPresent(StrokeWidthKey.self, forKey: .currentItemStrokeWidthKey)
        if self.currentItemStrokeWidthKey == nil,
           let legacyStrokeWidth = try container.decodeIfPresent(Double.self, forKey: .currentItemStrokeWidth) {
            self.currentItemStrokeWidthKey = StrokeWidthKey(strokeWidth: legacyStrokeWidth)
        }
        self.currentItemStrokeVariability = try container.decodeIfPresent(StrokeVariability.self, forKey: .currentItemStrokeVariability)

        self.currentItemStrokeColor = try container.decodeIfPresent(String.self, forKey: .currentItemStrokeColor)
        self.currentItemBackgroundColor = try container.decodeIfPresent(String.self, forKey: .currentItemBackgroundColor)
        self.currentItemStrokeStyle = try container.decodeIfPresent(ExcalidrawStrokeStyle.self, forKey: .currentItemStrokeStyle)
        self.currentItemFillStyle = try container.decodeIfPresent(ExcalidrawFillStyle.self, forKey: .currentItemFillStyle)
        self.currentItemRoughness = try container.decodeIfPresent(Double.self, forKey: .currentItemRoughness)
        self.currentItemOpacity = try container.decodeIfPresent(Double.self, forKey: .currentItemOpacity)
        self.currentItemFontFamily = try container.decodeIfPresent(FontFamily.self, forKey: .currentItemFontFamily)
        self.currentItemFontSize = try container.decodeIfPresent(Double.self, forKey: .currentItemFontSize)
        self.currentItemTextAlign = try container.decodeIfPresent(String.self, forKey: .currentItemTextAlign)
        self.currentItemRoundness = try container.decodeIfPresent(ExcalidrawStrokeSharpness.self, forKey: .currentItemRoundness)
        self.currentItemArrowType = try container.decodeIfPresent(ArrowType.self, forKey: .currentItemArrowType)
        self.currentItemStartArrowhead = try container.decodeIfPresent(Nullable<Arrowhead>.self, forKey: .currentItemStartArrowhead)
        self.currentItemEndArrowhead = try container.decodeIfPresent(Nullable<Arrowhead>.self, forKey: .currentItemEndArrowhead)
    }

    /// Convert to JSON string for JavaScript
    func toJSONString() -> String? {
        guard let data = try? JSONEncoder().encode(self),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(currentItemStrokeWidthKey, forKey: .currentItemStrokeWidthKey)
        try container.encodeIfPresent(currentItemStrokeVariability, forKey: .currentItemStrokeVariability)
        try container.encodeIfPresent(currentItemStrokeColor, forKey: .currentItemStrokeColor)
        try container.encodeIfPresent(currentItemBackgroundColor, forKey: .currentItemBackgroundColor)
        try container.encodeIfPresent(currentItemStrokeStyle, forKey: .currentItemStrokeStyle)
        try container.encodeIfPresent(currentItemFillStyle, forKey: .currentItemFillStyle)
        try container.encodeIfPresent(currentItemRoughness, forKey: .currentItemRoughness)
        try container.encodeIfPresent(currentItemOpacity, forKey: .currentItemOpacity)
        try container.encodeIfPresent(currentItemFontFamily, forKey: .currentItemFontFamily)
        try container.encodeIfPresent(currentItemFontSize, forKey: .currentItemFontSize)
        try container.encodeIfPresent(currentItemTextAlign, forKey: .currentItemTextAlign)
        try container.encodeIfPresent(currentItemRoundness, forKey: .currentItemRoundness)
        try container.encodeIfPresent(currentItemArrowType, forKey: .currentItemArrowType)
        try container.encodeIfPresent(currentItemStartArrowhead, forKey: .currentItemStartArrowhead)
        try container.encodeIfPresent(currentItemEndArrowhead, forKey: .currentItemEndArrowhead)
    }

    enum CodingKeys: String, CodingKey {
        case currentItemStrokeWidthKey
        // Decode-only legacy key from old Excalidraw appState.
        case currentItemStrokeWidth
        case currentItemStrokeVariability
        case currentItemStrokeColor
        case currentItemBackgroundColor
        case currentItemStrokeStyle
        case currentItemFillStyle
        case currentItemRoughness
        case currentItemOpacity
        case currentItemFontFamily
        case currentItemFontSize
        case currentItemTextAlign
        case currentItemRoundness
        case currentItemArrowType
        case currentItemStartArrowhead
        case currentItemEndArrowhead
    }

    /// Parse from a file's raw JSON `Data`. Goes straight through
    /// `JSONSerialization` and into `from(dict:)` — bypasses the web view, which
    /// is important for fresh/empty files: Excalidraw's `restoreAppState` carries
    /// the previous file's `currentItem*` values forward as defaults, so reading
    /// live appState would return stale values.
    static func from(fileContent data: Data) -> UserDrawingSettings {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let appState = json["appState"] as? [String: Any] else {
            return UserDrawingSettings()
        }
        return from(dict: appState)
    }

    /// Create from dictionary (from JavaScript message)
    static func from(dict: [String: Any]) -> UserDrawingSettings {
        var settings = UserDrawingSettings()
        if let strokeWidthKey = dict["currentItemStrokeWidthKey"] as? String {
            settings.currentItemStrokeWidthKey = StrokeWidthKey(rawValue: strokeWidthKey)
        }
        if settings.currentItemStrokeWidthKey == nil,
           let legacyStrokeWidth = numberValue(dict["currentItemStrokeWidth"]) {
            settings.currentItemStrokeWidthKey = StrokeWidthKey(strokeWidth: legacyStrokeWidth)
        }
        if let strokeVariability = dict["currentItemStrokeVariability"] as? String {
            settings.currentItemStrokeVariability = StrokeVariability(rawValue: strokeVariability)
        }
        settings.currentItemStrokeColor = dict["currentItemStrokeColor"] as? String
        settings.currentItemBackgroundColor = dict["currentItemBackgroundColor"] as? String

        // Convert string to enum types
        if let strokeStyle = dict["currentItemStrokeStyle"] as? String {
            settings.currentItemStrokeStyle = ExcalidrawStrokeStyle(rawValue: strokeStyle)
        }
        if let fillStyle = dict["currentItemFillStyle"] as? String {
            settings.currentItemFillStyle = ExcalidrawFillStyle(rawValue: fillStyle)
        }

        settings.currentItemRoughness = dict["currentItemRoughness"] as? Double
        settings.currentItemOpacity = dict["currentItemOpacity"] as? Double
        if let fontFamilyValue = dict["currentItemFontFamily"] as? Int {
            settings.currentItemFontFamily = FontFamily(rawValue: fontFamilyValue)
        }
        settings.currentItemFontSize = dict["currentItemFontSize"] as? Double
        settings.currentItemTextAlign = dict["currentItemTextAlign"] as? String
        if let roundness = dict["currentItemRoundness"] as? String {
            settings.currentItemRoundness = ExcalidrawStrokeSharpness(rawValue: roundness)
        }
        if let arrowTypeStr = dict["currentItemArrowType"] as? String {
            settings.currentItemArrowType = ArrowType(rawValue: arrowTypeStr)
        }

        // Handle arrowheads with proper null/undefined distinction
        // undefined (field not present) -> nil (Swift Optional)
        // null (field present but null) -> .null (Nullable enum)
        // value (field has value) -> .value(Arrowhead) (Nullable enum)
        if dict.keys.contains("currentItemStartArrowhead") {
            if let arrowheadStr = dict["currentItemStartArrowhead"] as? String,
               let arrowhead = Arrowhead(rawValue: arrowheadStr) {
                settings.currentItemStartArrowhead = .value(arrowhead)
            } else {
                // Explicit null from JavaScript
                settings.currentItemStartArrowhead = .null
            }
        }
        // else: field not present -> nil (undefined)

        if dict.keys.contains("currentItemEndArrowhead") {
            if let arrowheadStr = dict["currentItemEndArrowhead"] as? String,
               let arrowhead = Arrowhead(rawValue: arrowheadStr) {
                settings.currentItemEndArrowhead = .value(arrowhead)
            } else {
                // Explicit null from JavaScript
                settings.currentItemEndArrowhead = .null
            }
        }
        // else: field not present -> nil (undefined)

        return settings
    }

    private static func numberValue(_ value: Any?) -> Double? {
        switch value {
            case let value as Double:
                value
            case let value as Int:
                Double(value)
            case let value as NSNumber:
                value.doubleValue
            default:
                nil
        }
    }
}

extension UserDrawingSettings {
    /// Single source of truth for "what does this field look like when unset?".
    /// Both `DrawingSettingsPanel` (as `??` fallbacks) and `uiDefaults` reference
    /// these so the two stay in sync — drift here would silently break the
    /// canvas-vs-global comparison.
    enum Defaults {
        static let strokeWidthKey: StrokeWidthKey = .medium
        static let strokeWidth: Double = strokeWidthKey.strokeWidth
        static let strokeVariability: StrokeVariability = .constant
        static let strokeColor: String = "#1e1e1e"
        static let backgroundColor: String = "transparent"
        static let strokeStyle: ExcalidrawStrokeStyle = .solid
        static let fillStyle: ExcalidrawFillStyle = .solid
        static let roughness: Double = 1
        static let opacity: Double = 100
        static let fontFamily: FontFamily = .handDrawn
        static let fontSize: Double = 20
        static let textAlign: String = "left"
        static let roundness: ExcalidrawStrokeSharpness = .round
        static let arrowType: ArrowType = .sharp
        static let startArrowhead: Nullable<Arrowhead> = .null
        static let endArrowhead: Nullable<Arrowhead> = .value(.arrow)
    }

    /// Convenience: a fully-populated struct using `Defaults` for every field.
    /// Used by `matches(template:)` to fill nil fields before comparison.
    static let uiDefaults: UserDrawingSettings = {
        var s = UserDrawingSettings()
        s.currentItemStrokeWidthKey = Defaults.strokeWidthKey
        s.currentItemStrokeVariability = Defaults.strokeVariability
        s.currentItemStrokeColor = Defaults.strokeColor
        s.currentItemBackgroundColor = Defaults.backgroundColor
        s.currentItemStrokeStyle = Defaults.strokeStyle
        s.currentItemFillStyle = Defaults.fillStyle
        s.currentItemRoughness = Defaults.roughness
        s.currentItemOpacity = Defaults.opacity
        s.currentItemFontFamily = Defaults.fontFamily
        s.currentItemFontSize = Defaults.fontSize
        s.currentItemTextAlign = Defaults.textAlign
        s.currentItemRoundness = Defaults.roundness
        s.currentItemArrowType = Defaults.arrowType
        s.currentItemStartArrowhead = Defaults.startArrowhead
        s.currentItemEndArrowhead = Defaults.endArrowhead
        return s
    }()

    /// Returns a copy with nil fields filled in from `defaults`. Already-set fields
    /// are kept untouched (the inverse of `merging(template:)`).
    func filling(defaults: UserDrawingSettings) -> UserDrawingSettings {
        var result = self
        if result.currentItemStrokeWidthKey == nil { result.currentItemStrokeWidthKey = defaults.currentItemStrokeWidthKey }
        if result.currentItemStrokeVariability == nil { result.currentItemStrokeVariability = defaults.currentItemStrokeVariability }
        if result.currentItemStrokeColor == nil { result.currentItemStrokeColor = defaults.currentItemStrokeColor }
        if result.currentItemBackgroundColor == nil { result.currentItemBackgroundColor = defaults.currentItemBackgroundColor }
        if result.currentItemStrokeStyle == nil { result.currentItemStrokeStyle = defaults.currentItemStrokeStyle }
        if result.currentItemFillStyle == nil { result.currentItemFillStyle = defaults.currentItemFillStyle }
        if result.currentItemRoughness == nil { result.currentItemRoughness = defaults.currentItemRoughness }
        if result.currentItemOpacity == nil { result.currentItemOpacity = defaults.currentItemOpacity }
        if result.currentItemFontFamily == nil { result.currentItemFontFamily = defaults.currentItemFontFamily }
        if result.currentItemFontSize == nil { result.currentItemFontSize = defaults.currentItemFontSize }
        if result.currentItemTextAlign == nil { result.currentItemTextAlign = defaults.currentItemTextAlign }
        if result.currentItemRoundness == nil { result.currentItemRoundness = defaults.currentItemRoundness }
        if result.currentItemArrowType == nil { result.currentItemArrowType = defaults.currentItemArrowType }
        if result.currentItemStartArrowhead == nil { result.currentItemStartArrowhead = defaults.currentItemStartArrowhead }
        if result.currentItemEndArrowhead == nil { result.currentItemEndArrowhead = defaults.currentItemEndArrowhead }
        return result
    }

    /// Returns a copy where every non-nil field in `template` overrides this struct's
    /// value for that field; nil fields in the template are skipped (current value kept).
    /// Pairs with `matches(template:)` — `merging` is the action that makes `matches` true.
    func merging(template: UserDrawingSettings) -> UserDrawingSettings {
        var result = self
        if let v = template.currentItemStrokeWidthKey { result.currentItemStrokeWidthKey = v }
        if let v = template.currentItemStrokeVariability { result.currentItemStrokeVariability = v }
        if let v = template.currentItemStrokeColor { result.currentItemStrokeColor = v }
        if let v = template.currentItemBackgroundColor { result.currentItemBackgroundColor = v }
        if let v = template.currentItemStrokeStyle { result.currentItemStrokeStyle = v }
        if let v = template.currentItemFillStyle { result.currentItemFillStyle = v }
        if let v = template.currentItemRoughness { result.currentItemRoughness = v }
        if let v = template.currentItemOpacity { result.currentItemOpacity = v }
        if let v = template.currentItemFontFamily { result.currentItemFontFamily = v }
        if let v = template.currentItemFontSize { result.currentItemFontSize = v }
        if let v = template.currentItemTextAlign { result.currentItemTextAlign = v }
        if let v = template.currentItemRoundness { result.currentItemRoundness = v }
        if let v = template.currentItemArrowType { result.currentItemArrowType = v }
        if let v = template.currentItemStartArrowhead { result.currentItemStartArrowhead = v }
        if let v = template.currentItemEndArrowhead { result.currentItemEndArrowhead = v }
        return result
    }

    /// True iff the canvas's effective value equals the template's effective value
    /// for every field. Cascade is canvas → template → ui-defaults — a nil on the
    /// canvas inherits from the template, and a nil on the template inherits from
    /// the ui-defaults. Customization only happens when the canvas explicitly sets
    /// a value that disagrees with whatever the template ends up resolving to.
    func matches(template: UserDrawingSettings) -> Bool {
        let effectiveTemplate = template.filling(defaults: .uiDefaults)
        let effectiveSelf = self.filling(defaults: effectiveTemplate)
        return effectiveSelf == effectiveTemplate
    }
}

extension UserDrawingSettings {
    enum StrokeWidthKey: String, Codable {
        case thin
        case medium
        case bold

        var strokeWidth: Double {
            switch self {
                case .thin: 1
                case .medium: 2
                case .bold: 4
            }
        }

        init?(strokeWidth: Double) {
            switch strokeWidth {
                case 1: self = .thin
                case 2: self = .medium
                case 4: self = .bold
                default: return nil
            }
        }
    }

    enum StrokeVariability: String, Codable {
        case constant
        case variable
    }

    enum FontFamily: Int, Codable {
        case handDrawn = 5
        case normal = 6
        case code = 8
    }
    
    enum ArrowType: String, Codable {
        case sharp
        case round
        case elbow
    }
}
