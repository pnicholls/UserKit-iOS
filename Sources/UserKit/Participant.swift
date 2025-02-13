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
        public var sessionId: String?
        public var tracks: IdentifiedArrayOf<Track.State>
    }
    
    public enum Action {
        case `init`
        case pullTracks
        case setReceiver(String, RTCRtpReceiver)
        case tracks(IdentifiedActionOf<Track>)
        case update(User.State.WebSocket.Message.UserState.Call.Participant)
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .`init`:
                return .merge(state.tracks.map { .send(.tracks(.element(id: $0.id, action: .`init`))) })
                
            case .pullTracks:
                return .none
                
            case .setReceiver(let trackId, let receiver):
                state.tracks[id: trackId]?.receiver = receiver
                return .none
                
            case .tracks:
                return .none
                
            case .update(let participant):
                state.sessionId = participant.transceiverSessionId
                state.state = .init(rawValue: participant.state.rawValue)!
                
                let newTracks: [Track.State] = participant.tracks.compactMap { track in
                    guard let id = track.id else { return nil }
                    
                    if let _ = state.tracks[id: id] {
                        return nil
                    }
                    
                    return .init(
                        id: String(id.split(separator: "/")[1]),
                        state: .init(rawValue: track.state.rawValue)!,
                        pullState: .notPulled,
                        pushState: .pushed,
                        type: .init(rawValue: track.type.rawValue)!
                    )
                }
                
                state.tracks.append(contentsOf: newTracks)
                
                let existingTracks: [(Track.State, User.State.WebSocket.Message.UserState.Call.Participant.Track)] = participant.tracks.compactMap { existingTrack in
                    guard let id = existingTrack.id, let track = state.tracks[id: String(id.split(separator: "/")[1])] else {
                        return nil
                    }
                    return (track, existingTrack)
                }
                
                return .merge(
                    .merge(newTracks.map { .send(.tracks(.element(id: $0.id, action: .`init`))) }),
                    .merge(existingTracks.map { .send(.tracks(.element(id: $0.0.id, action: .update($0.1)))) })
                )
            }
        }
        .forEach(\.tracks, action: \.tracks) {
            Track()
        }
        .onChange(of: { $0.tracks }) { oldValue, newValue in
            Reduce { state, action in
                return .none
            }
        }
    }
}
