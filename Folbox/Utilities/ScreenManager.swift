import AppKit

enum ScreenManager {
    static func center(_ window: NSWindow, preferMouseScreen: Bool = true) {
        guard preferMouseScreen, let screen = screenUnderMouse() else {
            window.center()
            return
        }

        let windowSize = window.frame.size
        guard windowSize.width > 0, windowSize.height > 0 else {
            window.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let originX = visibleFrame.midX - (windowSize.width / 2)
        let originY = visibleFrame.midY - (windowSize.height / 2)
        window.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    static func screenUnderMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
    }
}
