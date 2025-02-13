//
//  User.swift
//  UserKit
//
//  Created by Peter Nicholls on 16/11/2024.
//

import ComposableArchitecture
import SwiftUI

import ReplayKit

@Reducer
public struct User {
    
    @Dependency(\.apiClient) var apiClient
    @Dependency(\.cameraClient) var cameraClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.webRTCClient) var webRTCClient
    @Dependency(\.webSocketClient) var webSocketClient
    
    @ObservableState
    public struct State: Equatable {
        let accessToken: String
        var call: Call.State?
        var webSocket: WebSocket
        
        public struct WebSocket: Equatable {
            public enum State: Equatable {
                case connected
                case connecting
                case disconnected
            }
            var state: State = .disconnected
            let url: URL
        }
    }
    
    public enum Action {
        case call(Call.Action)
        case webSocket(WebSocket)
        case `init`
        
        @CasePathable
        public enum WebSocket {
            case connect
            case client(WebSocketClient.Action)
            case disconnect
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
                    return .cancel(id: WebSocketClient.ID())
                    
                case .disconnected:
                    state.webSocket.state = .connecting
                    
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
                state.webSocket.state = .disconnected
                return .cancel(id: WebSocketClient.ID())

            case .webSocket(.client(.didOpen)):
                state.webSocket.state = .connected
                return .none
            
            case .webSocket(.disconnect):
                return .cancel(id: WebSocketClient.ID())
                
            case .webSocket(.receivedSocketMessage(.failure)):
                return .none
                
            case .webSocket(.receivedSocketMessage(.success(.data))):
                assertionFailure("Unexpected data received")
                return .none
                
            case .webSocket(.receivedSocketMessage(.success(.string(let raw)))):
                let message = try! JSONDecoder().decode(User.State.WebSocket.Message.self, from: raw.data(using: .utf8)!)
                switch message {
                case .pong:
                    return .none
                    
                case .userState(let userState) where userState.call == nil:
                    state.call = nil
                    return .run { send in
                        await webRTCClient.close()
                        await cameraClient.stop()
                        
                        // TODO - audioClient
                    }
                    
                case .userState(let userState):
                    state.call = state.call ?? .init(participants: [])
                    
                    let newParticipants = (userState.call?.participants ?? []).filter {
                        state.call?.participants[id: $0.id] == nil
                    }.map { participant in
                        Participant.State(
                            id: participant.id,
                            role: .init(rawValue: participant.role.rawValue)!,
                            state: .init(rawValue: participant.state.rawValue)!,
                            sessionId: participant.transceiverSessionId,
                            tracks: .init(uniqueElements: participant.tracks.compactMap { track in
                                guard let id = track.id else { return nil }
                                
                                return .init(
                                    id: String(id.split(separator: "/")[1]),
                                    state: .init(rawValue: track.state.rawValue)!,
                                    pullState: .notPulled,
                                    pushState: .pushed,
                                    type: .init(rawValue: track.type.rawValue)!
                                )
                            })
                        )
                    }
                    
                    state.call?.participants.append(contentsOf: newParticipants)
                    
                    let existingParticipants = (userState.call?.participants ?? []).filter { participant in
                        state.call?.participants[id: participant.id] != nil
                    }
                    
                    return .merge(
                        .merge(newParticipants.map { .send(.call(.participants(.element(id: $0.id, action: .`init`)))) }),
                        .merge(existingParticipants.map { .send(.call(.participants(.element(id: $0.id, action: .update($0))))) })
                    )
                    
                case .unknown:
                    fatalError("Unknown webSocket message received")
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
            public struct Call: Decodable {
                public struct Participant: Decodable {
                    public enum State: String, Decodable {
                        case none
                        case declined
                        case joined
                    }
                    
                    public enum Role: String, Decodable {
                        case host
                        case user
                    }
                    
                    public struct Track: Decodable, Equatable {
                        public enum State: String, Decodable {
                            case active, requested, inactive
                        }
                        
                        public enum TrackType: String, Decodable {
                            case audio, video, screenShare
                        }
                        
                        public let state: State
                        public let id: String?
                        public let type: TrackType
                    }

                    let id: String
                    let state: State
                    let role: Role
                    let tracks: [Track]
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
    @Perception.Bindable var store: StoreOf<User>

    var body: some View {
        WithPerceptionTracking {
            if let store = store.scope(state: \.call, action: \.call) {
                CallViewControllerRepresentable(store: store)
            } else {
                EmptyView()
            }
        }
    }
}
