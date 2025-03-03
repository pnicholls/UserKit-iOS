//
//  CallManager.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import SwiftUI

@MainActor class CallManager: ObservableObject {
    private let apiClient: APIClient
    private let webRTCClient: WebRTCClient
    private let webSocketClient: WebSocketClient
    
    @Published var alert: AlertInfo?
    @Published var pictureInPicture: PictureInPictureManager?
    @Published var participants: [ParticipantManager] = []
    @Published var sessionId: String?
    
    private var callTask: Task<Void, Error>?
    
    struct AlertInfo {
        let title: String
        let acceptText: String
        let declineText: String
    }
    
    init(apiClient: APIClient, webRTCClient: WebRTCClient, webSocketClient: WebSocketClient, alert: AlertInfo? = nil) {
        self.apiClient = apiClient
        self.webRTCClient = webRTCClient
        self.webSocketClient = webSocketClient
        self.alert = alert
        
        initialize()
    }
    
    private func initialize() {
        callTask = Task {
            do {
                let response = try await apiClient.request(
                    endpoint: .postSession(.init()),
                    as: APIClient.PostSessionResponse.self
                )
                
                sessionId = response.sessionId
                
                // If user has already accepted, configure WebRTC
                if let userParticipant = participants.first(where: { $0.role == .user }),
                   userParticipant.state == .joined {
                    try await configureWebRTC()
                }
            } catch {
                print("Failed to initialize call: \(error)")
            }
        }
    }
    
    func acceptCall() async {
        alert = nil
        pictureInPicture = PictureInPictureManager()
        
        // Find and update user participant
        if let index = participants.firstIndex(where: { $0.role == .user }) {
            participants[index].state = .joined
            
            if sessionId != nil {
                try? await configureWebRTC()
            }
        }
    }
    
    func declineCall() async {
        if let index = participants.firstIndex(where: { $0.role == .user }) {
            participants[index].state = .declined
        }
    }
    
    func continueCall() async {
        pictureInPicture = PictureInPictureManager(state: .starting, videoTrack: nil)
        alert = nil
        
        // Find video tracks for PiP
        Task {
            let transceivers = await webRTCClient.transceivers()
            
            for participant in participants.filter({ $0.role == .host }) {
                for track in participant.tracks.filter({ $0.type == .video && $0.mid != nil && $0.pullState == .pulled }) {
                    if let videoTrack = transceivers.filter({ $0.mediaType == .video }).first(where: { $0.mid == track.mid })?.receiver.track as? RTCVideoTrack {
                        await pictureInPicture?.setVideoTrack(videoTrack)
                    }
                }
            }
        }
    }
    
    func endCall() async {
        alert = nil
        
        Task {
            await webRTCClient.close()
            // Clean up other resources
        }
    }
    
    func updateParticipants(from participantsData: [[String: Any]]) async {
        for participantData in participantsData {
            guard let id = participantData["id"] as? String,
                  let roleString = participantData["role"] as? String,
                  let stateString = participantData["state"] as? String,
                  let role = ParticipantManager.Role(rawValue: roleString),
                  let state = ParticipantManager.State(rawValue: stateString) else {
                continue
            }
            
            let sessionId = participantData["transceiverSessionId"] as? String
            
            // Handle existing participant
            if let index = participants.firstIndex(where: { $0.id == id }) {
                participants[index].state = state
                participants[index].sessionId = sessionId
                
                // Update tracks
                if let tracksData = participantData["tracks"] as? [[String: Any]] {
                    await participants[index].updateTracks(from: tracksData)
                }
            } else {
                // Create new participant
                let tracks: [TrackManager] = []
                let newParticipant = ParticipantManager(
                    id: id,
                    role: role,
                    state: state,
                    sessionId: sessionId,
                    tracks: tracks,
                    webRTCClient: webRTCClient
                )
                
                participants.append(newParticipant)
                
                // Initialize tracks
                if let tracksData = participantData["tracks"] as? [[String: Any]] {
                    await newParticipant.updateTracks(from: tracksData)
                }
            }
        }
    }
    
    private func configureWebRTC() async throws {
        do {
            try await webRTCClient.configure()
            await participantJoined()
            await pushTracks()
        } catch {
            throw error
        }
    }
    
    private func participantJoined() async {
        do {
            let message: [String: Any] = ["type": "participantJoined"]
            let jsonData = try JSONSerialization.data(withJSONObject: message, options: .prettyPrinted)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                try await webSocketClient.send(message: .string(jsonString))
            }
        } catch {
            print("Failed to send participant joined message: \(error)")
        }
    }
    
    private func pushTracks() async {
        guard let sessionId = sessionId else {
            assertionFailure("Session ID must be set")
            return
        }
        
        do {
            let offer = try await webRTCClient.createOffer()
            let localDescription = try await webRTCClient.setLocalDescription(offer)
            
            let transceivers = await webRTCClient.localTransceivers()
            
            let tracks = transceivers.map { type, transceiver in
                APIClient.PushTracksRequest.Track(
                    location: "local",
                    trackName: transceiver.sender.track!.trackId,
                    mid: transceiver.mid
                )
            }
            
            guard !tracks.isEmpty else { return }
            
            let response = try await apiClient.request(
                endpoint: .pushTracks(sessionId, .init(
                    sessionDescription: .init(sdp: localDescription.sdp, type: "offer"),
                    tracks: tracks
                )),
                as: APIClient.PushTracksResponse.self
            )
            
            await webRTCClient.setRemoteDescription(.init(sdp: response.sessionDescription.sdp, type: .answer))
            
            // Update tracks for user participant
            guard let participant = participants.first(where: { $0.role == .user }) else { return }
            
            let localTracks: [[String: Any]] = await webRTCClient.localTransceivers().map { type, transceiver in
                [
                    "id": "\(sessionId)/\(transceiver.sender.track!.trackId)",
                    "type": type,
                    "state": "inactive"
                ]
            }
            
            let data: [String: Any] = [
                "state": participant.state.rawValue,
                "transceiverSessionId": sessionId,
                "tracks": localTracks
            ]
            
            let participantUpdate: [String: Any] = [
                "type": "participantUpdate",
                "participant": data
            ]
            
            let jsonData = try JSONSerialization.data(withJSONObject: participantUpdate, options: .prettyPrinted)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                try await webSocketClient.send(message: .string(jsonString))
            }
            
            await pullTracks()
        } catch {
            print("Failed to push tracks: \(error)")
        }
    }
    
    private func pullTracks() async {
        guard let sessionId = sessionId else { return }
        
        var tracks: [APIClient.PullTracksRequest.Track] = []
        
        // Find tracks to pull
        for participant in participants.filter({ $0.role == .host }) {
            guard let participantSessionId = participant.sessionId else { continue }
            
            for track in participant.tracks.filter({ $0.pullState == .notPulled }) {
                track.pullState = .pulling
                
                tracks.append(APIClient.PullTracksRequest.Track(
                    location: "remote",
                    trackName: track.id,
                    sessionId: participantSessionId
                ))
            }
        }
        
        guard !tracks.isEmpty else { return }
        
        do {
            let pullTracksResponse = try await apiClient.request(
                endpoint: .pullTracks(sessionId, .init(tracks: tracks)),
                as: APIClient.PullTracksResponse.self
            )
            
            if let sessionDescription = pullTracksResponse.sessionDescription,
               pullTracksResponse.requiresImmediateRenegotiation {
                
                await webRTCClient.setRemoteDescription(.init(sdp: sessionDescription.sdp, type: .offer))
                let answer = try await webRTCClient.createAnswer()
                let localDescription = try await webRTCClient.setLocalDescription(answer)
                
                _ = try await apiClient.request(
                    endpoint: .renegotiate(sessionId, .init(
                        sessionDescription: .init(sdp: localDescription.sdp, type: "answer")
                    )),
                    as: APIClient.RenegotiateResponse.self
                )
                
                // Update track states
                for track in pullTracksResponse.tracks {
                    for participant in participants {
                        if let trackIndex = participant.tracks.firstIndex(where: { $0.id == track.trackName }) {
                            participant.tracks[trackIndex].pullState = .pulled
                            participant.tracks[trackIndex].mid = track.mid
                        }
                    }
                }
            }
        } catch {
            print("Failed to pull tracks: \(error)")
        }
    }
}
