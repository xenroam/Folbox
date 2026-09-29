import AppKit

#if canImport(Sparkle)
import Sparkle
#endif

final class UpdateManager: NSObject {
    static let shared = UpdateManager()

    #if canImport(Sparkle)
    private let updaterController: SPUStandardUpdaterController
    #endif

    private override init() {
        #if canImport(Sparkle)
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
        super.init()
    }

    func checkForUpdates() {
        DispatchQueue.main.async {
            #if canImport(Sparkle)
            NSRunningApplication.current.activate(options: [])
            NSApp.activate(ignoringOtherApps: false)
            self.updaterController.checkForUpdates(nil)
            #else
            let alert = NSAlert()
            alert.messageText = AppLocalization.string("folbox.update.unavailable_title")
            alert.informativeText = AppLocalization.string("folbox.update.unavailable_message")
            alert.addButton(withTitle: AppLocalization.string("folbox.common.ok"))
            alert.runModal()
            #endif
        }
    }
}