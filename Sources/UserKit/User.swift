//
//  User.swift
//  UserKit
//
//  Created by Peter Nicholls on 16/11/2024.
//

import ComposableArchitecture
import SwiftUI

@Reducer
public struct User {
    
    @Dependency(\.apiClient) var apiClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.webSocketClient) var webSocketClient
    
    @ObservableState
    public struct State {
        let accessToken: String
        var call: Call.State?
        let webSocket: WebSocket
        
        public struct WebSocket: Equatable {
            public enum State: Equatable {
                case connected
                case connecting
                case disconnected
            }
            let state: State = .disconnected
            let url: URL
        }
    }
    
    public enum Action {
        case call(Call.Action)
        case webSocket(WebSocket)
        case `init`
        
        public enum WebSocket {
            case connect
            case client(WebSocketClient.Action)
            case receivedSocketMessage(Result<WebSocketClient.Message, any Error>)
        }
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .call:
                return .none
                                
            case .webSocket(.connect):
                switch state.webSocket.state {
                case .connected, .connecting:
                    return .none
                case .disconnected:
                    return .run { [state] send in
                        let actions = await webSocketClient.open(id: WebSocketClient.ID(), url: state.webSocket.url, protocols: [])
                        await withThrowingTaskGroup(of: Void.self) { group in
                            for await action in actions {
                                group.addTask { await send(.webSocket(.client(action))) }
                                switch action {
                                case .didOpen:
                                    group.addTask {
                                        while !Task.isCancelled {
                                            try await self.clock.sleep(for: .seconds(10))
                                            try? await self.webSocketClient.sendPing(id: WebSocketClient.ID())
                                        }
                                    }
                                    group.addTask {
                                        for await result in try await self.webSocketClient.receive(id: WebSocketClient.ID()) {
                                            await send(.webSocket(.receivedSocketMessage(result)))
                                        }
                                    }
                                case .didClose:
                                    return
                                }
                            }
                        }
                    }
                    .cancellable(id: WebSocketClient.ID())
                }
            
            case .webSocket(.client(.didClose)):
                return .none
                
            case .webSocket(.client(.didOpen)):
                return .none
                
            case .webSocket(.receivedSocketMessage(.failure)):
                return .none
                
            case .webSocket(.receivedSocketMessage(.success(.data))):
                assertionFailure("Unexpected data received")
                return .none
                
            case .webSocket(.receivedSocketMessage(.success(.string(let raw)))):
                let message = try? JSONDecoder().decode(User.State.WebSocket.Message.self, from: raw.data(using: .utf8)!)
                switch message {
                case .userState(let userState):
                    // TEMP HACK
                    if state.call != nil {
                        return .none
                    }
                    
                    var callState = state.call ?? .init(participants: [])
                    
                    callState.participants = .init(uniqueElements: userState.call?.participants.map({ participantState in
                        var participant = callState.participants[id: participantState.id] ??
                            .init(
                                id: participantState.id,
                                role: .init(rawValue: participantState.role.rawValue)!,
                                state: .init(rawValue: participantState.state.rawValue)!,
                                sessionId: participantState.transceiverSessionId ?? "placeholder-to-do",
                                tracks: []
                            )
                        participant.state = .init(rawValue: participantState.state.rawValue)!
                        
                        
                        // Tracks needs to update instead of being blown away
                        var tracks: [Participant.State.Track] = []
                        if let id = participantState.tracks.audio, let audioEnabled = participantState.tracks.audioEnabled {
                            let id = String(id.split(separator: "/")[1])
                            tracks.append(.init(id: id, trackType: .audio, isEnabled: audioEnabled))
                        }
                        if let id = participantState.tracks.video, let videoEnabled = participantState.tracks.videoEnabled {
                            let id = String(id.split(separator: "/")[1])
                            tracks.append(.init(id: id, trackType: .video, isEnabled: videoEnabled))
                        }
                        participant.tracks = .init(uniqueElements: tracks)
                        return participant
                    }) ?? [])
                    
                    state.call = callState
                    
                    return .none
                    
                default:
                    break
                }
                
                return .none
                                
            case .`init`:
                return .send(.webSocket(.connect))
            }
        }
        .ifLet(\.call, action: \.call) {
            Call()
        }
    }
}

public extension User.State.WebSocket {
    enum Message: Decodable {
        public struct UserState: Decodable {
            struct Call: Decodable {
                struct Participant: Decodable {
                    public enum State: String, Decodable {
                        case none
                        case declined
                        case joined
                    }
                    
                    public enum Role: String, Decodable {
                        case host
                        case user
                    }
                    
                    public struct Tracks: Decodable {
                        let audioEnabled: Bool?
                        let videoEnabled: Bool?
                        let screenShareEnabled: Bool?
                        let video: String?
                        let audio: String?
                    }

                    let id: String
                    let state: State
                    let role: Role
                    let tracks: Tracks
                    let transceiverSessionId: String?
                }
                let participants: [Participant]
            }
            let call: Call?
        }
        
        case pong
        case userState(UserState)
        case unknown
        
        enum CodingKeys: CodingKey {
            case type
            case state
        }
        
        enum CodingError: Error {
            case unknownType(Swift.DecodingError.Context)
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
         
            guard let type = try container.decodeIfPresent(String.self, forKey: .type) else {
                let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown type")
                throw CodingError.unknownType(context)
            }
            
            switch type {
            case "user-socket-pong":
                self = .pong
            case "userState":
                let state = try container.decode(Message.UserState.self, forKey: .state)
                self = .userState(state)
            default:
                self = .unknown
            }
        }
    }
}

struct UserView: View {
    @Bindable var store: StoreOf<User>

    var body: some View {
        if let store = store.scope(state: \.call, action: \.call) {
            CallViewControllerRepresentable(store: store)
        } else {
            EmptyView()
        }
    }
}
