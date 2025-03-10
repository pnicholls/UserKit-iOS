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
        enum State: String, Codable {
            case none
            case declined
            case joined
        }
        
        enum Role: String, Codable {
            case host
            case user
        }
        
        struct Track: Codable, Equatable {
            enum State: String, Codable {
                case active, requested, inactive
            }
            
            enum TrackType: String, Codable {
                case audio, video, screenShare
            }
            
            let state: State
            let id: String?
            let type: TrackType
        }

        let id: String
        let name: String
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
    
    private var videoTrack: RTCVideoTrack?
        
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
                    print(call)
                    await self?.addPictureInPictureViewController()
                    
                    let name = call.participants.first(where: { $0.role == .host})?.name
                    let message = "\(name ?? "Someone") is inviting you to a call"
                    await self?.presentAlert(title: "Incoming Call", message: message, options: [
                        UIAlertAction(title: "Join", style: .default) { [weak self] alertAction in
                            Task {
                                await self?.join()
                            }
                        },
                        UIAlertAction(title: "Not Now", style: .cancel) { [weak self] alertAction in
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
        } catch {
            assertionFailure("Failed to join call: \(error.localizedDescription)")
        }
        
        // Pull the tracks
        await pullTracks()
        await pushTracks()
    }
    
    private func decline() async {
        do {
            let message: [String: Any] = ["type": "participantDeclined"]
            let jsonData = try JSONSerialization.data(withJSONObject: message, options: .prettyPrinted)
            guard let json = String(data: jsonData, encoding: .utf8) else {
                enum UserKitError: Error { case invalidJSON }
                throw UserKitError.invalidJSON
            }
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
        pictureInPictureViewController.view.isHidden = false
        pictureInPictureViewController.view.frame = .init(x: viewController.view.frame.width - 50, y: viewController.view.safeAreaInsets.top, width: 50, height: 50)
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
    
    private func pullTracks() async {
        guard let sessionId = sessionId else {
            return assertionFailure("Failed to pull tracks, session required")
        }
        
        guard case .some(let call) = state.read({ $0 }) else {
            return assertionFailure("Failed to pull tracks, invalid call state")
        }
                
        var tracks: [APIClient.PullTracksRequest.Track] = []
        
        let participants = call.participants.filter { $0.role == .host }
        for participant in participants {
            guard let sessionId = participant.transceiverSessionId else {
                continue
            }
            
            for track in participant.tracks {
                guard let id = track.id else {
                    continue
                }
                
                let trackName = id.contains("/") ? String(id.split(separator: "/").last ?? "") : id

                tracks.append(
                    APIClient.PullTracksRequest.Track(
                        location: "remote",
                        trackName: trackName,
                        sessionId: sessionId
                    )
                )
            }
        }
        
        if tracks.isEmpty {
            return
        }
        
        do {
            let response = try await apiClient.request(
                endpoint: .pullTracks(sessionId, .init(tracks: tracks)),
                as: APIClient.PullTracksResponse.self
            )
            
            guard let sessionDescription = response.sessionDescription, response.requiresImmediateRenegotiation else {
                return assertionFailure("Failed to pull tracks, response invalid")
            }
            
            try await webRTCClient.setRemoteDescription(.init(sdp: sessionDescription.sdp, type: .offer))
            let answer = try await webRTCClient.createAnswer()
            let localDescription = try await webRTCClient.setLocalDescription(answer)
            
            let transceivers = await webRTCClient.transceivers()
            if let videoTrack = transceivers.filter({ $0.direction != .sendOnly }).filter({ $0.mediaType == .video }).compactMap({ $0.receiver.track as? RTCVideoTrack }).first {
                await pictureInPictureViewController?.set(track: videoTrack)
            }
            
            try await apiClient.request(
                endpoint: .renegotiate(sessionId, .init(
                    sessionDescription: .init(sdp: localDescription.sdp, type: "answer")
                )),
                as: APIClient.RenegotiateResponse.self
            )
        } catch {
            assertionFailure("Failed to pull tracks: \(error.localizedDescription)")
        }
    }
    
    private func pushTracks() async {
        guard let sessionId = sessionId else {
            return assertionFailure("Failed to pull tracks, session required")
        }
        
        guard case .some(let call) = state.read({ $0 }) else {
            return assertionFailure("Failed to pull tracks, invalid call state")
        }

        do {
            let offer = try await webRTCClient.createOffer()
            let localDescription = try await webRTCClient.setLocalDescription(offer)
            let transceivers = await webRTCClient.getLocalTransceivers()
            
            let tracks = transceivers.map { type, transceiver in
                APIClient.PushTracksRequest.Track(
                    location: "local",
                    trackName: transceiver.sender.track!.trackId,
                    mid: transceiver.mid
                )
            }
            
            if tracks.isEmpty {
                return
            }
                        
            let response = try await apiClient.request(
                endpoint: .pushTracks(sessionId, .init(
                    sessionDescription: .init(sdp: localDescription.sdp, type: "offer"),
                    tracks: tracks
                )),
                as: APIClient.PushTracksResponse.self
            )
            
            try await webRTCClient.setRemoteDescription(.init(sdp: response.sessionDescription.sdp, type: .answer))
            
            guard let participant = call.participants.first(where: { $0.role == .user }) else {
                return
            }
            
            let localTracks: [[String: Any]] = await webRTCClient.getLocalTransceivers().compactMap { type, transceiver in
                guard let id = transceiver.sender.track?.trackId else {
                    return nil
                }
                
                return [
                    "id": "\(sessionId)/\(id)",
                    "type": type,
                    "state": "inactive"
                ]
            }
            
            let data: [String: Any] = [
                "id": participant.id,
                "name": participant.name,
                "state": participant.state.rawValue,
                "transceiverSessionId": sessionId,
                "tracks": localTracks
            ]
            
            let participantUpdate: [String: Any] = [
                "type": "participantUpdate",
                "participant": data
            ]
            
            let jsonData = try JSONSerialization.data(withJSONObject: participantUpdate, options: .prettyPrinted)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                enum UserKitError: Error { case invalidJSON }
                throw UserKitError.invalidJSON
            }
            try await webSocketClient.send(message: .string(jsonString))
        } catch {
            assertionFailure("Failed to push tracks: \(error)")
        }
    }
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
        let state = self.state.read { $0 }
        
        switch state {
        case .some(let call):
            let name = call.participants.first(where: { $0.role == .host})?.name
            let message = "You are in a call with \(name ?? "someone")"

            await MainActor.run {
                presentAlert(title: "Continue Call", message: message, options: [
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
        case .none:
            break
        }
        
        return true
    }
}
