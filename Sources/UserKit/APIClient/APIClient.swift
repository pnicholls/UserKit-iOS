//
//  APIClient.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import Foundation

let baseURL = "https://getuserkit.com"

actor APIClient {
    private var accessToken: String?
    
    func setAccessToken(_ token: String) {
        self.accessToken = token
    }
    
    func request<T: Decodable>(apiKey: String, endpoint: Route, as type: T.Type) async throws -> T {
        let data = try await performRequest(apiKey, endpoint)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
    
    func request<T: Decodable>(endpoint: Route, as type: T.Type) async throws -> T {
        guard let token = accessToken else {
            throw APIError.missingAPIKey
        }
        
        let data = try await performRequest(token, endpoint)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
    
    private func performRequest(_ token: String, _ route: Route) async throws -> Data {
        guard let url = URL(string: route.url) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpMethod = route.method.rawValue
        
        let encoder = route.encoder
        
        if let body = route.body {
            let json = try encoder.encode(body)
            request.httpBody = json
            
            print("Raw JSON Request: \(String(data: json, encoding: .utf8) ?? "unable to decode")")
        }
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        // Print raw JSON response
        if let jsonString = String(data: data, encoding: .utf8) {
            print("Raw JSON Response: \(jsonString)")
        } else {
            print("Unable to convert response data to string")
        }
        
        return data
    }
    
    // Model types and request structure from original code
    enum Route: Equatable {
        enum Method: String {
            case get, post, put, delete
        }
        
        case postUser(UserRequest)
        case postSession(PostSessionRequest)
        case pullTracks(String, PullTracksRequest)
        case pushTracks(String, PushTracksRequest)
        case renegotiate(String, RenegotiateRequest)
                
        var url: String {
            switch self {
            case .postSession:
                "\(baseURL)/api/calls/sessions/new"
                
            case .postUser:
                "\(baseURL)/api/v1/users"
                
            case .pullTracks(let sessionId, _):
                "\(baseURL)/api/calls/sessions/\(sessionId)/tracks/new"

            case .pushTracks(let sessionId, _):
                "\(baseURL)/api/calls/sessions/\(sessionId)/tracks/new"
                
            case .renegotiate(let sessionId, _):
                "\(baseURL)/api/calls/sessions/\(sessionId)/renegotiate"
            }
        }
        
        var method: Method {
            switch self {
            case .postSession, .postUser, .pullTracks, .pushTracks:
                return .post
            case .renegotiate:
                return .put
            }
        }
        
        var body: Encodable? {
            switch self {
            case .postSession:
                return nil
            case .postUser(let request):
                return request
            case .pullTracks(_, let request):
                return request
            case .pushTracks(_, let request):
                return request
            case .renegotiate(_, let request):
                return request
            }
        }
        
        var encoder: JSONEncoder {
            let encoder = JSONEncoder()
            
            if case .postUser = self {
                encoder.keyEncodingStrategy = .convertToSnakeCase
            }
            
            return encoder
        }
    }
    
    enum APIError: Error {
        case invalidURL
        case missingAPIKey
    }
    
    // Request/Response Models
    struct PostSessionRequest: Codable, Equatable {}
    
    struct SessionDescription: Codable, Equatable {
        let sdp: String
        let type: String
    }
    
    struct PostSessionResponse: Codable, Equatable {
        let sessionId: String
    }
    
    struct UserRequest: Codable, Equatable {
        let id: String?
        let name: String?
        let email: String?
        let appVersion: String?
    }
    
    struct UserResponse: Codable, Equatable {
        let accessToken: String
        let webSocketUrl: URL
    }
    
    struct PullTracksRequest: Codable, Equatable {
        let tracks: [Track]
        
        struct Track: Codable, Equatable {
            let location: String
            let trackName: String
            let sessionId: String
        }
    }
    
    struct PullTracksResponse: Codable, Equatable {
        let requiresImmediateRenegotiation: Bool
        let tracks: [Track]
        let sessionDescription: SessionDescription?
        
        struct Track: Codable, Equatable {
            let mid: String
            let trackName: String
            let sessionId: String
            let errorCode: String?
            let errorDescription: String?
        }
        
        var failedTracks: [(trackName: String, error: String)] {
            return tracks.compactMap { track in
                guard let errorDescription = track.errorDescription else { return nil }
                return (track.trackName, errorDescription)
            }
        }
        
        var successfulTracks: [Track] {
            return tracks.filter { $0.errorCode == nil }
        }
    }
    
    struct PushTracksRequest: Codable, Equatable {
        let sessionDescription: SessionDescription
        let tracks: [Track]
        
        struct Track: Codable, Equatable {
            let location: String
            let trackName: String
            let mid: String
        }
    }
    
    struct PushTracksResponse: Codable, Equatable {
        let requiresImmediateRenegotiation: Bool
        let tracks: [Track]
        let sessionDescription: SessionDescription
        
        struct Track: Codable, Equatable {
            let mid: String
            let trackName: String
        }
    }
    
    struct RenegotiateRequest: Codable, Equatable {
        let sessionDescription: SessionDescription
    }
    
    struct RenegotiateResponse: Codable, Equatable {}
}
