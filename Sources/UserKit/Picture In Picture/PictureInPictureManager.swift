//
//  PictureInPictureManager.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import Combine
import SwiftUI
import WebRTC

@MainActor class PictureInPictureManager: ObservableObject {
    enum State: Equatable {
        case starting
        case started
        case stopped
    }
    
    @Published var state: State = .stopped
    @Published var videoTrack: RTCVideoTrack?
    
    // Add a publisher for track changes
    let trackChanged = PassthroughSubject<RTCVideoTrack, Never>()
    
    init(state: State = .stopped, videoTrack: RTCVideoTrack? = nil) {
        self.state = state
        self.videoTrack = videoTrack
        
        // If videoTrack is provided in init, emit it
        if let track = videoTrack {
            self.trackChanged.send(track)
        }
    }
    
    func setVideoTrack(_ track: RTCVideoTrack) {
        print("PiP Manager: Setting video track \(track)")
        videoTrack = track
        
        // Notify subscribers about the new track
        trackChanged.send(track)
    }
    
    func start() {
        print("PiP Manager: Starting")
        state = .starting
    }
    
    func started() {
        print("PiP Manager: Started")
        state = .started
        
        // If we already have a video track when PiP starts, re-emit it to ensure it's attached
        if let track = videoTrack {
            trackChanged.send(track)
        }
    }
    
    func stopped() {
        print("PiP Manager: Stopped")
        state = .stopped
    }
    
    func restore() {
        print("PiP Manager: Restored")
        // Handle PiP restoration
        
        // If we have a video track when PiP is restored, re-emit it
        if let track = videoTrack {
            trackChanged.send(track)
        }
    }
}
