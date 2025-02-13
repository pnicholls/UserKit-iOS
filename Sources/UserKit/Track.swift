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
public struct Track {
    
    @Dependency(\.cameraClient) var cameraClient
    @Dependency(\.screenRecorderClient) var screenRecorderClient
    @Dependency(\.webRTCClient) var webRTCClient
    
    @ObservableState
    public struct State: Equatable, Identifiable {
        public enum PullState: Equatable {
            public enum Error: String, Equatable, Decodable {
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
        
        public enum PushState: Equatable {
            case notPushed
            case pushing
            case pushed
            case failed
        }
        
        public enum State: String, Equatable {
            case inactive
            case requested
            case active
        }

        public enum TrackType: String, Decodable {
            case video
            case audio
            case screenShare
        }

        public var id: String
        public var state: State
        public var pullState: PullState
        public var pushState: PushState
        public let type: TrackType
        public var mid: String?
        public var receiver: RTCRtpReceiver?
    }
    
    public enum Action {
        case `init`
        case pull
        case request
        case requestAccepted
        case requestRejected
        case update(User.State.WebSocket.Message.UserState.Call.Participant.Track)
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .requestAccepted:
                switch state.type {
                case .video:
                    return .run { send in
                        for try await buffer in await cameraClient.start() {
                            await webRTCClient.handleVideoSourceBuffer(buffer.sampleBuffer)
                        }
                    }
                default:
                    return .none
                }
                
            case .requestRejected:
                return .none
                
            case .`init`:
                switch state.pullState {
                case .notPulled:
                    return .send(.pull)
                default:
                    break
                }
                
                return .none
                
            case .pull:
                return .none
                
            case .request:
                switch state.type {
                case .audio:
                    break
                    
                case .screenShare:
                    return .merge(
                        .run { send in
                            do {
                                let task = await screenRecorderClient.start()
                                for try await buffer in task {
                                    await webRTCClient.handleScreenShareSourceBuffer(buffer.sampleBuffer)
                                }
                            } catch {
                                // TODO: - Handle reject permission
                            }
                        },
                        .run { send in
                            // TODO - This won't work
                            try await Task.sleep(for: .seconds(3))
                            await send(.requestAccepted)
                        }
                    )
                    
                case .video:
                    return .run { send in
                        let result = await cameraClient.requestAccess()
                        await send(result ? .requestAccepted : .requestRejected)
                    }
                }
                return .none
                
            case .update(let track):
                state.state = .init(rawValue: track.state.rawValue)!
                return .none
            }
        }
        .onChange(of: { $0.state }) { oldValue, newValue in
            Reduce { state, action in
                switch (oldValue, newValue) {
                case (.inactive, .requested):
                    return .send(.request)
                default:
                    break
                }
                
                return .none
            }
        }
    }
}
