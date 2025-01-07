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
    
    @Dependency(\.apiClient) var apiClient
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

struct ParticipantView: View {
    @Bindable var store: StoreOf<Participant>
    
    let viewId = UUID()

    var body: some View {
        ZStack {
             Color.black // Background color when no video
             
            if let videoTrack = store.tracks.first(where: { $0.trackType == .video })?.receiver?.track as? RTCVideoTrack {
                 RTCVideoView(track: videoTrack)
             }
         }
    }
}

struct RTCVideoView: UIViewRepresentable {
    let track: RTCVideoTrack
    
    func makeUIView(context: Context) -> RTCMTLVideoView {
        let videoView = RTCMTLVideoView(frame: .zero)
        track.add(videoView)
        
        return videoView
    }
    
    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        // No updates needed as the track handling is done in makeUIView
    }
}
