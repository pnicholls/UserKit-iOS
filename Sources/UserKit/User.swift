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
    @Dependency(\.webRTCClient) var webRTCClient
    
    @ObservableState
    public struct State: Equatable {
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
                    guard let call = userState.call else {
                        break
                    }
                                                            
                    if state.call == nil {
                        state.call = .init(callState: .requested(.init()), participants: [])
                    }
                    
                    state.call?.participants = .init(uniqueElements: call.participants.map {
                        .init(
                            id: $0.id,
                            role: .init(rawValue: $0.role.rawValue)!,
                            state: .init(rawValue: $0.state.rawValue)!
                        )
                    })
                    
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
                    
                    let id: String
                    let state: State
                    let role: Role
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
            CallView(store: store)
        } else {
            EmptyView()
        }
    }
}
