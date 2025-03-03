//
//  TrackManager.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import SwiftUI

@MainActor class TrackManager: ObservableObject, Identifiable {
    let id: String
    @Published var state: State
    @Published var pullState: PullState
    @Published var pushState: PushState
    let type: TrackType
    @Published var mid: String?
    
    private let webRTCClient: WebRTCClient
    private let cameraClient = CameraClient()
    private let screenRecorderClient = ScreenRecorderClient()
    
    enum PullState: Equatable {
        enum Error: String, Equatable {
            case emptyTrack = "empty_track_error"
            case `internal` = "internal_error"
            case sessionNotReady = "session_error"
            case unknown
        }
        
        case notPulled
        case pulling
        case pulled
        case failed(Error)
    }
    
    enum PushState: Equatable {
        case notPushed
        case pushing
        case pushed
        case failed
    }
    
    enum State: String, Equatable {
        case inactive
        case requested
        case active
    }
    
    enum TrackType: String {
        case video
        case audio
        case screenShare
    }
    
    init(id: String, state: State, pullState: PullState, pushState: PushState, type: TrackType, webRTCClient: WebRTCClient) {
        self.id = id
        self.state = state
        self.pullState = pullState
        self.pushState = pushState
        self.type = type
        self.webRTCClient = webRTCClient
        
        // Monitor state changes
        observeStateChanges()
    }
    
    private func observeStateChanges() {
        Task { [weak self] in
            guard let self = self else { return }
            
            // Simple way to observe state changes in a reactive way
            let initialState = self.state
            
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                let newState = self.state
                if initialState == .inactive && newState == .requested {
                    await self.request()
                }
            }
        }
    }
    
    func pull() async {
        // Pulling track logic - would be called from participant manager
    }
    
    func pulled(_ track: APIClient.PullTracksResponse.Track) {
        pullState = .pulled
        mid = track.mid
    }
    
    func request() async {
        switch type {
        case .audio:
            // Handle audio request
            break
            
        case .screenShare:
            // Handle screen share request
            break
            
        case .video:
            let hasAccess = await cameraClient.requestAccess()
            
            if hasAccess {
                await requestAccepted()
            } else {
                await requestRejected()
            }
        }
    }
    
    func requestAccepted() async {
        switch type {
        case .video:
            let videoStream = await cameraClient.start()
            
            Task {
                for try await buffer in videoStream {
                    await webRTCClient.handleVideoSourceBuffer(sampleBuffer: buffer.sampleBuffer)
                }
            }
            
        default:
            break
        }
    }
    
    func requestRejected() async {
        // Handle rejection
    }
    
    func start() async {
        switch type {
        case .screenShare:
            Task {
                do {
                    let stream = await screenRecorderClient.start()
                    for try await buffer in stream {
                        await webRTCClient.handleScreenShareSourceBuffer(sampleBuffer: buffer.sampleBuffer)
                    }
                } catch {
                    // Handle errors
                    print("Screen recording error: \(error)")
                }
            }
            
            // Simulate acceptance after a delay
            Task {
                try await Task.sleep(nanoseconds: 3 * 1_000_000_000)
                await requestAccepted()
            }
            
        default:
            break
        }
    }
}
