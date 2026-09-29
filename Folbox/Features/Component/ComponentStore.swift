import AppKit
import Foundation
import Combine
import UniformTypeIdentifiers
import Darwin
import CoreGraphics

private final class DirectoryObserver {
    private let fileDescriptor: Int32
    private let source: DispatchSourceFileSystemObject
    private var isInvalidated = false

    init?(directoryURL: URL, onEvent: @escaping () -> Void) {
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return nil
        }

        fileDescriptor = descriptor
        let queue = DispatchQueue(label: "Folbox.DirectoryObserver.\(UUID().uuidString)")
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
            queue: queue
        )
        source.setEventHandler(handler: onEvent)
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        source.cancel()
    }
}

@MainActor
final class ComponentStore: ObservableObject {
    static let shared = ComponentStore()

    private let fileManager = FileManager.default
    private var directoryObservations: [UUID: (path: String, observer: DirectoryObserver)] = [:]

    @Published private(set) var instances: [ComponentInstance] {
        didSet {
            persist()
            syncDirectoryObservers()
        }
    }

    init() {
        instances = []
        ensureRootDirectory()
        restore()
        ensureStorageFolderNames()
        syncManagedFilesFromDisk(updateTimestamp: false)
        pruneMissingFiles()
        syncDirectoryObservers()
    }

    func instance(with id: UUID) -> ComponentInstance? {
        instances.first(where: { $0.id == id })
    }

    func isApplicationLink(instanceID: UUID, filePath: String) -> Bool {
        guard let instance = instance(with: instanceID) else {
            return false
        }
        return instance.appBookmarksByPath[filePath] != nil
    }

    func fileShortcut(instanceID: UUID, filePath: String) -> FileShortcut? {
        guard let instance = instance(with: instanceID) else {
            return nil
        }
        return instance.fileShortcutsByPath[filePath]
    }

    func hasConfiguredFileShortcut(instanceID: UUID, filePath: String) -> Bool {
        fileShortcut(instanceID: instanceID, filePath: filePath)?.isConfigured ?? false
    }

    func setFileShortcut(instanceID: UUID, filePath: String, keyCode: CGKeyCode, modifiers: CGEventFlags) {
        guard let index = instances.firstIndex(where: { $0.id == instanceID }) else {
            return
        }

        let shortcut = normalizedFileShortcut(
            FileShortcut(
                keyCode: Int(keyCode),
                modifierFlagsRaw: modifiers.rawValue
            )
        )

        guard shortcut.isConfigured else {
            clearFileShortcut(instanceID: instanceID, filePath: filePath)
            return
        }

        instances[index].fileShortcutsByPath[filePath] = shortcut
        instances[index].updatedAt = Date()
    }

    func clearFileShortcut(instanceID: UUID, filePath: String) {
        guard let index = instances.firstIndex(where: { $0.id == instanceID }) else {
            return
        }

        guard instances[index].fileShortcutsByPath.removeValue(forKey: filePath) != nil else {
            return
        }

        instances[index].updatedAt = Date()
    }

    func clearMatchingFileShortcut(
        keyCode: CGKeyCode,
        modifiers: CGEventFlags,
        excludingInstanceID: UUID,
        excludingFilePath: String
    ) {
        let target = normalizedFileShortcut(
            FileShortcut(
                keyCode: Int(keyCode),
                modifierFlagsRaw: modifiers.rawValue
            )
        )

        guard target.isConfigured else { return }

        for index in instances.indices {
            let id = instances[index].id
            var removedAny = false

            for (path, shortcut) in instances[index].fileShortcutsByPath {
                if shortcut != target {
                    continue
                }
                if id == excludingInstanceID, path == excludingFilePath {
                    continue
                }
                instances[index].fileShortcutsByPath.removeValue(forKey: path)
                removedAny = true
            }

            if removedAny {
                instances[index].updatedAt = Date()
            }
        }
    }

    @discardableResult
    func openFile(instanceID: UUID, filePath: String) -> Bool {
        guard let instance = instance(with: instanceID),
              instance.filePaths.contains(filePath) else {
            return false
        }

        let storedURL = URL(fileURLWithPath: filePath)
        let target = resolveStoredFileURL(for: storedURL)
        let didAccess = target.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                target.stopAccessingSecurityScopedResource()
            }
        }

        return NSWorkspace.shared.open(target)
    }

    @discardableResult
    func createInstance(
        name: String,
        styleColorHex: String,
        customCollapsedColumns: Int? = nil
    ) -> ComponentInstance {
        let now = Date()
        let id = UUID()
        let directoryName = preferredDirectoryName(name: name, id: id)
        let instance = ComponentInstance(
            id: id,
            name: name,
            storageFolderName: directoryName,
            styleColorHex: styleColorHex,
            customCollapsedColumns: customCollapsedColumns.map(GridMetrics.clamp),
            filePaths: [],
            createdAt: now,
            updatedAt: now
        )

        ensureDirectory(at: rootDirectoryURL.appendingPathComponent(directoryName, isDirectory: true))
        instances.append(instance)
        return instance
    }

    func updateInstance(
        id: UUID,
        name: String,
        styleColorHex: String,
        customCollapsedColumns: Int?
    ) {
        guard let index = instances.firstIndex(where: { $0.id == id }) else {
            return
        }

        let currentFolderName = normalizedStorageFolderName(instances[index].storageFolderName)
            ?? preferredDirectoryName(name: instances[index].name, id: id)

        var updated = instances[index]
        updated.name = name
        updated.styleColorHex = styleColorHex
        updated.customCollapsedColumns = customCollapsedColumns.map(GridMetrics.clamp)
        updated.updatedAt = Date()
        updated.storageFolderName = currentFolderName
        instances[index] = updated

        if let updatedIndex = instances.firstIndex(where: { $0.id == id }) {
            _ = reconcileStorageFolderName(for: updatedIndex, preferDisplayName: true)
        }
    }

    func deleteInstanceIfEmpty(id: UUID) -> Bool {
        guard let index = instances.firstIndex(where: { $0.id == id }) else {
            return false
        }

        guard instances[index].filePaths.isEmpty else {
            return false
        }

        stopDirectoryObservation(for: id)
        let directory = filesDirectoryURL(for: id)
        try? fileManager.removeItem(at: directory)
        instances.remove(at: index)
        return true
    }

    @discardableResult
    func importFiles(_ urls: [URL], to id: UUID, failures: inout [String]) -> Int {
        guard let index = instances.firstIndex(where: { $0.id == id }) else {
            return 0
        }

        let directory = filesDirectoryURL(for: id)
        ensureDirectory(at: directory)
        var importedCount = 0

        for sourceURL in urls where sourceURL.isFileURL {
            if let applicationURL = applicationURLToTrack(from: sourceURL) {
                switch bookmarkDataForApplication(at: applicationURL) {
                case .success(let bookmarkData):
                    let appPath = applicationURL.path
                    instances[index].filePaths.append(appPath)
                    instances[index].appBookmarksByPath[appPath] = bookmarkData
                    importedCount += 1
                case .failure(let error):
                    failures.append("\(sourceURL.lastPathComponent): \(error.message)")
                }
                continue
            }

            let result = moveFileToManagedDirectory(sourceURL: sourceURL, directoryURL: directory)
            switch result {
            case .success(let destinationURL):
                instances[index].filePaths.append(destinationURL.path)
                importedCount += 1
            case .failure(let error):
                failures.append("\(sourceURL.lastPathComponent): \(error.message)")
            }
        }

        if importedCount > 0 {
            instances[index].updatedAt = Date()
        }

        return importedCount
    }

    func trashFile(instanceID: UUID, filePath: String) {
        guard let index = instances.firstIndex(where: { $0.id == instanceID }) else {
            return
        }

        let fileURL = URL(fileURLWithPath: filePath)
        if instances[index].appBookmarksByPath[filePath] != nil || applicationURLToTrack(from: fileURL) != nil {
            instances[index].filePaths.removeAll(where: { $0 == filePath })
            instances[index].appBookmarksByPath.removeValue(forKey: filePath)
            instances[index].fileShortcutsByPath.removeValue(forKey: filePath)
            instances[index].updatedAt = Date()
            return
        }

        instances[index].filePaths.removeAll(where: { $0 == filePath })
        instances[index].fileShortcutsByPath.removeValue(forKey: filePath)
        try? fileManager.trashItem(at: URL(fileURLWithPath: filePath), resultingItemURL: nil)
        instances[index].updatedAt = Date()
    }

    func updateStoredFilePath(instanceID: UUID, from oldPath: String, to newPath: String) {
        guard oldPath != newPath,
              let index = instances.firstIndex(where: { $0.id == instanceID }),
              let currentIndex = instances[index].filePaths.firstIndex(of: oldPath) else {
            return
        }

        if instances[index].filePaths.contains(newPath) {
            return
        }

        instances[index].filePaths[currentIndex] = newPath

        if let bookmarkData = instances[index].appBookmarksByPath.removeValue(forKey: oldPath) {
            instances[index].appBookmarksByPath[newPath] = bookmarkData
        }

        if let shortcut = instances[index].fileShortcutsByPath.removeValue(forKey: oldPath) {
            instances[index].fileShortcutsByPath[newPath] = shortcut
        }

        instances[index].updatedAt = Date()
    }

    func reorderFile(instanceID: UUID, filePath: String, to targetIndex: Int?) {
        guard let index = instances.firstIndex(where: { $0.id == instanceID }) else {
            return
        }

        var paths = instances[index].filePaths
        guard let currentIndex = paths.firstIndex(of: filePath) else {
            return
        }

        paths.remove(at: currentIndex)
        let destination = min(max(targetIndex ?? paths.count, 0), paths.count)
        paths.insert(filePath, at: destination)

        instances[index].filePaths = paths
        instances[index].updatedAt = Date()
    }

    func transferFile(filePath: String, from sourceID: UUID, to targetID: UUID, targetIndex: Int?) {
        guard sourceID != targetID else {
            reorderFile(instanceID: sourceID, filePath: filePath, to: targetIndex)
            return
        }

        guard let sourceIndex = instances.firstIndex(where: { $0.id == sourceID }),
              let targetArrayIndex = instances.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        let sourceShortcut = instances[sourceIndex].fileShortcutsByPath[filePath]

        if let bookmarkData = instances[sourceIndex].appBookmarksByPath[filePath] {
            instances[sourceIndex].filePaths.removeAll(where: { $0 == filePath })
            instances[sourceIndex].appBookmarksByPath.removeValue(forKey: filePath)
            instances[sourceIndex].fileShortcutsByPath.removeValue(forKey: filePath)
            instances[sourceIndex].updatedAt = Date()

            var paths = instances[targetArrayIndex].filePaths
            let destination = min(max(targetIndex ?? paths.count, 0), paths.count)
            paths.insert(filePath, at: destination)
            instances[targetArrayIndex].filePaths = paths
            instances[targetArrayIndex].appBookmarksByPath[filePath] = bookmarkData
            if let sourceShortcut {
                instances[targetArrayIndex].fileShortcutsByPath[filePath] = sourceShortcut
            }
            instances[targetArrayIndex].updatedAt = Date()
            return
        }

        let sourceFileURL = URL(fileURLWithPath: filePath)
        if let applicationURL = applicationURLToTrack(from: sourceFileURL) {
            guard case .success(let bookmarkData) = bookmarkDataForApplication(at: applicationURL) else {
                return
            }

            instances[sourceIndex].filePaths.removeAll(where: { $0 == filePath })
            instances[sourceIndex].appBookmarksByPath.removeValue(forKey: filePath)
            instances[sourceIndex].fileShortcutsByPath.removeValue(forKey: filePath)
            instances[sourceIndex].updatedAt = Date()

            var paths = instances[targetArrayIndex].filePaths
            let destination = min(max(targetIndex ?? paths.count, 0), paths.count)
            paths.insert(applicationURL.path, at: destination)
            instances[targetArrayIndex].filePaths = paths
            instances[targetArrayIndex].appBookmarksByPath[applicationURL.path] = bookmarkData
            if let sourceShortcut {
                instances[targetArrayIndex].fileShortcutsByPath[applicationURL.path] = sourceShortcut
            }
            instances[targetArrayIndex].updatedAt = Date()
            return
        }

        let directory = filesDirectoryURL(for: targetID)
        ensureDirectory(at: directory)

        guard case .success(let movedURL) = moveFileToManagedDirectory(
            sourceURL: URL(fileURLWithPath: filePath),
            directoryURL: directory
        ) else {
            return
        }

        instances[sourceIndex].filePaths.removeAll(where: { $0 == filePath })
        instances[sourceIndex].fileShortcutsByPath.removeValue(forKey: filePath)
        instances[sourceIndex].updatedAt = Date()

        var paths = instances[targetArrayIndex].filePaths
        let destination = min(max(targetIndex ?? paths.count, 0), paths.count)
        paths.insert(movedURL.path, at: destination)
        instances[targetArrayIndex].filePaths = paths
        if let sourceShortcut {
            instances[targetArrayIndex].fileShortcutsByPath[movedURL.path] = sourceShortcut
        }
        instances[targetArrayIndex].updatedAt = Date()
    }

    @discardableResult
    func exportAllFiles(instanceID: UUID, to destinationDirectoryURL: URL) -> Int {
        guard let index = instances.firstIndex(where: { $0.id == instanceID }) else {
            return 0
        }

        ensureDirectory(at: destinationDirectoryURL)
        var exportedCount = 0
        let sourcePaths = instances[index].filePaths
        var removedPaths: Set<String> = []

        for sourcePath in sourcePaths {
            if instances[index].appBookmarksByPath[sourcePath] != nil {
                removedPaths.insert(sourcePath)
                exportedCount += 1
                continue
            }

            let sourceURL = URL(fileURLWithPath: sourcePath)
            if applicationURLToTrack(from: sourceURL) != nil {
                removedPaths.insert(sourcePath)
                exportedCount += 1
                continue
            }

            guard fileManager.fileExists(atPath: sourceURL.path) else {
                continue
            }

            let destinationURL = uniqueDestinationURL(for: sourceURL, in: destinationDirectoryURL)
            do {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
                removedPaths.insert(sourcePath)
                exportedCount += 1
            } catch {
                continue
            }
        }

        if exportedCount > 0 {
            instances[index].filePaths.removeAll(where: { removedPaths.contains($0) })
            for removedPath in removedPaths {
                instances[index].appBookmarksByPath.removeValue(forKey: removedPath)
                instances[index].fileShortcutsByPath.removeValue(forKey: removedPath)
            }
            instances[index].updatedAt = Date()
        }

        return exportedCount
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(instances) else {
            return
        }

        try? data.write(to: metadataFileURL, options: .atomic)
    }

    private func restore() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let data = try? Data(contentsOf: metadataFileURL),
           let restored = try? decoder.decode([ComponentInstance].self, from: data) {
            instances = restored
        }
    }

    private var metadataFileURL: URL {
        rootDirectoryURL.appendingPathComponent("metadata.json")
    }

    var currentStorageRootURL: URL {
        rootDirectoryURL
    }

    func instanceDirectoryURL(for instanceID: UUID) -> URL {
        let directoryURL = filesDirectoryURL(for: instanceID)
        ensureDirectory(at: directoryURL)
        return directoryURL
    }

    @discardableResult
    func relocateStorage(from oldRoot: URL, to newRoot: URL) -> Bool {
        guard oldRoot != newRoot else { return true }

        ensureDirectory(at: newRoot)
        let targetHasContent = storageRootHasMeaningfulContent(newRoot)

        let newMetadataURL = newRoot.appendingPathComponent("metadata.json")
        if fileManager.fileExists(atPath: newMetadataURL.path) {
            restore()
            remapStoredPathsForStorageRootChange(from: oldRoot, to: newRoot)
            ensureStorageFolderNames()
            syncManagedFilesFromDisk(updateTimestamp: false)
            pruneMissingFiles()
            syncDirectoryObservers()
            return true
        }

        if targetHasContent {
            instances = []
            syncDirectoryObservers()
            return true
        }

        if let items = try? fileManager.contentsOfDirectory(at: oldRoot, includingPropertiesForKeys: nil) {
            for item in items {
                let destination = newRoot.appendingPathComponent(item.lastPathComponent)
                if fileManager.fileExists(atPath: destination.path) {
                    try? fileManager.removeItem(at: destination)
                }
                try? fileManager.moveItem(at: item, to: destination)
            }
        }

        remapStoredPathsForStorageRootChange(from: oldRoot, to: newRoot)

        ensureStorageFolderNames()
        syncManagedFilesFromDisk(updateTimestamp: false)
        syncDirectoryObservers()

        return true
    }

    private var rootDirectoryURL: URL {
        StorageLocation.rootDirectoryURL(customURL: SettingsStore.shared.resolvedCustomStorageURL())
    }

    private func filesDirectoryURL(for instanceID: UUID) -> URL {
        guard let index = instances.firstIndex(where: { $0.id == instanceID }) else {
            return rootDirectoryURL.appendingPathComponent(instanceID.uuidString, isDirectory: true)
        }

        if instances[index].storageFolderName == nil {
            _ = reconcileStorageFolderName(for: index, preferDisplayName: false)
        }

        let folderName = instances[index].storageFolderName ?? instanceID.uuidString
        return rootDirectoryURL.appendingPathComponent(folderName, isDirectory: true)
    }

    private func ensureStorageFolderNames() {
        for index in instances.indices {
            _ = reconcileStorageFolderName(for: index, preferDisplayName: false)
        }
    }

    @discardableResult
    private func reconcileStorageFolderName(for index: Int, preferDisplayName: Bool) -> URL {
        guard instances.indices.contains(index) else {
            return rootDirectoryURL
        }

        let instance = instances[index]
        let preferredName = preferredDirectoryName(name: instance.name, id: instance.id)

        let currentName = normalizedStorageFolderName(instance.storageFolderName)
            ?? preferredName

        var finalName = currentName

        if preferDisplayName, currentName != preferredName {
            let sourceURL = rootDirectoryURL.appendingPathComponent(currentName, isDirectory: true)
            let destinationURL = rootDirectoryURL.appendingPathComponent(preferredName, isDirectory: true)

            if fileManager.fileExists(atPath: sourceURL.path),
               !fileManager.fileExists(atPath: destinationURL.path) {
                do {
                    try fileManager.moveItem(at: sourceURL, to: destinationURL)
                    // Set the new folder binding first so didSet side-effects don't recreate the old folder.
                    instances[index].storageFolderName = preferredName
                    remapManagedPaths(instanceIndex: index, from: sourceURL, to: destinationURL)
                    finalName = preferredName
                } catch {
                    finalName = currentName
                }
            }
        }

        let finalURL = rootDirectoryURL.appendingPathComponent(finalName, isDirectory: true)
        ensureDirectory(at: finalURL)

        if instances[index].storageFolderName != finalName {
            instances[index].storageFolderName = finalName
        }

        return finalURL
    }

    private func normalizedStorageFolderName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func remapStoredPathsForStorageRootChange(from oldRoot: URL, to newRoot: URL) {
        let oldPrefix = oldRoot.standardizedFileURL.path
        let newPrefix = newRoot.standardizedFileURL.path
        guard oldPrefix != newPrefix else {
            return
        }

        for index in instances.indices {
            instances[index].filePaths = instances[index].filePaths.map { path in
                remappedPath(path, oldPrefix: oldPrefix, newPrefix: newPrefix)
            }

            var remappedBookmarks: [String: Data] = [:]
            remappedBookmarks.reserveCapacity(instances[index].appBookmarksByPath.count)
            for (path, bookmarkData) in instances[index].appBookmarksByPath {
                let remapped = remappedPath(path, oldPrefix: oldPrefix, newPrefix: newPrefix)
                remappedBookmarks[remapped] = bookmarkData
            }
            instances[index].appBookmarksByPath = remappedBookmarks

            var remappedShortcuts: [String: FileShortcut] = [:]
            remappedShortcuts.reserveCapacity(instances[index].fileShortcutsByPath.count)
            for (path, shortcut) in instances[index].fileShortcutsByPath {
                let remapped = remappedPath(path, oldPrefix: oldPrefix, newPrefix: newPrefix)
                remappedShortcuts[remapped] = shortcut
            }
            instances[index].fileShortcutsByPath = remappedShortcuts
        }
    }

    private func remappedPath(_ path: String, oldPrefix: String, newPrefix: String) -> String {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        guard normalizedPath == oldPrefix || normalizedPath.hasPrefix(oldPrefix + "/") else {
            return path
        }

        let suffix = normalizedPath.dropFirst(oldPrefix.count)
        return newPrefix + suffix
    }

    private func storageRootHasMeaningfulContent(_ root: URL) -> Bool {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for url in urls {
            let name = url.lastPathComponent
            if name == ".DS_Store" || name == ".localized" || name.hasPrefix("._") {
                continue
            }
            return true
        }

        return false
    }

    private func remapManagedPaths(instanceIndex: Int, from sourceDirectoryURL: URL, to destinationDirectoryURL: URL) {
        guard instances.indices.contains(instanceIndex) else {
            return
        }

        let sourcePrefix = sourceDirectoryURL.standardizedFileURL.path + "/"
        let destinationPrefix = destinationDirectoryURL.standardizedFileURL.path + "/"

        instances[instanceIndex].filePaths = instances[instanceIndex].filePaths.map { path in
            let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            guard normalizedPath.hasPrefix(sourcePrefix) else {
                return path
            }
            let suffix = normalizedPath.dropFirst(sourcePrefix.count)
            return destinationPrefix + suffix
        }

        var remappedBookmarks: [String: Data] = [:]
        remappedBookmarks.reserveCapacity(instances[instanceIndex].appBookmarksByPath.count)
        for (path, bookmarkData) in instances[instanceIndex].appBookmarksByPath {
            let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            if normalizedPath.hasPrefix(sourcePrefix) {
                let suffix = normalizedPath.dropFirst(sourcePrefix.count)
                remappedBookmarks[destinationPrefix + suffix] = bookmarkData
            } else {
                remappedBookmarks[path] = bookmarkData
            }
        }
        instances[instanceIndex].appBookmarksByPath = remappedBookmarks

        var remappedShortcuts: [String: FileShortcut] = [:]
        remappedShortcuts.reserveCapacity(instances[instanceIndex].fileShortcutsByPath.count)
        for (path, shortcut) in instances[instanceIndex].fileShortcutsByPath {
            let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            if normalizedPath.hasPrefix(sourcePrefix) {
                let suffix = normalizedPath.dropFirst(sourcePrefix.count)
                remappedShortcuts[destinationPrefix + suffix] = shortcut
            } else {
                remappedShortcuts[path] = shortcut
            }
        }
        instances[instanceIndex].fileShortcutsByPath = remappedShortcuts
    }

    private func preferredDirectoryName(name: String, id: UUID) -> String {
        let base = sanitizedDirectoryBase(name)
        let shortID = String(id.uuidString.prefix(6)).lowercased()
        return "\(base)-\(shortID)"
    }

    private func sanitizedDirectoryBase(_ name: String) -> String {
        var value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            return AppLocalization.string("folbox.component.default_name")
        }

        value = value.replacingOccurrences(of: "/", with: "-")
        value = value.replacingOccurrences(of: ":", with: "-")
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if value.isEmpty {
            return AppLocalization.string("folbox.component.default_name")
        }

        return String(value.prefix(48))
    }

    private func ensureRootDirectory() {
        ensureDirectory(at: rootDirectoryURL)
    }

    private func ensureDirectory(at url: URL) {
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private struct FileMoveError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private func moveFileToManagedDirectory(sourceURL: URL, directoryURL: URL) -> Result<URL, FileMoveError> {
        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let destinationURL = uniqueDestinationURL(for: sourceURL, in: directoryURL)
        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            return .success(destinationURL)
        } catch {
            return .failure(FileMoveError(message: error.localizedDescription))
        }
    }

    private func applicationURLToTrack(from sourceURL: URL) -> URL? {
        let resolvedURL = (try? URL(resolvingAliasFileAt: sourceURL, options: [.withoutUI, .withoutMounting])) ?? sourceURL
        return isApplicationBundle(resolvedURL) ? resolvedURL : nil
    }

    private func isApplicationBundle(_ url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey]),
           values.isDirectory == true,
           let contentType = values.contentType {
            return contentType.conforms(to: .application)
        }
        if let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory,
           isDirectory {
            return url.pathExtension.lowercased() == "app"
        }
        return false
    }

    private func bookmarkDataForApplication(at sourceURL: URL) -> Result<Data, FileMoveError> {
        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let scopedOptions: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
        let bookmarkData = (try? sourceURL.bookmarkData(options: scopedOptions, includingResourceValuesForKeys: nil, relativeTo: nil))
        guard let bookmarkData else {
            return .failure(FileMoveError(message: AppLocalization.string("folbox.component.import_app_permission_failed")))
        }
        return .success(bookmarkData)
    }

    func resolveStoredFileURL(for storedURL: URL) -> URL {
        if let bookmarkData = bookmarkData(for: storedURL.path) {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if isStale,
                   let refreshedData = try? resolvedURL.bookmarkData(
                        options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                   ) {
                    refreshBookmarkData(refreshedData, for: storedURL.path)
                }
                return resolvedURL
            }
        }

        return storedURL
    }

    private func bookmarkData(for path: String) -> Data? {
        for instance in instances {
            if let bookmarkData = instance.appBookmarksByPath[path] {
                return bookmarkData
            }
        }
        return nil
    }

    private func refreshBookmarkData(_ data: Data, for path: String) {
        for index in instances.indices {
            guard instances[index].appBookmarksByPath[path] != nil else {
                continue
            }
            instances[index].appBookmarksByPath[path] = data
        }
    }

    private func syncManagedFilesFromDisk(updateTimestamp: Bool) {
        for id in instances.map(\.id) {
            syncManagedFilesFromDisk(instanceID: id, updateTimestamp: updateTimestamp)
        }
    }

    private func syncManagedFilesFromDisk(instanceID: UUID, updateTimestamp: Bool = true) {
        guard let index = instances.firstIndex(where: { $0.id == instanceID }) else {
            return
        }

        let directoryURL = filesDirectoryURL(for: instanceID)
        ensureDirectory(at: directoryURL)

        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        let diskPaths = urls
            .map(\.path)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let diskPathSet = Set(diskPaths)
        let bookmarkPaths = instances[index].appBookmarksByPath

        var merged = instances[index].filePaths.filter { path in
            guard isManagedPath(path, in: directoryURL), bookmarkPaths[path] == nil else {
                return true
            }
            return diskPathSet.contains(path)
        }

        let knownManagedPaths = Set(
            merged.filter { path in
                isManagedPath(path, in: directoryURL) && bookmarkPaths[path] == nil
            }
        )
        for path in diskPaths where !knownManagedPaths.contains(path) {
            merged.append(path)
        }

        var unique: [String] = []
        unique.reserveCapacity(merged.count)
        var seen: Set<String> = []
        for path in merged where seen.insert(path).inserted {
            unique.append(path)
        }

        let validPaths = Set(unique)
        let filteredShortcuts = instances[index].fileShortcutsByPath.filter { validPaths.contains($0.key) }

        guard unique != instances[index].filePaths || filteredShortcuts != instances[index].fileShortcutsByPath else {
            return
        }

        instances[index].filePaths = unique
        instances[index].fileShortcutsByPath = filteredShortcuts
        if updateTimestamp {
            instances[index].updatedAt = Date()
        }
    }

    private func isManagedPath(_ path: String, in directoryURL: URL) -> Bool {
        let managedDirectoryPath = directoryURL.standardizedFileURL.path
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return normalizedPath.hasPrefix(managedDirectoryPath + "/")
    }

    private func normalizedFileShortcut(_ shortcut: FileShortcut) -> FileShortcut {
        let keyCode = min(max(shortcut.keyCode, 0), Int(UInt16.max))
        let modifiers = HotKeyManager.normalizedFlags(rawValue: shortcut.modifierFlagsRaw).rawValue

        if keyCode == Int(CGKeyCode.disabled) || modifiers == CGEventFlags.disabled.rawValue {
            return .disabled
        }

        return FileShortcut(keyCode: keyCode, modifierFlagsRaw: modifiers)
    }

    private func syncDirectoryObservers() {
        let validIDs = Set(instances.map(\.id))

        for id in Array(directoryObservations.keys) where !validIDs.contains(id) {
            stopDirectoryObservation(for: id)
        }

        for id in validIDs {
            let directoryURL = filesDirectoryURL(for: id)
            ensureDirectory(at: directoryURL)
            let path = directoryURL.path

            if let observation = directoryObservations[id], observation.path == path {
                continue
            }

            stopDirectoryObservation(for: id)

            guard let observer = DirectoryObserver(directoryURL: directoryURL, onEvent: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.syncManagedFilesFromDisk(instanceID: id)
                }
            }) else {
                continue
            }

            directoryObservations[id] = (path: path, observer: observer)
        }
    }

    private func stopDirectoryObservation(for id: UUID) {
        guard let observation = directoryObservations.removeValue(forKey: id) else {
            return
        }
        observation.observer.invalidate()
    }

    private func uniqueDestinationURL(for sourceURL: URL, in directoryURL: URL) -> URL {
        uniqueDestinationURL(
            baseName: sourceURL.deletingPathExtension().lastPathComponent,
            pathExtension: sourceURL.pathExtension,
            in: directoryURL
        )
    }

    private func uniqueDestinationURL(baseName: String, pathExtension: String, in directoryURL: URL) -> URL {
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

    private func pruneMissingFiles() {
        for index in instances.indices {
            let filtered = instances[index].filePaths.filter { fileManager.fileExists(atPath: $0) }
            let validPaths = Set(filtered)
            let filteredBookmarks = instances[index].appBookmarksByPath.filter { validPaths.contains($0.key) }
            let filteredShortcuts = instances[index].fileShortcutsByPath.filter { validPaths.contains($0.key) }
            guard filtered != instances[index].filePaths || filteredBookmarks != instances[index].appBookmarksByPath || filteredShortcuts != instances[index].fileShortcutsByPath else {
                continue
            }

            instances[index].filePaths = filtered
            instances[index].appBookmarksByPath = filteredBookmarks
            instances[index].fileShortcutsByPath = filteredShortcuts
            instances[index].updatedAt = Date()
        }
    }

    func pruneMissingFiles(instanceID: UUID) {
        guard let index = instances.firstIndex(where: { $0.id == instanceID }) else {
            return
        }

        let filtered = instances[index].filePaths.filter { fileManager.fileExists(atPath: $0) }
        let validPaths = Set(filtered)
        let filteredBookmarks = instances[index].appBookmarksByPath.filter { validPaths.contains($0.key) }
        let filteredShortcuts = instances[index].fileShortcutsByPath.filter { validPaths.contains($0.key) }

        guard filtered != instances[index].filePaths || filteredBookmarks != instances[index].appBookmarksByPath || filteredShortcuts != instances[index].fileShortcutsByPath else {
            return
        }

        instances[index].filePaths = filtered
        instances[index].appBookmarksByPath = filteredBookmarks
        instances[index].fileShortcutsByPath = filteredShortcuts
        instances[index].updatedAt = Date()
    }
}
