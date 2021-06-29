//
//  PreviewViewController.swift
//  XcodePreviewer
//
//  Created by Mihael Isaev on 15.06.2021.
//

import Cocoa
import Quartz
import AppKit
import WebKit
import UIKitPlus
import WebberTools

final class LocalPreview: Equatable, Hashable, Identable {
    typealias ID = String
    static var idKey: IDKey { \.class }
    
    let module, `class`, html: String
    
    @UState var width: CGFloat = 0
    @UState var height: CGFloat = 0
    @UState var title = ""
    @UState var decodedHTML = ""
    
    init (_ preview: WebberTools.Preview) {
        width = CGFloat(preview.width)
        height = CGFloat(preview.height)
        title = preview.title
        module = preview.module
        `class` = preview.class
        html = preview.html
        if let data = Data(base64Encoded: preview.html), let str = String(data: data, encoding: .utf8) {
            decodedHTML = str
        }
    }
    
    static func == (lhs: LocalPreview, rhs: LocalPreview) -> Bool {
        lhs.class == rhs.class
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(`class`)
    }
}

class WV: WebView, WebFrameLoadDelegate {
    init (_ decodedHTML: UState<String>) {
        super.init(frame: .zero)
        self.alphaValue = 0
        self.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        self.mainFrame.webView.frameLoadDelegate = self
        mainFrame.loadHTMLString(decodedHTML.wrappedValue, baseURL: nil)
        decodedHTML.listen {
            self.mainFrame.loadHTMLString($0, baseURL: nil)
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    override init!(frame: NSRect, frameName: String!, groupName: String!) {
        super.init(frame: frame, frameName: frameName, groupName: groupName)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    
    func webView(_ sender: WebView!, didFinishLoadFor frame: WebFrame!) {
        self.alphaValue = 1
    }
}

class PreviewViewController: ViewController, QLPreviewingController {
    
    enum Status {
        case none, building, error, ready
        
        var color: UColor {
            switch self {
            case .building: return .yellow
            case .error: return .red
            case .ready: return .green
            case .none: return .clear
            }
        }
    }
    
    lazy var fileURL: URL = agentFileURL
    
    @UState var agentFileURL: URL = URL(fileURLWithPath: "/")
    @UState var hello = "Loading..."
    @UState var fileActivated = false
    @UState var agentLaunched = false
    @UState var status: Status = .none
    @UState var previews: [LocalPreview] = []
    
    @objc func openURL(_ url: URL) -> Bool {
        var responder: NSResponder? = self
        while responder != nil {
            if let application = responder as? NSApplication {
                return application.perform(#selector(openURL(_:)), with: url) != nil
            }
            responder = responder?.nextResponder
        }
        return false
    }
    
    lazy var container = UVStack()
    
    override func buildUI() {
        super.buildUI()
        body {
            container.subviews {
                UVSpace(16)
                UHStack {
                    UView().size(10).circle().background($status.map { $0.color })
                    UHSpace(16)
                }
                UVSpace(16)
                UVScrollStack {
                    UVSpace(16)
                    UForEach($previews) { preview in
                        UVSpace(16)
                        UText(preview.$title.map { $0.foreground(.white).font(v: .boldSystemFont(ofSize: 18)).alignment(.center) })
                        UVSpace(8)
                        UWrapperView(WV(preview.$decodedHTML))
                            .width(preview.$width)
                            .height(preview.$height)
                    }
                    UVSpace(16)
                }
                .width(to: container)
                .alignment(.centerX)
                UVSpace(16)
                UText("Press Cmd+S in your file to update the preview".foreground(0xd2d2d2).alignment(.center).font(.helveticaNeueMedium, 12))
                UVSpace(16)
            }
            .edgesToSuperview()
            UImage(.bigLogo)
                .size(400)
                .mode(.resizeAspect)
                .hidden($previews.map { $0.count > 0 })
                .centerInSuperview()
            UHStack {
                UText("🤗 Please launch XLivePreview app")
                UHSpace(16)
            }
            .edgesToSuperview(top: 16, trailing: 0)
            .hidden($agentLaunched)
            .onClickGesture {
                GlobalNotifier.setPreviewPath(self.fileURL)
            }
            UText("Please launch XLivePreview app")
                .font(v: .boldSystemFont(ofSize: 16))
                .color(.red)
                .alignment(.center)
                .edgesToSuperview(h: 16)
                .bottomToSuperview(-16, safeArea: true)
                .hidden($agentLaunched)
        }
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
    }
    
    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        fileURL = url
        agentFileURL = url
        GlobalNotifier.configure(.quickLook)
        GlobalNotifier.onAgentLaunch {
            self.hello = "agentLaunched2: \(true)"
            self.agentLaunched = true
        }
        GlobalNotifier.onAgentQuit {
            self.hello = "agentLaunched3: \(false)"
            self.agentLaunched = false
        }
        GlobalNotifier.onActivate { contentHash, names in
            self.hello = names.count > 0 ? names.joined(separator: " / ") : "previews not found"
        }
        GlobalNotifier.onSetPreviewPath {
            self.agentFileURL = $0
        }
        GlobalNotifier.onDetectedCurrentFile {
            self.hello = "current file: \($0.absoluteString)"
        }
        GlobalNotifier.onAccessNotGranted { url in
            guard self.fileURL == url else { return }
            self.fileActivated = false
        }
        GlobalNotifier.onAccessGranted { url in
            guard self.fileURL == url else { return }
            self.fileActivated = true
        }
        
        GlobalNotifier.onQuickLookBuilding { payload in
            self.status = .building
        }
        GlobalNotifier.onQuickLookError { payload in
            self.status = .error
        }
        var fileName = ""
        GlobalNotifier.onQuickLookPreviews { payload in
            self.status = .ready
            if fileName != payload.fileName {
                self.previews.removeAll()
            }
            fileName = payload.fileName
            for (i, preview) in payload.previews.enumerated() {
                if let p = self.previews.first(where: { $0.class == preview.class }) {
                    p.title = preview.title
                    p.width = CGFloat(preview.width)
                    p.height = CGFloat(preview.height)
                    if let data = Data(base64Encoded: preview.html), let str = String(data: data, encoding: .utf8) {
                        p.decodedHTML = str
                    }
                } else {
                    if self.previews.count >= i {
                        self.previews.insert(.init(preview), at: i)
                    } else {
                        self.previews.append(.init(preview))
                    }
                }
            }
            self.previews.removeAll(where: { l in
                !payload.previews.contains(where: { $0.class == l.class })
            })
        }
        GlobalNotifier.setPreviewPath(url.deletingLastPathComponent())
        handler(nil)
    }
}
