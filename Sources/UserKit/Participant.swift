//
//  File.swift
//  
//
//  Created by Peter Nicholls on 23/10/2024.
//

import ComposableArchitecture
import SwiftUI
import WebRTC

@Reducer
public struct Participant {
    
    @Dependency(\.webRTCClient) var webRTCClient

    @ObservableState
    public struct State: Equatable, Identifiable {
        public struct Track: Equatable, Identifiable {
            public enum State {
                case notPulled
                case pulling
                case pulled
                case failed
            }

            public enum TrackType: String, Decodable {
                case video
                case audio
            }

            public let id: String
            public var state: State
            public let trackType: TrackType
            public var mid: String?
            public var receiver: RTCRtpReceiver?
            public var isEnabled: Bool
        }
        
        public enum Role: String, Decodable {
            case host
            case user
        }
        
        public enum State: String, Decodable {
            case none
            case declined
            case joined
        }
                
        public let id: String
        public let role: Role
        public var state: State
        public var sessionId: String
        public var tracks: IdentifiedArrayOf<Track>
    }
    
    public enum Action {
        case pullTracks
        case setReceiver(String, RTCRtpReceiver)
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .pullTracks:
                return .none
                
            case .setReceiver(let trackId, let receiver):
                state.tracks[id: trackId]?.receiver = receiver
                return .none
            }
        }
    }
}

extension Participant.State {
    mutating func updateTracks(from newTracks: User.State.WebSocket.Message.UserState.Call.Participant.Tracks) {
        if let audioId = newTracks.audio,
           let audioEnabled = newTracks.audioEnabled {
            let trackId = String(audioId.split(separator: "/")[1])
            
            if let existingTrack = tracks[id: trackId] {
                var updatedTrack = existingTrack
                updatedTrack.isEnabled = audioEnabled
                tracks.updateOrAppend(updatedTrack)
            } else {
                tracks.append(.init(id: trackId, state: .notPulled, trackType: .audio, isEnabled: audioEnabled))
            }
        }
        
        if let videoId = newTracks.video,
           let videoEnabled = newTracks.videoEnabled {
            let trackId = String(videoId.split(separator: "/")[1])
            
            if let existingTrack = tracks[id: trackId] {
                var updatedTrack = existingTrack
                updatedTrack.isEnabled = videoEnabled
                tracks.updateOrAppend(updatedTrack)
            } else {
                tracks.append(.init(id: trackId, state: .notPulled, trackType: .video, isEnabled: videoEnabled))
            }
        }
    }
}
