//
//  AppDelegate.swift
//  XLivePreview
//
//  Created by Mihael Isaev on 15.06.2021.
//

import UIKitPlus
import WebberTools

class WelcomeViewController: ViewController {
    @BodyBuilder override var body: BodyBuilder.Result {
        UVisualEffectView()
            .edgesToSuperview()
            .size(300)
            .material(.fullScreenUI)
            .blendingMode(.behindWindow)
            .state(.active)
    }
}

class XApp: App {
    lazy var loginWindow = Window {
        NavigationController(rootViewController: WelcomeViewController()).body {
            UHStack {
                UButton.windowClose
                UHSpace(6)
                UButton.windowMinimize
                UHSpace(6)
                UButton.windowZoom.enabled(false)
            }
            .edgesToSuperview(top: 10, leading: 10)
        }
    }
    
    enum WorkStatus {
        case idle, building, error
        
        var color: NSColor {
            switch self {
            case .idle: return .white
            case .building: return .yellow
            case .error: return .red
            }
        }
    }
    
    @UState var workStatus: WorkStatus = .idle
    
    @AppBuilder override var body: AppBuilderContent {
        loginWindow
            .styleMask(.miniaturizable, .closable, .titled, .fullSizeContentView)
            .hideStandardButtons(.closeButton, .miniaturizeButton, .zoomButton)
            .opaque(false)
            .alpha(0.98)
            .hasShadow(true)
            .titlebarAppearsTransparent()
            .titleVisibility(.hidden)
            .movableByWindowBackground()
            .background(.clear)
//            .makeKeyAndOrderFront()
            .size(300, 400)
            .center()
            .title("Test 1")
        StatusItem {
            MenuItem("Quit").onAction(selector: #selector(NSApplication.terminate))
        }
        .squareLength()
        .tint(.blue)
        .image(self.$workStatus.map { .statusIcon($0.color) })
        .toolTip("XLivePreview")
        .menuTitle("Content")
    }
    
    override func applicationWillFinishLaunching(_ notification: Notification) {
        super.applicationWillFinishLaunching(notification)
        NSApp.setActivationPolicy(.accessory)
        GlobalNotifier.configure(.app)
    }
    
    var projects: [Project] = []
    
    override func applicationDidFinishLaunching(_ aNotification: Notification) {
        super.applicationDidFinishLaunching(aNotification)
        GlobalNotifier.agentLaunched()
        GlobalNotifier.onSetPreviewPath { directoryURL in
            GlobalNotifier.agentLaunched()
            debugPrint("onSetPreviewPath")
            func checkAccess() -> Bool {
                guard let bookmark = UserDefaults.standard.data(forKey: directoryURL.path) else { return false }
                var isStale = false
                guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else { return false }
                guard !isStale else { return false }
                guard let _ = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return false }
                return true
            }
            func getAccess(_ handler: @escaping (Bool) -> Void) {
                let openPanel = NSOpenPanel()
                openPanel.canChooseFiles = false
                openPanel.directoryURL = directoryURL
                openPanel.allowsMultipleSelection = false
                openPanel.canChooseDirectories = true
                openPanel.canCreateDirectories = false
                openPanel.title = "Select a folder"
                DispatchQueue.main.async {
                    self.loginWindow.window.center()
                    self.loginWindow.window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    openPanel.beginSheetModal(for:self.loginWindow.window) { (response) in
                        switch response {
                        case .OK:
                            guard
                                let url = openPanel.url,
                                let _ = try? FileManager.default.contentsOfDirectory(atPath: url.path)
                            else {
                                handler(true)
                                return
                            }
                            if let bookmarkData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                                UserDefaults.standard.set(bookmarkData, forKey: directoryURL.path)
                            }
                            handler(true)
                        default:
                            handler(false)
                        }
                        self.loginWindow.window.close()
                        openPanel.close()
                    }
                }
            }
            func accessGranted(_ directoryURL: URL) {
                GlobalNotifier.accessGranted(directoryURL)
                do {
                    self.projects.append(try Project(directoryURL))
                } catch {
                    debugPrint("unable to add project: \(error)")
                }
            }
            guard checkAccess() else {
                return getAccess { granted in
                    guard granted else { return GlobalNotifier.accessNotGranted(directoryURL) }
                    accessGranted(directoryURL)
                }
            }
            accessGranted(directoryURL)
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        GlobalNotifier.agentQuited()
    }
    
    @objc func notif(_ notification: Notification) {
        workStatus = .error
    }
}
