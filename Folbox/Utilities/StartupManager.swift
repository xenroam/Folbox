import Foundation
import ServiceManagement

final class StartupManager {
    static let shared = StartupManager()

    private init() {}

    func currentStatus() -> Bool? {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return nil
    }

    func setEnabled(_ enabled: Bool) -> Bool? {
        guard #available(macOS 13.0, *) else {
            return nil
        }

        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {}

        return SMAppService.mainApp.status == .enabled
    }
}
