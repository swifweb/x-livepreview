//
//  Project.swift
//  XLivePreview
//
//  Created by Mihael Isaev on 15.06.2021.
//

import Foundation
import WebberTools

private class ActivePreviewTask {
    let startedAt = Date()
    let process = Process()
    let swiftPath, path, projectPath, moduleName: String
    let previewNames: [String]
    let completionHandler: (Result<[Preview], Error>) -> Void
    var cancelled = false
    
    init? (_ swiftPath: String, _ path: String, _ previewNames: [String], _ completionHandler: @escaping (Result<[Preview], Error>) -> Void) {
        guard path.contains("/Sources/") else { return nil }
        self.swiftPath = swiftPath
        self.path = path
        self.projectPath = path.components(separatedBy: "/Sources/")[0]
        self.moduleName = path.components(separatedBy: "/Sources/")[1].components(separatedBy: "/")[0]
        self.previewNames = previewNames
        self.completionHandler = completionHandler
    }
    
    func start() {
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.5) {
            guard !self.cancelled else { return }
            do {
                let previews = try Swift(self.swiftPath, self.projectPath)
                    .previews(self.moduleName, previewNames: self.previewNames, self.process)
                guard !self.cancelled else { return }
                self.completionHandler(.success(previews))
            } catch {
                guard !self.cancelled else { return }
                self.completionHandler(.failure(error))
            }
        }
    }
    
    func cancel() {
        debugPrint("🟣 cancelled")
        cancelled = true
        if process.isRunning {
            process.terminate()
        }
    }
}

private class CurrentPreviewContext {
    let url: URL
    let previewNames: [String]
    var contentHash: String
    
    init (_ url: URL, _ previewNames: [String], _ contentHash: String) {
        self.url = url
        self.previewNames = previewNames
        self.contentHash = contentHash
    }
}

class Project {
    fileprivate var activeTask: ActivePreviewTask?
    
    let swiftPath: String
    let directory: URL
    
    init (_ directory: URL) throws {
        self.swiftPath = try Bash.which("swift")
        self.directory = directory
        debugPrint("project initialized")
        watch()
    }
    
    fileprivate var currentPreviewContext: CurrentPreviewContext?
    struct CachedPreviews {
        let contentHash: String
        let previews: [Preview]
    }
    private var _cachedPreviews: [URL: CachedPreviews] = [:]
    
    func watch() {
        debugPrint("watching")
        FS.watch(directory.appendingPathComponent("Sources")) { [weak self] url in
            debugPrint("📡 \(url)")
            self?.changed(at: url)
        }
    }
    
    func changed(at url: URL) {
        var url = url
        if url.pathExtension != "swift" {
            if let context = currentPreviewContext, context.url.path.contains(url.path) {
                url = context.url
                debugPrint("switched folderURL into fileURL")
            } else {
                currentPreviewContext = .init(url, [], String.shuffledAlphabet(32))
                debugPrint("skipped: \(url)")
                return
            }
        }
        debugPrint("✏️ \(url)")
        debugPrint("case 1")
        guard let info = FS.extractPreviewNamesAndHash(at: url.path) else {
            debugPrint("case 2")
            currentPreviewContext = .init(url, [], String.shuffledAlphabet(32))
            notifyQuickLook(file: url, with: [])
            return
        }
        debugPrint("case 3")
        guard info.previewNames.count > 0 else {
            debugPrint("case 4")
            currentPreviewContext = .init(url, [], info.hash)
            notifyQuickLook(file: url, with: [])
            return
        }
        debugPrint("case 5")
        // if same file
        if let context = currentPreviewContext, context.url == url {
            debugPrint("case 6")
            // if have previews in cache
            if let previews = _cachedPreviews[url] {
                debugPrint("case 7")
                notifyQuickLook(file: url, with: previews.previews)
            }
            debugPrint("case 8")
            // content hash should be different
            guard context.contentHash != info.hash else { debugPrint("case 9 context.contentHash: \(context.contentHash) info.hash: \(info.hash)");return }
            currentPreviewContext = .init(url, info.previewNames, info.hash)
            debugPrint("case 10")
            generatePreviews(for: url, info.previewNames, info.hash)
        }
        // if next file
        else {
            currentPreviewContext = .init(url, info.previewNames, info.hash)
            debugPrint("case 11")
            // if have previews in cache
            if let cache = _cachedPreviews[url] {
                debugPrint("case 12")
                notifyQuickLook(file: url, with: cache.previews)
                debugPrint("case 13")
                // content hash should be different
                guard cache.contentHash != info.hash else { debugPrint("case 14");return }
                debugPrint("case 15")
                generatePreviews(for: url, info.previewNames, info.hash)
            } else {
                debugPrint("case 16")
                notifyQuickLook(file: url, with: [])
                generatePreviews(for: url, info.previewNames, info.hash)
            }
        }
    }
    
    private func generatePreviews(for url: URL, _ previewNames: [String], _ contentHash: String) {
        debugPrint("✴️ previewNames: \(previewNames)")
        guard let newTask = ActivePreviewTask(swiftPath, url.path, previewNames, {
            switch $0 {
            case .failure(let error):
                if let error = error as? Swift.SwiftError {
                    switch error {
                    case .errors(let errors):
                        debugPrint("🔴 Compilation errors: \(errors.count)")
                    default:
                        debugPrint("🔴 \(error)")
                    }
                } else {
                    debugPrint("🔴 \(error)")
                }
                self.notifyQuickLookError(file: url)
            case .success(let previews):
                let previews = FS.replaceContentLinksToBase64(at: url.path, previews: previews)
                debugPrint("🟢 succeeded")
                self._cachedPreviews[url] = .init(contentHash: contentHash, previews: previews)
                self.notifyQuickLook(file: url, with: previews)
            }
        }) else {
            debugPrint("🔴 Unable to instantiate new task")
            self.notifyQuickLookError(file: url)
            return
        }
        activeTask?.cancel()
        activeTask = newTask
        notifyQuickLookBuilding(file: url)
        newTask.start()
    }
    
    func notifyQuickLookBuilding(file url: URL) {
        guard currentPreviewContext?.url == url else { return }
        debugPrint("🔨 building")
        GlobalNotifier.quickLookBuilding(.init(directory: directory.path, fileName: url.lastPathComponent))
    }
    
    func notifyQuickLookError(file url: URL) {
        guard currentPreviewContext?.url == url else { return }
        debugPrint("❗️ error")
        GlobalNotifier.quickLookError(.init(directory: directory.path, fileName: url.lastPathComponent))
    }
    
    func notifyQuickLook(file url: URL, with previews: [Preview]) {
        guard currentPreviewContext?.url == url else { return }
        debugPrint("✉️ notify")
        GlobalNotifier.quickLookPreviews(.init(directory: directory.path, fileName: url.lastPathComponent, previews: previews))
    }
}
