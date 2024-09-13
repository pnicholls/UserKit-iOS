//
//  File.swift
//  
//
//  Created by Peter Nicholls on 6/9/2024.
//

import Foundation
import Dependencies

public struct APIClient {
    public var postUser: @Sendable (_ data: UserRequest, _ apiKey: String) async throws -> UserResponse
}

extension APIClient {
    public struct UserRequest: Codable {
        let name: String?
        let email: String
        let appVersion: String?
    }
    
    public struct UserResponse: Codable {
        let accessToken: String
    }
}

let baseURL = "https://nato-glory-anticipated-cb.trycloudflare.com"

extension APIClient: DependencyKey {
    
    public static let liveValue: APIClient = {
        .init { data, apiKey in
            let url = URL(string: "\(baseURL)/api/v1/users")!
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpMethod = "POST"
            
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let json = try! encoder.encode(data)
            request.httpBody = json
            
            let (data, _) = try! await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            let response = try! decoder.decode(UserResponse.self, from: data)
            
            return response
        }
    }()
    
}

extension DependencyValues {
    
    public var apiClient: APIClient {
        get { self[APIClient.self] }
        set { self[APIClient.self] = newValue }
    }
    
}


//public class APIClient: ObservableObject {
//    
//    struct UserRequest: Codable {
//        let email: String
//    }
//    
//    struct UserResponse: Codable {
//        
//    }
//    
//    struct Track: Codable {
//        let location: String
//        let mid: String
//        let trackName: String
//    }
//    
//    struct SessionDescription: Codable {
//        let sdp: String
//        let type: String
//    }
//    
//    struct NewSessionRequest: Codable {
//        let sessionDescription: SessionDescription
//    }
//    
//    struct NewSessionResponse: Codable {
//        let sessionDescription: SessionDescription
//        let sessionId: String
//    }
//    
//    struct NewTracksRequest: Codable {
//        let tracks: [Track]
//        let sessionDescription: SessionDescription
//    }
//
//    struct NewTracksResponse: Codable {
//        let requiresImmediateRenegotiation: Bool
//        let tracks: [Track]
//        let sessionDescription: SessionDescription
//        
//        struct Track: Codable {
//            let mid: String
//            let trackName: String
//        }
//    }
//    
//    struct NewPullTracksRequest: Codable {
//        let tracks: [Track]
//        
//        struct Track: Codable {
//            let location: String
//            let trackName: String
//            let sessionId: String
//        }
//    }
//
//    struct RenegotiateRequest: Codable {
//        let sessionDescription: SessionDescription
//    }
//    
//    struct RenegotiateResponse: Codable {
//        
//    }
//    
//    private let baseURL: String
//    
//    init(baseURL: URL) {
//        self.baseURL = baseURL.absoluteString
//    }
//    
//    func postUser(data: UserRequest) async throws -> UserResponse {
//        let url = URL(string: "\(baseURL)/api/v1/users")!
//        var request = URLRequest(url: url)
//        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//        request.httpMethod = "POST"
//        
//        let encoder = JSONEncoder()
//        let json = try! encoder.encode(data)
//        request.httpBody = json
//        
//        let (data, _) = try! await URLSession.shared.data(for: request)
//        let decoder = JSONDecoder()
//        
//        let response = try! decoder.decode(UserResponse.self, from: data)
//        
//        return response
//    }
//    
//    func postSession(data: NewSessionRequest) async throws -> NewSessionResponse {
//        let url = URL(string: "\(baseURL)/api/v1/calls/sessions")!
//        var request = URLRequest(url: url)
//        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//        request.httpMethod = "POST"
//        
//        let encoder = JSONEncoder()
//        let json = try! encoder.encode(data)
//        request.httpBody = json
//        
//        let (data, _) = try! await URLSession.shared.data(for: request)
//        let decoder = JSONDecoder()
//        
//        let response = try! decoder.decode(NewSessionResponse.self, from: data)
//        
//        return response
//    }
//    
//    func postLocalTracks(sessionId: String, data: NewTracksRequest) async throws -> NewTracksResponse {
//        let url = URL(string: "\(baseURL)/api/v1/calls/sessions/\(sessionId)/tracks")!
//        var request = URLRequest(url: url)
//        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//        request.httpMethod = "POST"
//        
//        let encoder = JSONEncoder()
//        let json = try! encoder.encode(data)
//        request.httpBody = json
//        
//        let (data, _) = try! await URLSession.shared.data(for: request)
//        let decoder = JSONDecoder()
//        
//        let response = try! decoder.decode(NewTracksResponse.self, from: data)
//        
//        return response
//    }
//    
//    func pullTracks(sessionId: String, data: NewPullTracksRequest) async throws -> NewTracksResponse {
//        let url = URL(string: "\(baseURL)/api/v1/calls/sessions/\(sessionId)/tracks")!
//        var request = URLRequest(url: url)
//        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//        request.httpMethod = "POST"
//        
//        let encoder = JSONEncoder()
//        let json = try! encoder.encode(data)
//        request.httpBody = json
//        
//        let (data, _) = try! await URLSession.shared.data(for: request)
//        let decoder = JSONDecoder()
//        
//        let response = try! decoder.decode(NewTracksResponse.self, from: data)
//        
//        return response
//    }
//    
//    func renegotiate(sessionId: String, data: RenegotiateRequest) async throws -> RenegotiateResponse {
//        let url = URL(string: "\(baseURL)/api/v1/calls/sessions/\(sessionId)/renegotiate")!
//        var request = URLRequest(url: url)
//        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//        request.httpMethod = "PUT"
//        
//        let encoder = JSONEncoder()
//        let json = try! encoder.encode(data)
//        request.httpBody = json
//        
//        let (data, _) = try! await URLSession.shared.data(for: request)
//        let decoder = JSONDecoder()
//        
//        let response = try! decoder.decode(RenegotiateResponse.self, from: data)
//        
//        return response
//    }
//}
