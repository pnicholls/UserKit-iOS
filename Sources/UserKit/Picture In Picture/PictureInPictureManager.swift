//
//  PictureInPictureManager.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

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
    
    init(state: State = .stopped, videoTrack: RTCVideoTrack? = nil) {
        self.state = state
        self.videoTrack = videoTrack
    }
    
    func setVideoTrack(_ track: RTCVideoTrack) {
        videoTrack = track
    }
    
    func start() {
        state = .starting
    }
    
    func started() {
        state = .started
    }
    
    func stopped() {
        state = .stopped
    }
    
    func restore() {
        // Handle PiP restoration
    }
}
