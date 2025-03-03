//
//  ParticipantManager.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import SwiftUI

@MainActor class ParticipantManager: ObservableObject, Identifiable {
    let id: String
    let role: Role
    @Published var state: State
    @Published var sessionId: String?
    @Published var tracks: [TrackManager]
    
    private let webRTCClient: WebRTCClient
    
    enum Role: String {
        case host
        case user
    }
    
    enum State: String {
        case none
        case declined
        case joined
    }
    
    init(id: String, role: Role, state: State, sessionId: String?, tracks: [TrackManager], webRTCClient: WebRTCClient) {
        self.id = id
        self.role = role
        self.state = state
        self.sessionId = sessionId
        self.tracks = tracks
        self.webRTCClient = webRTCClient
    }
    
    func updateTracks(from tracksData: [[String: Any]]) async {
        for trackData in tracksData {
            guard let trackId = trackData["id"] as? String,
                  let typeString = trackData["type"] as? String,
                  let stateString = trackData["state"] as? String,
                  let type = TrackManager.TrackType(rawValue: typeString),
                  let state = TrackManager.State(rawValue: stateString) else {
                continue
            }
            
            // Extract track ID from full path
            let parsedTrackId = String(trackId.split(separator: "/").last ?? "")
            
            // Update existing track
            if let index = tracks.firstIndex(where: { $0.id == parsedTrackId }) {
                tracks[index].state = state
            } else {
                // Create new track
                let track = TrackManager(
                    id: parsedTrackId,
                    state: state,
                    pullState: .notPulled,
                    pushState: .pushed,
                    type: type,
                    webRTCClient: webRTCClient
                )
                
                tracks.append(track)
                
                // Initialize track if needed
                if track.pullState == .notPulled {
                    await track.pull()
                }
            }
        }
    }
}
