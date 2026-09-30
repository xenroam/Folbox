import Foundation
import Combine
import CoreGraphics

@MainActor
final class SettingsStore: ObservableObject {
    static let languageDidChangeNotification = Notification.Name("folbox.languageDidChange")

    private enum Keys {
        static let useCustomStorageLocation = "app.useCustomStorageLocation"
        static let customStorageBookmark = "app.customStorageBookmark"
    }

    private struct PersistedSettings: Codable {
        var language: String
        var launchAtLogin: Bool
        var singleClickOpensFile: Bool
        var panelShortcutKeyCode: Int
        var panelShortcutModifierFlagsRaw: UInt64
        var gridColumns: Int
        var gridRows: Int
        var expandedColumns: Int
        var fileTileSize: Int
        var titlePosition: String
        var panelExpandDirection: String
        var panelAnimationDuration: Double
        var panelScrollMode: String
        var fileListDisplayMode: String
        var collapsedBackgroundOpacity: Double
        var expandedBackgroundOpacity: Double
        var componentOpacity: Double
        var panelBlurIntensity: Double
        var showFileTileBorder: Bool

        private enum CodingKeys: String, CodingKey {
            case language, launchAtLogin, singleClickOpensFile
            case panelShortcutKeyCode, panelShortcutModifierFlagsRaw
            case gridColumns, gridRows, expandedColumns, fileTileSize
            case titlePosition, panelExpandDirection, panelAnimationDuration, panelScrollMode, fileListDisplayMode
            case collapsedBackgroundOpacity, expandedBackgroundOpacity, componentOpacity
            case panelBlurIntensity, showFileTileBorder
        }

        init(
            language: String,
            launchAtLogin: Bool,
            singleClickOpensFile: Bool,
            panelShortcutKeyCode: Int,
            panelShortcutModifierFlagsRaw: UInt64,
            gridColumns: Int,
            gridRows: Int,
            expandedColumns: Int,
            fileTileSize: Int,
            titlePosition: String,
            panelExpandDirection: String,
            panelAnimationDuration: Double,
            panelScrollMode: String,
            fileListDisplayMode: String,
            collapsedBackgroundOpacity: Double,
            expandedBackgroundOpacity: Double,
            componentOpacity: Double,
            panelBlurIntensity: Double,
            showFileTileBorder: Bool
        ) {
            self.language = language
            self.launchAtLogin = launchAtLogin
            self.singleClickOpensFile = singleClickOpensFile
            self.panelShortcutKeyCode = panelShortcutKeyCode
            self.panelShortcutModifierFlagsRaw = panelShortcutModifierFlagsRaw
            self.gridColumns = gridColumns
            self.gridRows = gridRows
            self.expandedColumns = expandedColumns
            self.fileTileSize = fileTileSize
            self.titlePosition = titlePosition
            self.panelExpandDirection = panelExpandDirection
            self.panelAnimationDuration = panelAnimationDuration
            self.panelScrollMode = panelScrollMode
            self.fileListDisplayMode = fileListDisplayMode
            self.collapsedBackgroundOpacity = collapsedBackgroundOpacity
            self.expandedBackgroundOpacity = expandedBackgroundOpacity
            self.componentOpacity = componentOpacity
            self.panelBlurIntensity = panelBlurIntensity
            self.showFileTileBorder = showFileTileBorder
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            language = try container.decode(String.self, forKey: .language)
            launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
            singleClickOpensFile = try container.decodeIfPresent(Bool.self, forKey: .singleClickOpensFile) ?? AppDefaults.Settings.singleClickOpensFile
            panelShortcutKeyCode = try container.decodeIfPresent(Int.self, forKey: .panelShortcutKeyCode) ?? AppDefaults.Settings.panelShortcutKeyCode
            panelShortcutModifierFlagsRaw = try container.decodeIfPresent(UInt64.self, forKey: .panelShortcutModifierFlagsRaw) ?? AppDefaults.Settings.panelShortcutModifierFlagsRaw
            gridColumns = try container.decode(Int.self, forKey: .gridColumns)
            gridRows = try container.decode(Int.self, forKey: .gridRows)
            expandedColumns = try container.decode(Int.self, forKey: .expandedColumns)
            fileTileSize = try container.decodeIfPresent(Int.self, forKey: .fileTileSize) ?? AppDefaults.Settings.fileTileSize
            titlePosition = try container.decode(String.self, forKey: .titlePosition)
            panelExpandDirection = try container.decode(String.self, forKey: .panelExpandDirection)
            panelAnimationDuration = try container.decode(Double.self, forKey: .panelAnimationDuration)
            panelScrollMode = try container.decode(String.self, forKey: .panelScrollMode)
            fileListDisplayMode = try container.decodeIfPresent(String.self, forKey: .fileListDisplayMode) ?? AppDefaults.Settings.fileListDisplayMode.rawValue

            collapsedBackgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .collapsedBackgroundOpacity) ?? AppDefaults.Settings.collapsedBackgroundOpacity
            expandedBackgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .expandedBackgroundOpacity) ?? AppDefaults.Settings.expandedBackgroundOpacity
            componentOpacity = try container.decodeIfPresent(Double.self, forKey: .componentOpacity) ?? AppDefaults.Settings.componentOpacity

            panelBlurIntensity = try container.decode(Double.self, forKey: .panelBlurIntensity)
            showFileTileBorder = try container.decodeIfPresent(Bool.self, forKey: .showFileTileBorder) ?? AppDefaults.Settings.showFileTileBorder
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(language, forKey: .language)
            try container.encode(launchAtLogin, forKey: .launchAtLogin)
            try container.encode(singleClickOpensFile, forKey: .singleClickOpensFile)
            try container.encode(panelShortcutKeyCode, forKey: .panelShortcutKeyCode)
            try container.encode(panelShortcutModifierFlagsRaw, forKey: .panelShortcutModifierFlagsRaw)
            try container.encode(gridColumns, forKey: .gridColumns)
            try container.encode(gridRows, forKey: .gridRows)
            try container.encode(expandedColumns, forKey: .expandedColumns)
            try container.encode(fileTileSize, forKey: .fileTileSize)
            try container.encode(titlePosition, forKey: .titlePosition)
            try container.encode(panelExpandDirection, forKey: .panelExpandDirection)
            try container.encode(panelAnimationDuration, forKey: .panelAnimationDuration)
            try container.encode(panelScrollMode, forKey: .panelScrollMode)
            try container.encode(fileListDisplayMode, forKey: .fileListDisplayMode)
            try container.encode(collapsedBackgroundOpacity, forKey: .collapsedBackgroundOpacity)
            try container.encode(expandedBackgroundOpacity, forKey: .expandedBackgroundOpacity)
            try container.encode(componentOpacity, forKey: .componentOpacity)
            try container.encode(panelBlurIntensity, forKey: .panelBlurIntensity)
            try container.encode(showFileTileBorder, forKey: .showFileTileBorder)
        }
    }

    static let shared = SettingsStore()

    private let defaults: UserDefaults
    private var accessedSecurityScopedURLs: Set<URL> = []
    private var isApplyingPersistedSettings = false

    @Published var language: AppLanguage {
        didSet {
            guard oldValue != language else { return }
            persistSettingsJSON()
            NotificationCenter.default.post(name: Self.languageDidChangeNotification, object: nil)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet { persistSettingsJSON() }
    }

    @Published var singleClickOpensFile: Bool {
        didSet { persistSettingsJSON() }
    }

    @Published var panelShortcutKeyCode: Int {
        didSet {
            if panelShortcutKeyCode < 0 || panelShortcutKeyCode > Int(UInt16.max) {
                panelShortcutKeyCode = AppDefaults.Settings.panelShortcutKeyCode
                return
            }
            persistSettingsJSON()
        }
    }

    @Published var panelShortcutModifierFlagsRaw: UInt64 {
        didSet {
            let normalized = normalizedShortcutModifierFlagsRaw(panelShortcutModifierFlagsRaw)
            if panelShortcutModifierFlagsRaw != normalized {
                panelShortcutModifierFlagsRaw = normalized
                return
            }
            persistSettingsJSON()
        }
    }

    @Published var gridColumns: Int {
        didSet {
            let clamped = GridMetrics.clamp(gridColumns)
            if clamped != gridColumns {
                gridColumns = clamped
                return
            }
            persistSettingsJSON()
        }
    }

    @Published var gridRows: Int {
        didSet {
            let clamped = GridMetrics.clamp(gridRows)
            if clamped != gridRows {
                gridRows = clamped
                return
            }
            persistSettingsJSON()
        }
    }

    @Published var expandedColumns: Int {
        didSet {
            let clamped = GridMetrics.clamp(expandedColumns)
            if clamped != expandedColumns {
                expandedColumns = clamped
                return
            }
            persistSettingsJSON()
        }
    }

    @Published var fileTileSize: Int {
        didSet {
            let clamped = GridMetrics.clampTileSize(fileTileSize)
            if clamped != fileTileSize {
                fileTileSize = clamped
                return
            }
            persistSettingsJSON()
        }
    }

    @Published var panelExpandDirection: PanelExpandDirection {
        didSet { persistSettingsJSON() }
    }

    @Published var titlePosition: TitlePosition {
        didSet { persistSettingsJSON() }
    }

    @Published var panelAnimationDuration: Double {
        didSet {
            let clamped = min(max(panelAnimationDuration, AppDefaults.Settings.panelAnimationDurationRange.lowerBound), AppDefaults.Settings.panelAnimationDurationRange.upperBound)
            if clamped != panelAnimationDuration {
                panelAnimationDuration = clamped
                return
            }
            persistSettingsJSON()
        }
    }

    @Published var panelScrollMode: PanelScrollMode {
        didSet { persistSettingsJSON() }
    }

    @Published var fileListDisplayMode: FileListDisplayMode {
        didSet { persistSettingsJSON() }
    }

    @Published var collapsedBackgroundOpacity: Double {
        didSet {
            let clamped = min(max(collapsedBackgroundOpacity, AppDefaults.Settings.opacityRange.lowerBound), AppDefaults.Settings.opacityRange.upperBound)
            if clamped != collapsedBackgroundOpacity {
                collapsedBackgroundOpacity = clamped
                return
            }
            if expandedBackgroundOpacity < collapsedBackgroundOpacity {
                expandedBackgroundOpacity = collapsedBackgroundOpacity
            }
            persistSettingsJSON()
        }
    }

    @Published var expandedBackgroundOpacity: Double {
        didSet {
            let clamped = min(max(expandedBackgroundOpacity, collapsedBackgroundOpacity), AppDefaults.Settings.opacityRange.upperBound)
            if clamped != expandedBackgroundOpacity {
                expandedBackgroundOpacity = clamped
                return
            }
            persistSettingsJSON()
        }
    }

    @Published var componentOpacity: Double {
        didSet {
            let clamped = min(max(componentOpacity, AppDefaults.Settings.opacityRange.lowerBound), AppDefaults.Settings.opacityRange.upperBound)
            if clamped != componentOpacity {
                componentOpacity = clamped
                return
            }
            persistSettingsJSON()
        }
    }

    @Published var panelBlurIntensity: Double {
        didSet {
            let clamped = min(max(panelBlurIntensity, AppDefaults.Settings.opacityRange.lowerBound), AppDefaults.Settings.opacityRange.upperBound)
            if clamped != panelBlurIntensity {
                panelBlurIntensity = clamped
                return
            }
            persistSettingsJSON()
        }
    }

    @Published var showFileTileBorder: Bool {
        didSet { persistSettingsJSON() }
    }

    @Published var useCustomStorageLocation: Bool {
        didSet { defaults.set(useCustomStorageLocation, forKey: Keys.useCustomStorageLocation) }
    }

    @Published private(set) var customStorageDisplayPath: String?

    private var customStorageBookmarkData: Data? {
        didSet { defaults.set(customStorageBookmarkData, forKey: Keys.customStorageBookmark) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppDefaults.Settings.language
        launchAtLogin = AppDefaults.Settings.launchAtLogin
        singleClickOpensFile = AppDefaults.Settings.singleClickOpensFile
        panelShortcutKeyCode = AppDefaults.Settings.panelShortcutKeyCode
        panelShortcutModifierFlagsRaw = AppDefaults.Settings.panelShortcutModifierFlagsRaw
        gridColumns = AppDefaults.Settings.gridColumns
        gridRows = AppDefaults.Settings.gridRows
        expandedColumns = AppDefaults.Settings.expandedColumns
        fileTileSize = AppDefaults.Settings.fileTileSize
        titlePosition = AppDefaults.Settings.titlePosition
        panelExpandDirection = AppDefaults.Settings.panelExpandDirection
        panelAnimationDuration = AppDefaults.Settings.panelAnimationDuration
        panelScrollMode = AppDefaults.Settings.panelScrollMode
        fileListDisplayMode = AppDefaults.Settings.fileListDisplayMode
        collapsedBackgroundOpacity = AppDefaults.Settings.collapsedBackgroundOpacity
        expandedBackgroundOpacity = AppDefaults.Settings.expandedBackgroundOpacity
        componentOpacity = AppDefaults.Settings.componentOpacity
        panelBlurIntensity = AppDefaults.Settings.panelBlurIntensity
        showFileTileBorder = AppDefaults.Settings.showFileTileBorder
        useCustomStorageLocation = AppDefaults.Settings.useCustomStorageLocation
        customStorageBookmarkData = nil

        restoreBootstrapSettings()
        customStorageDisplayPath = resolvedCustomStorageURL()?.path

        loadSettings()
        refreshLaunchAtLoginStatus()
    }

    func refreshLaunchAtLoginStatus() {
        guard let status = StartupManager.shared.currentStatus() else {
            return
        }
        if launchAtLogin != status {
            launchAtLogin = status
        }
    }

    @discardableResult
    func setLaunchAtLoginEnabled(_ enabled: Bool) -> Bool {
        guard let status = StartupManager.shared.setEnabled(enabled) else {
            if launchAtLogin != enabled {
                launchAtLogin = enabled
            }
            return launchAtLogin
        }
        if launchAtLogin != status {
            launchAtLogin = status
        }
        return launchAtLogin
    }

    private func restoreBootstrapSettings() {
        if defaults.object(forKey: Keys.useCustomStorageLocation) != nil {
            useCustomStorageLocation = defaults.bool(forKey: Keys.useCustomStorageLocation)
        }

        customStorageBookmarkData = defaults.data(forKey: Keys.customStorageBookmark)
    }

    private func loadSettings() {
        ensureSettingsDirectory()

        if let payload = readSettingsJSON() {
            apply(payload)
            return
        }
        persistSettingsJSON()
    }

    private var settingsFileURL: URL {
        StorageLocation.rootDirectoryURL(customURL: resolvedCustomStorageURL()).appendingPathComponent("settings.json")
    }

    private func ensureSettingsDirectory() {
        let root = StorageLocation.rootDirectoryURL(customURL: resolvedCustomStorageURL())
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func readSettingsJSON() -> PersistedSettings? {
        guard let data = try? Data(contentsOf: settingsFileURL) else { return nil }
        return try? JSONDecoder().decode(PersistedSettings.self, from: data)
    }

    private func persistSettingsJSON() {
        guard !isApplyingPersistedSettings else { return }

        let payload = PersistedSettings(
            language: language.rawValue,
            launchAtLogin: launchAtLogin,
            singleClickOpensFile: singleClickOpensFile,
            panelShortcutKeyCode: panelShortcutKeyCode,
            panelShortcutModifierFlagsRaw: panelShortcutModifierFlagsRaw,
            gridColumns: gridColumns,
            gridRows: gridRows,
            expandedColumns: expandedColumns,
            fileTileSize: fileTileSize,
            titlePosition: titlePosition.rawValue,
            panelExpandDirection: panelExpandDirection.rawValue,
            panelAnimationDuration: panelAnimationDuration,
            panelScrollMode: panelScrollMode.rawValue,
            fileListDisplayMode: fileListDisplayMode.rawValue,
            collapsedBackgroundOpacity: collapsedBackgroundOpacity,
            expandedBackgroundOpacity: expandedBackgroundOpacity,
            componentOpacity: componentOpacity,
            panelBlurIntensity: panelBlurIntensity,
            showFileTileBorder: showFileTileBorder
        )

        guard let data = try? JSONEncoder().encode(payload) else { return }
        ensureSettingsDirectory()
        try? data.write(to: settingsFileURL, options: .atomic)
    }

    private func apply(_ payload: PersistedSettings) {
        isApplyingPersistedSettings = true
        defer { isApplyingPersistedSettings = false }

        if let value = AppLanguage(rawValue: payload.language) {
            language = value
        }
        launchAtLogin = payload.launchAtLogin
        singleClickOpensFile = payload.singleClickOpensFile
        panelShortcutKeyCode = payload.panelShortcutKeyCode
        panelShortcutModifierFlagsRaw = normalizedShortcutModifierFlagsRaw(payload.panelShortcutModifierFlagsRaw)
        gridColumns = GridMetrics.clamp(payload.gridColumns)
        gridRows = GridMetrics.clamp(payload.gridRows)
        expandedColumns = GridMetrics.clamp(payload.expandedColumns)
        fileTileSize = GridMetrics.clampTileSize(payload.fileTileSize)
        if let value = TitlePosition(rawValue: payload.titlePosition) {
            titlePosition = value
        }
        if let value = PanelExpandDirection(rawValue: payload.panelExpandDirection) {
            panelExpandDirection = value
        }
        panelAnimationDuration = min(max(payload.panelAnimationDuration, AppDefaults.Settings.panelAnimationDurationRange.lowerBound), AppDefaults.Settings.panelAnimationDurationRange.upperBound)
        if let value = PanelScrollMode(rawValue: payload.panelScrollMode) {
            panelScrollMode = value
        }
        if let value = FileListDisplayMode(rawValue: payload.fileListDisplayMode) {
            fileListDisplayMode = value
        }
        collapsedBackgroundOpacity = min(max(payload.collapsedBackgroundOpacity, AppDefaults.Settings.opacityRange.lowerBound), AppDefaults.Settings.opacityRange.upperBound)
        expandedBackgroundOpacity = min(max(payload.expandedBackgroundOpacity, collapsedBackgroundOpacity), AppDefaults.Settings.opacityRange.upperBound)
        componentOpacity = min(max(payload.componentOpacity, AppDefaults.Settings.opacityRange.lowerBound), AppDefaults.Settings.opacityRange.upperBound)
        panelBlurIntensity = min(max(payload.panelBlurIntensity, AppDefaults.Settings.opacityRange.lowerBound), AppDefaults.Settings.opacityRange.upperBound)
        showFileTileBorder = payload.showFileTileBorder
    }

    private func normalizedShortcutModifierFlagsRaw(_ rawValue: UInt64) -> UInt64 {
        let rawFlags = CGEventFlags(rawValue: rawValue)
        let normalized = rawFlags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        return normalized.rawValue
    }

    private func reconcileSettingsStorage() {
        ensureSettingsDirectory()
        if let payload = readSettingsJSON() {
            apply(payload)
        } else {
            persistSettingsJSON()
        }
    }

    func resolvedCustomStorageURL() -> URL? {
        guard useCustomStorageLocation, let bookmarkData = customStorageBookmarkData else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }

        if !accessedSecurityScopedURLs.contains(url) {
            if url.startAccessingSecurityScopedResource() {
                accessedSecurityScopedURLs.insert(url)
            }
        }

        if isStale {
            customStorageBookmarkData = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        }

        return url
    }

    @discardableResult
    func setCustomStorageURL(_ url: URL) -> Bool {
        guard let bookmarkData = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return false
        }

        customStorageBookmarkData = bookmarkData
        useCustomStorageLocation = true
        customStorageDisplayPath = resolvedCustomStorageURL()?.path
        reconcileSettingsStorage()
        DesktopAutoMoveStore.shared.refreshServiceDestination(triggerImmediateScan: true)
        return true
    }

    func clearCustomStorageLocation() {
        useCustomStorageLocation = false
        customStorageBookmarkData = nil
        customStorageDisplayPath = nil
        reconcileSettingsStorage()
        DesktopAutoMoveStore.shared.refreshServiceDestination(triggerImmediateScan: true)
    }
}

enum PanelScrollMode: String, CaseIterable, Identifiable {
    case scrollDownExpands
    case scrollUpExpands

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .scrollDownExpands:
            return AppLocalization.string("folbox.settings.option.scroll_down_expands")
        case .scrollUpExpands:
            return AppLocalization.string("folbox.settings.option.scroll_up_expands")
        }
    }
}

enum PanelExpandDirection: String, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left:
            return AppLocalization.string("folbox.settings.option.expand_left")
        case .right:
            return AppLocalization.string("folbox.settings.option.expand_right")
        }
    }
}

enum FileListDisplayMode: String, CaseIterable, Identifiable {
    case horizontal
    case vertical

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .horizontal:
            return AppLocalization.string("folbox.settings.option.horizontal")
        case .vertical:
            return AppLocalization.string("folbox.settings.option.vertical")
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case chineseSimplified
    case chineseTraditional

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return AppLocalization.string("folbox.settings.option.language_system")
        case .english:
            return AppLocalization.string("folbox.settings.option.language_english")
        case .chineseSimplified:
            return AppLocalization.string("folbox.settings.option.language_chinese_simplified")
        case .chineseTraditional:
            return AppLocalization.string("folbox.settings.option.language_chinese_traditional")
        }
    }
}
