import AppKit

final class EscapeClosableWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
