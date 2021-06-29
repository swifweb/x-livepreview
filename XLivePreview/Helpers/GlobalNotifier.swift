//
//  GlobalNotifier.swift
//  XLivePreview
//
//  Created by Mihael Isaev on 16.06.2021.
//

import Foundation
import WebberTools

private let _notifier = GlobalNotifier()

class GlobalNotifier {
    private static var shared: GlobalNotifier { _notifier }
    let exchangeKey = "xlivepreview-exchange"
    
    fileprivate init () {}
    
    static func configure(_ type: ServiceType) {
        shared.configure(type)
    }
    
    enum ServiceType {
        case none
        case app
        case sourceExtension
        case quickLook
    }
    
    var serviceType: ServiceType = .none
    
    private func configure(_ type: ServiceType) {
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(notif(_:)), name: .init(exchangeKey), object: nil)
    }
    
    @objc func notif(_ notification: Notification) {
        guard let _str = notification.object as? String else { return }
        guard let data = _str.data(using: .utf8) else { return }
        guard let prototype = try? JSONDecoder().decode(EventPrototype.self, from: data) else { return }
        if prototype.event == .isAgentLaunched {
            if serviceType == .app {
                send(.pingBack, id: prototype.id, payload: Nothing(), pingBack: nil)
            }
        } else {
            if prototype.event != .pingBack, prototype.pingBack {
                send(.pingBack, id: prototype.id, payload: Nothing(), pingBack: nil)
            }
        }
        switch prototype.event {
        case .pingBack:
            pingBacks[prototype.id]?(.success(()))
            pingBacks.removeValue(forKey: prototype.id)
            break
        case .isAgentLaunched:
            break
        case .agentLaunched:
            _agentLaunchedHandler?()
        case .agentQuited:
            _agentQuitedHandler?()
        case .activate:
            guard let data = try? JSONDecoder().decode(EventModel<Activate>.self, from: data) else { return }
            _activateHandler?(data.payload.contentHash, data.payload.previewNames)
        case .setPreivewPath:
            guard let data = try? JSONDecoder().decode(EventModel<SetPreviewPath>.self, from: data) else { return }
            _setPreivewPathHandler?(data.payload.previewPath)
        case .detectedCurrentFile:
            guard let data = try? JSONDecoder().decode(EventModel<DetectedCurrentFile>.self, from: data) else { return }
            _detectedCurrentFileHandler?(data.payload.path)
        case .accessNotGranted:
            guard let data = try? JSONDecoder().decode(EventModel<AccessNotGranted>.self, from: data) else { return }
            _accessNotGrantedHandler?(data.payload.path)
        case .accessGranted:
            guard let data = try? JSONDecoder().decode(EventModel<AccessGranted>.self, from: data) else { return }
            _accessGrantedHandler?(data.payload.path)
        case .quickLookBuilding:
            guard let data = try? JSONDecoder().decode(EventModel<QuickLookBuilding>.self, from: data) else { return }
            _quickLookBuildingHandler?(data.payload)
        case .quickLookError:
            guard let data = try? JSONDecoder().decode(EventModel<QuickLookError>.self, from: data) else { return }
            _quickLookErrorHandler?(data.payload)
        case .quickLookPreviews:
            guard let data = try? JSONDecoder().decode(EventModel<QuickLookPreviews>.self, from: data) else { return }
            _quickLookPreviewsHandler?(data.payload)
        }
    }
    
    private enum GlobalNotifierError: Error {
        case timeout
    }
    
    private struct Nothing: Codable {}
    
    private struct EventPrototype: Codable {
        let id: UUID
        let event: Event
        let pingBack: Bool
    }
    
    private struct EventModel<P: Codable>: Codable {
        let id: UUID
        let event: Event
        let pingBack: Bool
        let payload: P
    }
    
    private struct Activate: Codable {
        let contentHash: String
        let previewNames: [String]
    }
    
    private struct SetPreviewPath: Codable {
        let previewPath: URL
    }
    
    private struct DetectedCurrentFile: Codable {
        let path: URL
    }
    
    private struct AccessNotGranted: Codable {
        let path: URL
    }
    
    private struct AccessGranted: Codable {
        let path: URL
    }
    
    struct QuickLookBuilding: Codable {
        let directory, fileName: String
    }
    
    struct QuickLookError: Codable {
        let directory, fileName: String
    }
    
    struct QuickLookPreviews: Codable {
        let directory, fileName: String
        let previews: [Preview]
    }
    
    private enum Event: String, Codable {
        case pingBack
        case isAgentLaunched
        case agentLaunched
        case agentQuited
        case activate
        case setPreivewPath
        case detectedCurrentFile
        case accessNotGranted
        case accessGranted
        case quickLookBuilding
        case quickLookError
        case quickLookPreviews
    }
    
    private typealias PingBack = (Result<Void, Error>) -> Void
    private var pingBacks: [UUID: PingBack] = [:]
    
    private func send<P: Codable>(_ event: Event, id: UUID = UUID(), payload: P, pingBack: PingBack?) {
        let eventModel = EventModel(id: id, event: event, pingBack: pingBack != nil, payload: payload)
        let object: String
        do {
            object = String(data: try JSONEncoder().encode(eventModel), encoding: .utf8) ?? ""
        } catch {
            pingBack?(.failure(error))
            return
        }
        if let pingBack = pingBack {
            pingBacks[eventModel.id] = pingBack
        }
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name.init(exchangeKey),
            object: object,
            userInfo: nil,
            options: .deliverImmediately
        )
        if let _ = pingBack {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
                self.pingBacks[eventModel.id]?(.failure(GlobalNotifierError.timeout))
                self.pingBacks.removeValue(forKey: eventModel.id)
            }
        }
    }
    
    static func isAgentLaunched(_ handler: @escaping (Bool) -> Void) {
        shared.send(.isAgentLaunched, payload: Nothing()) { result in
            switch result {
            case .failure:
                handler(false)
            case .success:
                handler(true)
            }
        }
    }
    
    static func agentLaunched() {
        shared.send(.agentLaunched, payload: Nothing(), pingBack: nil)
    }
    
    static func agentQuited() {
        shared.send(.agentQuited, payload: Nothing(), pingBack: nil)
    }
    
    static func activate(_ contentHash: String, _ previewNames: [String]) {
        shared.send(
            .activate,
            payload: Activate(
                contentHash: contentHash,
                previewNames: previewNames
            ),
            pingBack: nil
        )
    }
    
    static func setPreviewPath(_ previewPath: URL) {
        shared.send(.setPreivewPath, payload: SetPreviewPath(previewPath: previewPath), pingBack: nil)
    }
    
    static func detectedCurrentFile(_ path: URL) {
        shared.send(.detectedCurrentFile, payload: DetectedCurrentFile(path: path), pingBack: nil)
    }
    
    static func accessNotGranted(_ path: URL) {
        shared.send(.accessNotGranted, payload: AccessNotGranted(path: path), pingBack: nil)
    }
    
    static func accessGranted(_ path: URL) {
        shared.send(.accessGranted, payload: AccessGranted(path: path), pingBack: nil)
    }
    
    static func quickLookBuilding(_ payload: QuickLookBuilding) {
        shared.send(.quickLookBuilding, payload: payload, pingBack: nil)
    }
    
    static func quickLookError(_ payload: QuickLookError) {
        shared.send(.quickLookError, payload: payload, pingBack: nil)
    }
    
    static func quickLookPreviews(_ payload: QuickLookPreviews) {
        shared.send(.quickLookPreviews, payload: payload, pingBack: nil)
    }
    
    private var _agentLaunchedHandler: (() -> Void)?
    
    static func onAgentLaunch(_ handler: @escaping () -> Void) {
        shared._agentLaunchedHandler = handler
    }
    
    private var _agentQuitedHandler: (() -> Void)?
    
    static func onAgentQuit(_ handler: @escaping () -> Void) {
        shared._agentQuitedHandler = handler
    }
    
    private var _activateHandler: ((String, [String]) -> Void)?
    
    static func onActivate(_ handler: @escaping (String, [String]) -> Void) {
        shared._activateHandler = handler
    }
    
    private var _setPreivewPathHandler: ((URL) -> Void)?
    
    static func onSetPreviewPath(_ handler: @escaping (URL) -> Void) {
        shared._setPreivewPathHandler = handler
    }
    
    private var _detectedCurrentFileHandler: ((URL) -> Void)?
    
    static func onDetectedCurrentFile(_ handler: @escaping (URL) -> Void) {
        shared._detectedCurrentFileHandler = handler
    }
    
    private var _accessNotGrantedHandler: ((URL) -> Void)?
    
    static func onAccessNotGranted(_ handler: @escaping (URL) -> Void) {
        shared._accessNotGrantedHandler = handler
    }
    
    private var _accessGrantedHandler: ((URL) -> Void)?
    
    static func onAccessGranted(_ handler: @escaping (URL) -> Void) {
        shared._accessGrantedHandler = handler
    }
    
    private var _quickLookBuildingHandler: ((QuickLookBuilding) -> Void)?
    
    static func onQuickLookBuilding(_ handler: @escaping (QuickLookBuilding) -> Void) {
        shared._quickLookBuildingHandler = handler
    }
    
    private var _quickLookErrorHandler: ((QuickLookError) -> Void)?
    
    static func onQuickLookError(_ handler: @escaping (QuickLookError) -> Void) {
        shared._quickLookErrorHandler = handler
    }
    
    private var _quickLookPreviewsHandler: ((QuickLookPreviews) -> Void)?
    
    static func onQuickLookPreviews(_ handler: @escaping (QuickLookPreviews) -> Void) {
        shared._quickLookPreviewsHandler = handler
    }
}
