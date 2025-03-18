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
import ReplayKit
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

        let id: String?
        let name: String
        let state: State
        let role: Role
        let tracks: [Track]
        let transceiverSessionId: String?
    }
    struct TouchIndicator: Codable, Equatable {
        enum State: String, Codable {
            case active, inactive
        }
        
        let state: State
    }
    let participants: [Participant]
    let touchIndicator: TouchIndicator
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
    
    private let cameraClient = CameraClient()
            
    // MARK: - Functions
    
    init(apiClient: APIClient, webRTCClient: WebRTCClient, webSocketClient: WebSocket) {
        self.apiClient = apiClient
        self.webRTCClient = webRTCClient
        self.webSocketClient = webSocketClient
        self.state = .init(.none)
        
        state.onDidMutate = { [weak self] newState, oldState in
            Task {
                switch (oldState, newState) {
                case (.none, .some(let newCall)):
                    await self?.handleStateChange(oldCall: nil, newCall: newCall)
                case (.some(let oldCall), .some(let newCall)):
                    await self?.handleStateChange(oldCall: oldCall, newCall: newCall)
                case (.some(let oldCall), .none):
                    await self?.handleStateChange(oldCall: oldCall, newCall: nil)
                case (.none, .none):
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
                
        // Pull and push tracks
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
        await cameraClient.stop()
        
        if RPScreenRecorder.shared().isRecording {
            RPScreenRecorder.shared().stopCapture()
        }
        TouchIndicator.enabled = .never
        
        await webRTCClient.close()
        
        do {
            let message: [String: Any] = ["type": "participantLeft"]
            let jsonData = try JSONSerialization.data(withJSONObject: message, options: .prettyPrinted)
            guard let json = String(data: jsonData, encoding: .utf8) else {
                enum UserKitError: Error { case invalidJSON }
                throw UserKitError.invalidJSON
            }
            try await webSocketClient.send(message: .string(json))
        } catch {
            assertionFailure("Failed to leave call: \(error.localizedDescription)")
        }
    }
    
    private func addPictureInPictureViewController() {
        Task { @MainActor in
            guard let viewController = UIViewController.topViewController else {
                fatalError("Failed to find top view controller")
            }
            
            guard pictureInPictureViewController == nil else {
                return
            }
        
            let pictureInPictureViewController = PictureInPictureViewController()
            self.pictureInPictureViewController = pictureInPictureViewController
            
            viewController.addChild(pictureInPictureViewController)
            viewController.view.addSubview(pictureInPictureViewController.view)
            pictureInPictureViewController.view.isUserInteractionEnabled = false
            pictureInPictureViewController.view.isHidden = false
            pictureInPictureViewController.view.frame = .init(x: viewController.view.frame.width - 50, y: viewController.view.safeAreaInsets.top, width: 50, height: 50)
            pictureInPictureViewController.didMove(toParent: viewController)
            
            viewController.view.layoutIfNeeded()
        }
    }
    
    private func removePictureInPictureViewController() {
        Task { @MainActor in
            guard let pictureInPictureViewController = pictureInPictureViewController else {
                return
            }
        
            pictureInPictureViewController.willMove(toParent: nil)
            pictureInPictureViewController.view.removeFromSuperview()
            pictureInPictureViewController.removeFromParent()
            
            self.pictureInPictureViewController = nil
        }
    }
        
    private func startPictureInPicture() {
        Task { @MainActor in
            guard let pictureInPictureViewController = pictureInPictureViewController else {
                return
            }
            
            guard !pictureInPictureViewController.pictureInPictureController.isPictureInPictureActive else {
                return
            }

            pictureInPictureViewController.pictureInPictureController.startPictureInPicture()
        }
    }
    
    private func stopPictureInPicture() async {
        await MainActor.run { [weak self] in
            guard let self = self,
                  let pictureInPictureViewController = self.pictureInPictureViewController else {
                return
            }
            
            pictureInPictureViewController.pictureInPictureController.stopPictureInPicture()
        }
        
        while await MainActor.run(body: { [weak self] in
            self?.pictureInPictureViewController?.pictureInPictureController.isPictureInPictureActive ?? false
        }) {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
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
                // TODO: Handle track errors
                return
            }
            
            try await webRTCClient.setRemoteDescription(.init(sdp: sessionDescription.sdp, type: .offer))
            let answer = try await webRTCClient.createAnswer()
            let localDescription = try await webRTCClient.setLocalDescription(answer)
            
            await setPictureInPictureTrack()
            
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
    
    private func setPictureInPictureTrack() async {
        let transceivers = await webRTCClient.transceivers()
        if let videoTrack = transceivers.filter({ $0.direction != .sendOnly }).filter({ $0.mediaType == .video }).compactMap({ $0.receiver.track as? RTCVideoTrack }).last {
            await pictureInPictureViewController?.set(track: videoTrack)
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
                "id": participant.id as Any,
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
    
    private func handleStateChange(oldCall: Call?, newCall: Call?) async {
        switch (oldCall, newCall) {
        case (.none, .some(let call)):
            guard let user = call.participants.first(where: { $0.role == .user }) else {
                return assertionFailure("Failed to handle state change, no user participant")
            }

            switch user.state {
            case .none:
                addPictureInPictureViewController()

                let name = call.participants.first(where: { $0.role == .host})?.name
                let message = "\(name ?? "Someone") is inviting you to a call"
                await presentAlert(title: "Incoming Call", message: message, options: [
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
            case .joined:
                addPictureInPictureViewController()
                
                // Rejoin
                await join()

                let name = call.participants.first(where: { $0.role == .host})?.name
                let message = "You are in a call with \(name ?? "someone")"

                await MainActor.run {
                    presentAlert(title: "Continue Call", message: message, options: [
                        UIAlertAction(title: "Continue", style: .default) { [weak self] alertAction in
                            self?.startPictureInPicture()
                            Task { await self?.setPictureInPictureTrack() }
                        },
                        UIAlertAction(title: "End", style: .cancel) { [weak self] alertAction in
                            Task {
                                await self?.end()
                            }
                        }
                    ])
                }
            case .declined:
                print("user declined")
            }
        case (.some(let oldCall), .some(let newCall)):
            guard let oldUser = oldCall.participants.first(where: { $0.role == .user }), let newUser = newCall.participants.first(where: { $0.role == .user }) else {
                return assertionFailure("Failed to handle state change, no user participant")
            }
            
            guard newUser.state == .joined else {
                return
            }
            
            let oldVideoTrack = oldUser.tracks.first(where: { $0.type == .video })
            let newVideoTrack = newUser.tracks.first(where: { $0.type == .video })
                    
            if let oldTrack = oldVideoTrack, let newTrack = newVideoTrack {
                switch (oldTrack.state, newTrack.state) {
                case (.inactive, .requested):
                    await requestVideo()
                case (.active, .inactive):
                    await stopVideo()
                default:
                    break
                }
            }

            let oldScreenShareTrack = oldUser.tracks.first(where: { $0.type == .screenShare })
            let newScreenShareTrack = newUser.tracks.first(where: { $0.type == .screenShare })
            
            if let oldTrack = oldScreenShareTrack, let newTrack = newScreenShareTrack {
                switch (oldTrack.state, newTrack.state) {
                case (.inactive, .requested):
                    await requestScreenShare()
                case (.active, .inactive):
                    await stopScreenShare()
                default:
                    break
                }
                
                switch (newCall.touchIndicator.state, newTrack.state) {
                case (.active, .active):
                    TouchIndicator.enabled = .always
                default:
                    TouchIndicator.enabled = .never
                }
            }
                        
            let oldTracks = oldCall.participants.filter { $0.role == .host }.flatMap { $0.tracks }
            let newTracks = newCall.participants.filter { $0.role == .host }.flatMap { $0.tracks }
            
            if oldTracks != newTracks {
                await pullTracks()
            }
        case (.some(_), .none):
            await end()
        case (.none, .none):
            break
        }
    }
    
    private func requestVideo() async {
        func updateParticipant(state: Call.Participant.Track.State) async {
            guard case .some(let call) = self.state.read({ $0 }) else {
                return assertionFailure("Failed to handle state change, invalid call state")
            }
            
            guard let participant = call.participants.first(where: { $0.role == .user }) else {
                return
            }
            
            let data: [String: Any] = [
                "id": participant.id as Any,
                "name": participant.name,
                "state": participant.state.rawValue,
                "transceiverSessionId": participant.transceiverSessionId ?? "",
                "tracks": participant.tracks.map { track in
                    [
                        "id": track.id,
                        "state": track.type == .video ? state.rawValue : track.state.rawValue,
                        "type": track.type.rawValue
                    ]
                }
            ]
            
            let participantUpdate: [String: Any] = [
                "type": "participantUpdate",
                "participant": data
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: participantUpdate, options: .prettyPrinted)
                guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                    enum UserKitError: Error { case invalidJSON }
                    throw UserKitError.invalidJSON
                }
                try await webSocketClient.send(message: .string(jsonString))
            } catch {
                assertionFailure("Failed to handle state change, JSON invalid \(error)")
            }
        }
        
        guard await cameraClient.requestAccess() else {
            await updateParticipant(state: .inactive)
            return
        }
        
        await updateParticipant(state: .active)
        
        let stream = await cameraClient.start()
        for await buffer in stream {
            await webRTCClient.handleVideoSourceBuffer(sampleBuffer: buffer.sampleBuffer)
        }
    }
    
    private func stopVideo() async {
        await cameraClient.stop()
    }
    
    private func requestScreenShare() async {
        await MainActor.run {
            pictureInPictureViewController?.delegate = nil
        }
        await stopPictureInPicture()
        removePictureInPictureViewController()
        
        // Time for the view to be removed from the hierarchy
        try! await Task.sleep(nanoseconds: 50_000_000)
        
        func updateParticipant(state: Call.Participant.Track.State) async {
            guard case .some(let call) = self.state.read({ $0 }) else {
                return assertionFailure("Failed to handle state change, invalid call state")
            }
            
            guard let participant = call.participants.first(where: { $0.role == .user }) else {
                return
            }
            
            let data: [String: Any] = [
                "id": participant.id as Any,
                "name": participant.name,
                "state": participant.state.rawValue,
                "transceiverSessionId": participant.transceiverSessionId ?? "",
                "tracks": participant.tracks.map { track in
                    [
                        "id": track.id,
                        "state": track.type == .screenShare ? state.rawValue : track.state.rawValue,
                        "type": track.type.rawValue
                    ]
                }
            ]
            
            let participantUpdate: [String: Any] = [
                "type": "participantUpdate",
                "participant": data
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: participantUpdate, options: .prettyPrinted)
                guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                    enum UserKitError: Error { case invalidJSON }
                    throw UserKitError.invalidJSON
                }
                try await webSocketClient.send(message: .string(jsonString))
            } catch {
                assertionFailure("Failed to handle state change, JSON invalid \(error)")
            }
        }
        
        do {
            let recorder = RPScreenRecorder.shared()
            recorder.isMicrophoneEnabled = false
            recorder.isCameraEnabled = false
            
            var isRecording = false
            
            let started = { [weak self] in
                guard let self = self else { return }
                
                self.addPictureInPictureViewController()
                
                // Time for the view to be added to the hierarchy
                try! await Task.sleep(nanoseconds: 500_000_000)
                
                self.startPictureInPicture()
                await self.setPictureInPictureTrack()
                
                await updateParticipant(state: .active)
            }
            
            try await recorder.startCapture { [weak self] sampleBuffer, bufferType, error in
                Task {
                    await self?.webRTCClient.handleScreenShareSourceBuffer(sampleBuffer: sampleBuffer)
                }
                
                if !isRecording {
                    isRecording = true
                    Task { await started() }
                }
            }
        } catch {
            let recordingError = error as NSError
            switch (recordingError.domain, recordingError.code) {
            case (RPRecordingErrorDomain, -5801):
                await updateParticipant(state: .inactive)
    
            default:
                assertionFailure("Failed to handle video request: \(error)")
            }
        }
    }
    
    private func stopScreenShare() async {
        let recorder = RPScreenRecorder.shared()
        if recorder.isRecording {
            recorder.stopCapture()
        }
        
        TouchIndicator.enabled = .never
    }
}

extension CallManager: PictureInPictureViewControllerDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController) async -> Bool {
        guard case .some(let call) = state.read({ $0 }) else {
            return true
        }

        let name = call.participants.first(where: { $0.role == .host})?.name
        let message = "You are in a call with \(name ?? "someone")"

        await MainActor.run {
            presentAlert(title: "Continue Call", message: message, options: [
                UIAlertAction(title: "Continue", style: .default) { [weak self] alertAction in
                    self?.startPictureInPicture()
                    Task { await self?.setPictureInPictureTrack() }
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
