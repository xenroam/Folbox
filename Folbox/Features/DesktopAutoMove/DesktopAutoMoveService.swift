import Foundation
import CoreServices

@MainActor
final class DesktopAutoMoveService {
    static let shared = DesktopAutoMoveService()

    private let fileManager = FileManager.default
    private let eventQueue = DispatchQueue(label: "Folbox.DesktopAutoMoveService")
    private var stream: FSEventStreamRef?
    private var watchedDesktopURL: URL?
    private var destinationRootURL: URL?
    private var pendingScanWorkItem: DispatchWorkItem?
    private var isEnabled = false

    private init() {}

    func setEnabled(_ enabled: Bool, destinationURL: URL?, desktopURL: URL?) {
        guard isEnabled != enabled else {
            if enabled {
                refreshConfiguration(destinationURL: destinationURL, desktopURL: desktopURL, triggerImmediateScan: false)
            }
            return
        }

        isEnabled = enabled

        if enabled {
            refreshConfiguration(destinationURL: destinationURL, desktopURL: desktopURL, triggerImmediateScan: true)
        } else {
            stopMonitoring(clearDestination: true)
        }
    }

    func refreshConfiguration(destinationURL: URL?, desktopURL: URL?, triggerImmediateScan: Bool) {
        guard isEnabled else {
            return
        }

        destinationRootURL = destinationURL?.standardizedFileURL

        guard let desktopURL = desktopURL?.standardizedFileURL else {
            stopMonitoring(clearDestination: false)
            return
        }

        startMonitoringDesktop(desktopURL: desktopURL)

        if triggerImmediateScan {
            scheduleDesktopScan(delay: 0.2)
        }
    }

    private func startMonitoringDesktop(desktopURL: URL) {
        if watchedDesktopURL == desktopURL, stream != nil {
            return
        }

        stopMonitoring(clearDestination: false)
        watchedDesktopURL = desktopURL

        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let service = Unmanaged<DesktopAutoMoveService>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in
                service.handleDesktopEvent()
            }
        }

        guard let newStream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [desktopURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1,
            flags
        ) else {
            watchedDesktopURL = nil
            return
        }

        FSEventStreamSetDispatchQueue(newStream, eventQueue)

        guard FSEventStreamStart(newStream) else {
            FSEventStreamInvalidate(newStream)
            FSEventStreamRelease(newStream)
            watchedDesktopURL = nil
            return
        }

        stream = newStream
    }

    private func stopMonitoring(clearDestination: Bool) {
        pendingScanWorkItem?.cancel()
        pendingScanWorkItem = nil

        if clearDestination {
            destinationRootURL = nil
        }

        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }

        watchedDesktopURL = nil
    }

    private func handleDesktopEvent() {
        guard isEnabled else {
            return
        }

        scheduleDesktopScan(delay: 0.1)
    }

    private func scheduleDesktopScan(delay: TimeInterval) {
        pendingScanWorkItem?.cancel()

        guard isEnabled, let watchedDesktopURL, let destinationRootURL else {
            return
        }

        let workItem = DispatchWorkItem {
            Self.moveVisibleItemsFromDesktop(from: watchedDesktopURL, to: destinationRootURL)
        }

        pendingScanWorkItem = workItem
        eventQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private static func moveVisibleItemsFromDesktop(from desktopURL: URL, to destinationRootURL: URL) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: destinationRootURL, withIntermediateDirectories: true)

        guard let itemURLs = try? fileManager.contentsOfDirectory(
            at: desktopURL,
            includingPropertiesForKeys: [.isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let normalizedDestination = destinationRootURL.standardizedFileURL

        for sourceURL in itemURLs {
            let normalizedSource = sourceURL.standardizedFileURL

            if normalizedSource == normalizedDestination {
                continue
            }

            if normalizedSource.lastPathComponent.hasPrefix(".") {
                continue
            }

            if normalizedSource.deletingLastPathComponent().standardizedFileURL == normalizedDestination {
                continue
            }

            if let isHidden = (try? normalizedSource.resourceValues(forKeys: [.isHiddenKey]))?.isHidden, isHidden {
                continue
            }

            let destinationURL = uniqueDestinationURL(for: normalizedSource, in: normalizedDestination, fileManager: fileManager)

            do {
                try fileManager.moveItem(at: normalizedSource, to: destinationURL)
            } catch {
                continue
            }
        }
    }

    private static func uniqueDestinationURL(for sourceURL: URL, in directoryURL: URL, fileManager: FileManager) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let pathExtension = sourceURL.pathExtension
        let fullName = pathExtension.isEmpty ? baseName : "\(baseName).\(pathExtension)"

        var candidateURL = directoryURL.appendingPathComponent(fullName)
        if !fileManager.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }

        var index = 2
        while fileManager.fileExists(atPath: candidateURL.path) {
            let fileName = pathExtension.isEmpty ? "\(baseName) \(index)" : "\(baseName) \(index).\(pathExtension)"
            candidateURL = directoryURL.appendingPathComponent(fileName)
            index += 1
        }

        return candidateURL
    }
}
