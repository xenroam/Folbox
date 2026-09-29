import Foundation

enum AppLocalization {
    private static let tableName = "Localizable"

    static func string(_ key: String, language: AppLanguage, _ arguments: CVarArg...) -> String {
        string(key, language: language, arguments: arguments)
    }

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        string(key, language: SettingsStore.shared.language, arguments: arguments)
    }

    static func string(_ key: String, language: AppLanguage, arguments: [CVarArg]) -> String {
        let format = localizedFormat(for: key, language: language)
        guard !arguments.isEmpty else {
            return format
        }
        return String(format: format, locale: Locale.current, arguments: arguments)
    }

    private static func localizedFormat(for key: String, language: AppLanguage) -> String {
        let primary = bundle(for: language)
        let localized = primary.localizedString(forKey: key, value: nil, table: tableName)
        if localized != key {
            return localized
        }

        let english = bundle(forLanguageCode: "en") ?? Bundle.main
        let fallback = english.localizedString(forKey: key, value: nil, table: tableName)
        if fallback != key {
            return fallback
        }

        return key
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        switch language {
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return bundle(forLanguageCode: preferred)
                ?? bundle(forLanguageCode: "en")
                ?? Bundle.main
        case .english:
            return bundle(forLanguageCode: "en")
                ?? Bundle.main
        case .chineseSimplified:
            return bundle(forLanguageCode: "zh-Hans")
                ?? bundle(forLanguageCode: "zh")
                ?? bundle(forLanguageCode: "en")
                ?? Bundle.main
        case .chineseTraditional:
            return bundle(forLanguageCode: "zh-Hant")
                ?? bundle(forLanguageCode: "zh")
                ?? bundle(forLanguageCode: "en")
                ?? Bundle.main
        }
    }

    private static func bundle(forLanguageCode code: String) -> Bundle? {
        let candidates = languageCandidates(for: code)
        for candidate in candidates {
            if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return nil
    }

    private static func languageCandidates(for code: String) -> [String] {
        let normalized = code.replacingOccurrences(of: "_", with: "-")
        var result: [String] = []

        if normalized.lowercased().hasPrefix("zh-hans") {
            result.append("zh-Hans")
            result.append("zh")
        } else if normalized.lowercased().hasPrefix("zh-hant") {
            result.append("zh-Hant")
            result.append("zh")
        } else if normalized.lowercased().hasPrefix("zh") {
            result.append("zh-Hans")
            result.append("zh-Hant")
            result.append("zh")
        } else if normalized.lowercased().hasPrefix("en") {
            result.append("en")
        } else {
            result.append(normalized)
            if let base = normalized.split(separator: "-").first {
                result.append(String(base))
            }
            result.append("en")
        }

        if !result.contains("Base") {
            result.append("Base")
        }

        return result
    }
}

extension SettingsStore {
    func t(_ key: String, _ arguments: CVarArg...) -> String {
        AppLocalization.string(key, language: language, arguments: arguments)
    }
}
