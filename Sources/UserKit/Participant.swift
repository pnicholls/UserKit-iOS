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
            public enum TrackType: String, Decodable {
                case video
                case audio
            }

            public let id: String
            let trackType: TrackType
            var mid: String?
            var receiver: RTCRtpReceiver?
            let isEnabled: Bool
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
        case setReceiver(String, RTCRtpReceiver)
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .setReceiver(let trackId, let receiver):
                state.tracks[id: trackId]?.receiver = receiver
                return .none
            }
        }
    }
}
