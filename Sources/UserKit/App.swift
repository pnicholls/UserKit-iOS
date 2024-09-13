// The Swift Programming Language
// https://docs.swift.org/swift-book

import ComposableArchitecture
import SwiftUI

struct User: Equatable {
    let accessToken: String
}

@Reducer
struct App {
    
    @Dependency(\.apiClient) var apiClient
    @Dependency(\.webSocketClient) var webSocketClient
    @Dependency(\.webRTCClient) var webRTCClient
    
    @ObservableState
    struct State: Equatable {
        let config: Config
        var call: CallState = .unknown
        var user: UserState = .unauthenticated
        
        struct Config: Equatable {
            let apiKey: String
            let appId: String
            let webSocketUrl = "ws://nato-glory-anticipated-cb.trycloudflare.com/socket/users"
        }
        
        enum CallState: Equatable {
            case unknown
            case none
            case webSocketConnecting
            case webSocketConnected
            case joiningChannel
            case joinedChannel
            case webRTCConfiguring
            case webRTCConfigured
            case offering
            case offered
            case settingLocalDescription
            case setLocalDescription
            case pushingTracks
        }
        
        enum UserState: Equatable {
            case unauthenticated
            case authenticated(User)
        }
    }
    
    enum Action {
        case start
        case login(String, String)
        case api(Api)
        case webRTC(WebRTC)
        case webSocket(WebSocket)
        
        enum Api {
            case postUserResponse(Result<APIClient.UserResponse, Error>)
        }
        
        enum WebSocket {
            case connect
            case joinChannel
            case event(Result<WebSocketClient.Event, Error>)
            case pushTracks
        }
        
        enum WebRTC {
            case configure
            case configured
            case createOffer
            case offer(Result<WebRTCClient.SessionDescription, Error>)
            case setLocalDescription(WebRTCClient.SessionDescription)
            case localDescription(Result<WebRTCClient.SessionDescription, Error>)
            case setRemoteDescription(WebRTCClient.SessionDescription)
        }
    }
    
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .start:
                return .none

            case .login(let name, let email):
                return .run { [state] send in
                    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

                    await send(.api(.postUserResponse(Result {
                        try await apiClient.postUser(.init(name: name, email: email, appVersion: appVersion), state.config.apiKey)
                    })))
                }
                
            case .api(.postUserResponse(.success(let response))):
                state.user = .authenticated(.init(accessToken: response.accessToken))
                return .send(.webSocket(.connect))
                
            case .api(.postUserResponse(.failure(let error))):
                return .none
                
            case .webSocket(.connect):
                state.call = .webSocketConnecting
                
                guard case State.UserState.authenticated(let user) = state.user else {
                    fatalError("unauthenticated")
                }
                
                return .run { [state] send in
                    for try await event in await webSocketClient.connect(state.config.webSocketUrl, user.accessToken) {
                        await send(.webSocket(.event(.success(event))))
                    }
                }
                
            case .webSocket(.event(.success(.socket(.connected)))):
                state.call = .webSocketConnected
                return .send(.webSocket(.joinChannel))
                
            case .webSocket(.joinChannel):
                state.call = .joiningChannel
                guard case State.UserState.authenticated(let user) = state.user else {
                    fatalError("unauthenticated")
                }
                                    
                return .run { send in
                    for try await event in await webSocketClient.join("users/\(user.accessToken)") {
                        await send(.webSocket(.event(.success(event))))
                    }
                }
                
            case .webSocket(.event(.success(.channel(.joined)))):
                state.call = .joinedChannel
                return .send(.webRTC(.configure))
                
            case .webSocket(.event(.success(.channel(.push(let payload))))):
                let sessionDescription = payload["session_description"] as! [String: String]
                return .run { send in
                    await webRTCClient.setRemoteDescription(.init(sdp: sessionDescription["sdp"]!, type: .answer))
                }
                
            case .webSocket(.event(.failure(let error))):
                return .none
                
            case .webSocket(.pushTracks):
                state.call = .pushingTracks
                
                guard case State.UserState.authenticated(let user) = state.user else {
                    fatalError("unauthenticated")
                }
                
                return .run { send in
                    let sessionDescription = await webRTCClient.localDescription()
                    let transceivers = await webRTCClient.transceivers()
                    let tracks = transceivers.map { transceiver in
                        [
                            "location": transceiver.location,
                            "mid": transceiver.mid,
                            "trackName": transceiver.trackName ?? "unknown"
                        ]
                    }
                    for try await event in await webSocketClient.push("users/\(user.accessToken)", "push_tracks", ["sessionDescription": ["sdp": sessionDescription.sdp, "type": sessionDescription.type.rawValue], "tracks": tracks]) {
                        await send(.webSocket(.event(.success(event))))
                    }
                }
                
            case .webRTC(.configure):
                state.call = .webRTCConfiguring
                
                return .run { send in
                    await webRTCClient.configure()
                    await send(.webRTC(.configured))
                }
            
            case .webRTC(.configured):
                state.call = .webRTCConfigured
                return .send(.webRTC(.createOffer))
                
            case .webRTC(.createOffer):
                state.call = .offering
                return .run { send in
                    for try await event in await webRTCClient.offer() {
                        await send(.webRTC(.offer(.success(event))))
                    }
                }
                
            case .webRTC(.offer(.success(let sessionDescription))):
                state.call = .offered
                return .send(.webRTC(.setLocalDescription(sessionDescription)))
                
            case .webRTC(.setLocalDescription(let sessionDescription)):
                state.call = .settingLocalDescription
                return .run { send in
                    for try await event in await webRTCClient.setLocalDescription(sessionDescription) {
                        await send(.webRTC(.localDescription(.success(event))))
                    }
                }
                
            case .webRTC(.offer(.failure(let error))):
                return .none
                
            case .webRTC(.localDescription(.success(let sessionDescription))):
                state.call = .setLocalDescription
                return .send(.webSocket(.pushTracks))
                
            case .webRTC(.localDescription(.failure(let error))):
                return .none
                
            case .webRTC(.setRemoteDescription(let sessionDescription)):
                return .none
            }
            
        }.onChange(of: { $0.call }) { oldValue, newValue in
            Reduce { state, action in
                switch (oldValue, newValue) {
                case (.unknown, .webSocketConnecting):
                    return .none
                    
                case (.webSocketConnecting, .webSocketConnected):
                    return .none
                    
                case (.webSocketConnected, .joiningChannel):
                    return .none
                    
                case (.joiningChannel, .joinedChannel):
                    return .none
                    
                case (.joinedChannel, .webRTCConfiguring):
                    return .none
                    
                case (.webRTCConfiguring, .webRTCConfigured):
                    return .none
                
                case (.webRTCConfigured, .offering):
                    return .none
                    
                case (.offering, .offered):
                    return .none
                    
                case (.offered, .settingLocalDescription):
                    return .none
                    
                case (.settingLocalDescription, .setLocalDescription):
                    return .none
                    
                case (.setLocalDescription, .pushingTracks):
                    return .none
                    
                default:
                    fatalError("invalid call state \(oldValue) -> \(newValue)")
                }
            }
        }
    }
}


