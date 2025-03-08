//
//  CallManager.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

//
//  CallManager.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import AVKit
import UIKit
import SwiftUI
import WebRTC

struct Call: Codable, Equatable {
    struct Participant: Codable, Equatable {
        public enum State: String, Codable {
            case none
            case declined
            case joined
        }
        
        public enum Role: String, Codable {
            case host
            case user
        }
        
        public struct Track: Codable, Equatable {
            public enum State: String, Codable {
                case active, requested, inactive
            }
            
            public enum TrackType: String, Codable {
                case audio, video, screenShare
            }
            
            public let state: State
            public let id: String?
            public let type: TrackType
        }

        let id: String
        let state: State
        let role: Role
        let tracks: [Track]
        let transceiverSessionId: String?
    }
    let participants: [Participant]
}

class CallManager {
    
    // MARK: - Types
    
    enum State: Equatable {
        case none
        case some(Call)
    }
    
    // MARK: - Properties
        
    private let apiClient: APIClient
    
    private let webRTCClient: WebRTCClient
    
    private let webSocketClient: WebSocket
    
    private let state: StateSync<State>
    
    private var sessionId: String? = nil
    
    private var pictureInPictureViewController: PictureInPictureViewController? = nil {
        didSet {
            pictureInPictureViewController?.delegate = self
        }
    }
        
    // MARK: - Functions
    
    init(apiClient: APIClient, webRTCClient: WebRTCClient, webSocketClient: WebSocket) {
        self.apiClient = apiClient
        self.webRTCClient = webRTCClient
        self.webSocketClient = webSocketClient
        self.state = .init(.none)
        
        state.onDidMutate = { [weak self] newState, oldState in
            Task {
                switch (oldState, newState) {
                case (.none, .some(let call)):
                    await self?.addPictureInPictureViewController()
                    await self?.presentAlert(title: "Join Call?", message: "Example Text", options: [
                        UIAlertAction(title: "Join", style: .default) { [weak self] alertAction in
                            Task {
                                await self?.join()
                            }
                        },
                        UIAlertAction(title: "Decline", style: .cancel) { [weak self] alertAction in
                            Task {
                                await self?.decline()
                            }
                        }
                    ])
                default:
                    break
                }
            }
        }
    }
    
    func update(state: Call?) {
        self.state.mutate {
            switch state {
            case .some(let call):
                $0 = .some(call)
            case .none:
                $0 = .none
            }
        }
    }
    
    @MainActor private func presentAlert(title: String, message: String, options: [UIAlertAction]) {
        guard let viewController = UIViewController.topViewController else {
            fatalError("Failed to find top view controller")
        }
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        options.forEach { alertAction in
            alertController.addAction(alertAction)
        }
        alertController.preferredAction = options.first
        viewController.present(alertController, animated: true)
    }
        
    private func join() async {
        do {
            // Create a session
            async let apiTask = apiClient.request(
                endpoint: .postSession(.init()),
                as: APIClient.PostSessionResponse.self
            )
            
            // Configure WebRTC
            async let webRTCTask = webRTCClient.configure()
        
            // Start Picture in Picture with loading state
            async let pictureInPictureTask: () = startPictureInPicture()
            
            let (response, _, _) = try await (apiTask, webRTCTask, pictureInPictureTask)
            
            // Set session
            self.sessionId = response.sessionId
            
            // Update the participants join state
            let message: [String: Any] = ["type": "participantJoined"]
            let jsonData = try JSONSerialization.data(withJSONObject: message, options: .prettyPrinted)
            let json = String(data: jsonData, encoding: .utf8)!
            try await webSocketClient.send(message: .string(json))
                        
            // Pull the tracks
            try await pullTracks()
        } catch {
            assertionFailure("Failed to join call: \(error.localizedDescription)")
        }
    }
    
    private func decline() async {
        do {
            let message: [String: Any] = ["type": "participantDeclined"]
            let jsonData = try JSONSerialization.data(withJSONObject: message, options: .prettyPrinted)
            let json = String(data: jsonData, encoding: .utf8)!
            try await webSocketClient.send(message: .string(json))
        } catch {
            assertionFailure("Failed to decline call: \(error.localizedDescription)")
        }
    }
    
    private func end() async {
        await webRTCClient.close()
    }
    
    @MainActor private func addPictureInPictureViewController() {
        guard let viewController = UIViewController.topViewController else {
            fatalError("Failed to find top view controller")
        }
        
        let pictureInPictureViewController = PictureInPictureViewController()
        self.pictureInPictureViewController = pictureInPictureViewController
        
        viewController.addChild(pictureInPictureViewController)
        viewController.view.addSubview(pictureInPictureViewController.view)
        pictureInPictureViewController.view.isUserInteractionEnabled = false
        pictureInPictureViewController.view.isHidden = true
        pictureInPictureViewController.view.frame = .init(x: viewController.view.frame.width - 150, y: viewController.view.safeAreaInsets.top, width: 150, height: 150)
        pictureInPictureViewController.didMove(toParent: viewController)
    }
        
    @MainActor private func startPictureInPicture() {
        guard let pictureInPictureViewController = pictureInPictureViewController else {
            return
        }

        pictureInPictureViewController.pictureInPictureController.startPictureInPicture()
    }
    
    @MainActor private func stopPictureInPicture() {
        guard let pictureInPictureViewController = pictureInPictureViewController else {
            return
        }

        pictureInPictureViewController.pictureInPictureController.stopPictureInPicture()
    }
    
    private func pullTracks() async throws {}
}

extension CallManager: PictureInPictureViewControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    }
    
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task {
            await stopPictureInPicture()
        }
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController) async -> Bool {
        await MainActor.run {
            presentAlert(title: "Continue Call?", message: "Example Text", options: [
                UIAlertAction(title: "Continue", style: .default) { [weak self] alertAction in
                    self?.startPictureInPicture()
                },
                UIAlertAction(title: "End", style: .cancel) { [weak self] alertAction in
                    Task {
                        await self?.end()
                    }
                }
            ])
        }
        
        return true
    }
}
