import Foundation
import CoreGraphics

enum AppDefaults {
    enum Settings {
        static let language: AppLanguage = .system
        static let launchAtLogin = false
        static let panelShortcutKeyCode = Int(UInt16.max)
        static let panelShortcutModifierFlagsRaw: UInt64 = CGEventFlags.disabled.rawValue
        static let singleClickOpensFile = false
        static let panelAnimationDuration = 0.2
        static let panelAnimationDurationRange: ClosedRange<Double> = 0.1...0.5
        static let useCustomStorageLocation = false
        static let autoMoveDesktopFilesToStorage = false

        static let titlePosition: TitlePosition = .top
        static let fileListDisplayMode: FileListDisplayMode = .horizontal
        static let panelExpandDirection: PanelExpandDirection = .left
        static let panelScrollMode: PanelScrollMode = .scrollDownExpands
        static let gridColumns = 4
        static let expandedColumns = 4
        static let gridRows = 4
        static var fileTileSize: Int { GridMetrics.defaultTileSize }

        static let collapsedBackgroundOpacity = 0.0
        static let expandedBackgroundOpacity = 0.5
        static let componentOpacity = 1.0
        static let opacityRange: ClosedRange<Double> = 0.0...1.0
        static let panelBlurIntensity = 1.0
        static let showFileTileBorder = true
    }

    enum Component {
        static let styleColorHex = "#000000"
    }

    enum AppInfo {
        static let donateURLString = "https://xenroam.github.io/Donate/"
        static let appcastURLString = "https://xenroam.github.io/Folbox/appcast.xml"
        static let configURLString = "https://xenroam.github.io/Folbox/folbox.json"

        static func projectName() -> String {
            infoString(for: "CFBundleDisplayName")
                ?? infoString(for: "CFBundleName")
                ?? ProcessInfo.processInfo.processName
        }

        static func projectVersion() -> String {
            infoString(for: "CFBundleShortVersionString") ?? "1.0"
        }

        static func projectBuildNumber() -> String {
            infoString(for: "CFBundleVersion") ?? "1"
        }

        static func nameAndVersion() -> String {
            "\(projectName()) \(projectVersion())"
        }

        static func nameVersionAndBuild() -> String {
            "\(projectName()) \(projectVersion()) (\(projectBuildNumber()))"
        }

        static func versionAndBuild() -> String {
            AppLocalization.string("folbox.about.version_build", projectVersion(), projectBuildNumber())
        }

        private static func infoString(for key: String) -> String? {
            guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
                return nil
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}
