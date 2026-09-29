import Foundation
import SwiftUI

enum TitlePosition: String, CaseIterable, Codable, Identifiable {
    case top
    case bottom
    case left
    case right

    var id: String { rawValue }

    var isSide: Bool {
        self == .left || self == .right
    }

    var displayName: String {
        switch self {
        case .top:
            return AppLocalization.string("folbox.settings.option.title_top")
        case .bottom:
            return AppLocalization.string("folbox.settings.option.title_bottom")
        case .left:
            return AppLocalization.string("folbox.settings.option.title_left")
        case .right:
            return AppLocalization.string("folbox.settings.option.title_right")
        }
    }
}

struct FileShortcut: Codable, Equatable {
    var keyCode: Int
    var modifierFlagsRaw: UInt64

    static let disabled = FileShortcut(
        keyCode: Int(UInt16.max),
        modifierFlagsRaw: 0
    )

    var isConfigured: Bool {
        keyCode != Int(UInt16.max) && modifierFlagsRaw != 0
    }
}

struct ComponentInstance: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var storageFolderName: String?
    var styleColorHex: String
    var customCollapsedColumns: Int?
    var filePaths: [String]
    var appBookmarksByPath: [String: Data]
    var fileShortcutsByPath: [String: FileShortcut]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        name: String,
        storageFolderName: String? = nil,
        styleColorHex: String,
        customCollapsedColumns: Int? = nil,
        filePaths: [String] = [],
        appBookmarksByPath: [String: Data] = [:],
        fileShortcutsByPath: [String: FileShortcut] = [:],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.storageFolderName = storageFolderName
        self.styleColorHex = styleColorHex
        self.customCollapsedColumns = customCollapsedColumns
        self.filePaths = filePaths
        self.appBookmarksByPath = appBookmarksByPath
        self.fileShortcutsByPath = fileShortcutsByPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case storageFolderName
        case styleColorHex
        case customCollapsedColumns
        case filePaths
        case appBookmarksByPath
        case fileShortcutsByPath
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        storageFolderName = try container.decodeIfPresent(String.self, forKey: .storageFolderName)
        styleColorHex = try container.decodeIfPresent(String.self, forKey: .styleColorHex) ?? AppDefaults.Component.styleColorHex
        customCollapsedColumns = try container.decodeIfPresent(Int.self, forKey: .customCollapsedColumns)
        filePaths = try container.decodeIfPresent([String].self, forKey: .filePaths) ?? []
        appBookmarksByPath = try container.decodeIfPresent([String: Data].self, forKey: .appBookmarksByPath) ?? [:]
        fileShortcutsByPath = try container.decodeIfPresent([String: FileShortcut].self, forKey: .fileShortcutsByPath) ?? [:]
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(storageFolderName, forKey: .storageFolderName)
        try container.encode(styleColorHex, forKey: .styleColorHex)
        try container.encodeIfPresent(customCollapsedColumns, forKey: .customCollapsedColumns)
        try container.encode(filePaths, forKey: .filePaths)
        try container.encode(appBookmarksByPath, forKey: .appBookmarksByPath)
        try container.encode(fileShortcutsByPath, forKey: .fileShortcutsByPath)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var fileURLs: [URL] {
        filePaths.map { URL(fileURLWithPath: $0) }
    }

    func resolvedCollapsedColumns(globalColumns: Int) -> Int {
        GridMetrics.clamp(customCollapsedColumns ?? globalColumns)
    }
}

enum GridMetrics {
    static let defaultTileSize = 84
    static let minimumTileSize = 64
    static let maximumTileSize = 128
    static let tileHeightRatio: CGFloat = 78.0 / 84.0
    static let spacing: CGFloat = 8
    static let minimumCount = 1
    static let maximumCount = 10
    static let panelPadding: CGFloat = 40
    static let titleBarThickness: CGFloat = 34

    static func tileWidth(for size: Int) -> CGFloat {
        CGFloat(clampTileSize(size))
    }

    static func tileHeight(for size: Int) -> CGFloat {
        tileWidth(for: size) * tileHeightRatio
    }

    static func panelCornerRadius(for size: Int) -> CGFloat {
        adaptiveValue(for: size, minimum: 8, maximum: 14)
    }

    static func fileNameFontSize(for size: Int) -> CGFloat {
        adaptiveValue(for: size, minimum: 9, maximum: 12)
    }

    static func panelTitleFontSize(for size: Int) -> CGFloat {
        fileNameFontSize(for: size)
    }

    static func shortcutBadgeFontSize(for size: Int) -> CGFloat {
        adaptiveValue(for: size, minimum: 9, maximum: 14)
    }

    static func shortcutBadgeEdgePadding(for size: Int) -> CGFloat {
        adaptiveValue(for: size, minimum: 2, maximum: 8)
    }

    static func thumbnailSize(for size: Int) -> CGFloat {
        adaptiveValue(for: size, minimum: 30, maximum: 62)
    }

    static func fileLabelSpacing(for size: Int) -> CGFloat {
        adaptiveValue(for: size, minimum: 2, maximum: 10)
    }

    static func tileContentPadding(for size: Int) -> CGFloat {
        adaptiveValue(for: size, minimum: 3, maximum: 6)
    }

    private static func adaptiveValue(for size: Int, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        let clampedSize = CGFloat(clampTileSize(size))
        let minSize = CGFloat(minimumTileSize)
        let maxSize = CGFloat(maximumTileSize)
        guard maxSize > minSize else { return minimum }
        let progress = (clampedSize - minSize) / (maxSize - minSize)
        return minimum + (maximum - minimum) * progress
    }

    static func clampTileSize(_ value: Int) -> Int {
        min(max(value, minimumTileSize), maximumTileSize)
    }

    static func clamp(_ value: Int) -> Int {
        min(max(value, minimumCount), maximumCount)
    }

    static func visibleSlotCount(fileCount: Int, columns: Int) -> Int {
        min(max(fileCount, 1), clamp(columns))
    }

    static func visibleRowCount(fileCount: Int, columns: Int, maxRows: Int) -> Int {
        let columnCount = clamp(columns)
        let needed = Int(ceil(Double(max(fileCount, 1)) / Double(columnCount)))
        return min(max(needed, 1), clamp(maxRows))
    }
}

extension Color {
    init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard value.count == 6, let intValue = Int(value, radix: 16) else {
            return nil
        }

        let red = Double((intValue >> 16) & 0xFF) / 255.0
        let green = Double((intValue >> 8) & 0xFF) / 255.0
        let blue = Double(intValue & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }

    var hexString: String {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else {
            return AppDefaults.Component.styleColorHex
        }

        let red = Int(round(components.redComponent * 255))
        let green = Int(round(components.greenComponent * 255))
        let blue = Int(round(components.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

enum ColorPresets {
    static let accentColors: [String] = [
        "#FF4444",
        "#FF8C00",
        "#FFD700",
        "#7FFF00",
        "#00FA9A",
        "#00CED1",
        "#1E90FF",
        "#4169E1",
        "#8A2BE2",
        "#9370DB",
        "#FF1493",
        "#FF69B4",
        "#DC143C",
        "#FF6347",
        "#32CD32",
        "#20B2AA",
        "#4682B4",
        "#6A5ACD",
        "#BA55D3",
        "#C71585"
    ]
}

enum ComponentConfigurationMode {
    case create
    case edit
}
