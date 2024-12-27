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

    struct Call: Equatable, Decodable {
        struct Participant: Decodable, Equatable {
            enum Role: String, Decodable {
                case host
                case user
            }
            
            let id: String
            let role: Role
            let transceiverSessionId: String?
            let tracks: Tracks
        }
        
        let participants: [Participant]
    }

    case userState(UserState)
    case unknown
    
    enum CodingKeys: String, CodingKey {
        case type
        case state
    }
    
    enum MessageType: String, Decodable, Equatable {
        case userState
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(MessageType.self, forKey: .type)
        
        switch type {
        case .userState:
            let state = try container.decode(UserState.self, forKey: .state)
            self = .userState(state)
        case .none:
            self = .unknown
        }
    }
}

public struct Tracks: Decodable, Equatable {
    let audioEnabled: Bool?
    let videoEnabled: Bool?
    let screenShareEnabled: Bool?
    let video: String?
    let audio: String?
}
