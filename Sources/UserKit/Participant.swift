//
//  File.swift
//  
//
//  Created by Peter Nicholls on 23/10/2024.
//

import ComposableArchitecture
import SwiftUI
//import WebRTC

@Reducer
public struct Participant {
    
    @Dependency(\.apiClient) var apiClient
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
        public let state: State
    }
    
    public enum Action: Sendable {
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            return .none
        }
    }
}
