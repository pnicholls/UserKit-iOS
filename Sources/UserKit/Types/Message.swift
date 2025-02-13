//
//  File.swift
//  
//
//  Created by Peter Nicholls on 16/10/2024.
//

import Foundation

enum Message: Decodable {
    struct UserState: Decodable {
        let id: String
        let call: Call?
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

    struct Call: Equatable, Decodable {
        struct Participant: Decodable, Equatable {
            enum Role: String, Decodable {
                case host
                case user
            }
            
            let id: String
            let role: Role
            let transceiverSessionId: String?
            let tracks: [Track]
        }
        
        let participants: [Participant]
    }
    
    case userState(UserState)
    case userSocketPong
    case unknown
    
    enum CodingKeys: String, CodingKey {
        case type
        case state
    }
    
    enum MessageType: String, Decodable, Equatable {
        case userState = "userState"
        case userSocketPong = "user-socket-pong"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(MessageType.self, forKey: .type)
        
        switch type {
        case .userState:
            let state = try container.decode(UserState.self, forKey: .state)
            self = .userState(state)
        case .userSocketPong:
            self = .userSocketPong
        case .none:
            self = .unknown
        }
    }
}
