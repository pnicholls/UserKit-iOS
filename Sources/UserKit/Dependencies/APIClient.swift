//
//  File.swift
//  
//
//  Created by Peter Nicholls on 6/9/2024.
//

//
//  File.swift
//
//
//  Created by Peter Nicholls on 6/9/2024.
//

import ComposableArchitecture
import Foundation

let baseURL = "https://buy-corresponding-dropped-really.trycloudflare.com"

actor APIClientState {
    private var accessToken: String?
    
    func setAccessToken(_ accessToken: String) {
        self.accessToken = accessToken
    }
    
    func getAccessToken() -> String? {
        return accessToken
    }
}

public struct APIClient {
    private let state: APIClientState
    var _request: (String, APIClient.Route) async throws -> Data
    
    init(state: APIClientState = APIClientState(), request: @escaping (String, APIClient.Route) async throws -> Data) {
        self.state = state
        self._request = request
    }
    
    func setAccessToken(_ accessToken: String) async {
        await state.setAccessToken(accessToken)
    }
    
    func request<T: Decodable>(apiKey: String, endpoint: APIClient.Route, as type: T.Type) async throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        return try await decoder.decode(T.self, from: self._request(apiKey, endpoint))
    }
  
    func request<T: Decodable>(endpoint: APIClient.Route, as type: T.Type) async throws -> T {
        guard let accessToken = await state.getAccessToken() else {
            throw APIError.missingAPIKey
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        return try await decoder.decode(T.self, from: self._request(accessToken, endpoint))
    }
}

extension APIClient {
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
            case .postSession:
                return .post
                
            case .postUser:
                return .post
                
            case .pullTracks:
                return .post
                
            case .pushTracks:
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
            switch self {
            case .postSession:
                return JSONEncoder()
                
            case .pullTracks:
                return JSONEncoder()
                
            case .pushTracks:
                return JSONEncoder()
                
            case .renegotiate:
                return JSONEncoder()
                
            default:
                let encoder = JSONEncoder()
                encoder.keyEncodingStrategy = .convertToSnakeCase
                return encoder
            }
        }
    }
        
    enum APIError: Error {
        case invalidURL
        case missingAPIKey
    }
}

extension APIClient {
    struct PostSessionRequest: Codable, Equatable {}
    
    public struct SessionDescription: Codable, Equatable {
        let sdp: String
        let type: String
    }
    
    public struct PostSessionResponse: Codable, Equatable {
        let sessionId: String
    }
    
    struct UserRequest: Codable, Equatable {
        let id: String?
        let name: String?
        let email: String?
        let appVersion: String?
    }
    
    public struct UserResponse: Codable, Equatable {
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
    
    public struct PullTracksResponse: Codable {
        let requiresImmediateRenegotiation: Bool
        let tracks: [Track]
        let sessionDescription: SessionDescription
        
        struct Track: Codable {
            let mid: String
            let trackName: String
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
    
    public struct PushTracksResponse: Codable {
        let requiresImmediateRenegotiation: Bool
        let tracks: [Track]
        let sessionDescription: SessionDescription
        
        struct Track: Codable {
            let mid: String
            let trackName: String
        }
    }
    
    public struct RenegotiateRequest: Codable, Equatable {
        let sessionDescription: SessionDescription
    }
    
    public struct RenegotiateResponse: Codable {}
}

extension APIClient: DependencyKey {
    public static var liveValue: APIClient {
        return Self(request: { accessToken, route in
            guard let url = URL(string: route.url) else {
                throw APIError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.httpMethod = route.method.rawValue

            let encoder = route.encoder
            
            if let body = route.body {
                let json = try! encoder.encode(body)
                request.httpBody = json
            }
                    
            let (data, _) = try await URLSession.shared.data(for: request)
            
            return data
        })
    }
}

// MARK: - Dependency

extension DependencyValues {
    var apiClient: APIClient {
        get { self[APIClient.self] }
        set { self[APIClient.self] = newValue}
    }
}
