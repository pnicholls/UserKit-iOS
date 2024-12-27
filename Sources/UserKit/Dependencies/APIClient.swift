//
//  File.swift
//  
//
//  Created by Peter Nicholls on 6/9/2024.
//

import ComposableArchitecture
import Foundation

let baseURL = "https://tournaments-promises-sorts-ada.trycloudflare.com/api/v1"

public struct APIClient {
    var _request: (String, APIClient.Route) async throws -> Data
  
    func request<T: Decodable>(apiKey: String, endpoint: APIClient.Route, as type: T.Type) async throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        return try await decoder.decode(T.self, from: self._request(apiKey, endpoint))
    }
}

extension APIClient {
    enum Route: Equatable {
        enum Method: String {
            case get, post, put, delete
        }
        
        case postUser(UserRequest)
                
        var url: String {
            switch self {
            case .postUser:
                "\(baseURL)/users"
            }
        }
        
        var method: Method {
            switch self {
            case .postUser:
                return .post
            }
        }
        
        var body: Encodable {
            switch self {
            case .postUser(let request):
                return request
            }
        }
    }
        
    enum APIError: Error {
        case invalidURL
    }
}

extension APIClient {
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
}

extension APIClient: DependencyKey {
    public static var liveValue: APIClient {
        return Self(_request: { apiKey, route in
            guard let url = URL(string: route.url) else {
                throw APIError.invalidURL
            }
            
            var request = URLRequest(url: url)
                        
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpMethod = route.method.rawValue

            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let json = try! encoder.encode(route.body)
            request.httpBody = json
                    
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

//import Foundation
//import Dependencies
//
//public struct APIClient {
//    public var postUser: @Sendable (_ data: UserRequest, _ apiKey: String) async throws -> UserResponse
//    public var postSession: @Sendable (_ apiKey: String) async throws -> PostSessionResponse
//    public var pullTracks: @Sendable (_ sessionId: String, _ data: PullTracksRequest, _ apiKey: String) async throws -> PostTracksResponse
//    public var renegotiate: @Sendable (_ sessionId: String, _ data: RenegotiateRequest, _ apiKey: String) async throws -> RenegotiateResponse
//}
//
//extension APIClient {
//    public struct SessionDescription: Codable {
//        let sdp: String
//        let type: String
//    }
//    
//    public struct PullTracksRequest: Codable {
//        let tracks: [Track]
//        
//        struct Track: Codable {
//            let location: String
//            let trackName: String
//            let sessionId: String
//        }
//    }
//
//    public struct RenegotiateRequest: Codable {
//        let sessionDescription: SessionDescription
//    }
//    
//    public struct RenegotiateResponse: Codable {}
//    
//    public struct PostTracksResponse: Codable {
//        let requiresImmediateRenegotiation: Bool
//        let tracks: [Track]
//        let sessionDescription: SessionDescription
//        
//        public struct Track: Codable {
//            let sessionId: String
//            let mid: String
//            let trackName: String
//        }
//    }
//    
//    public struct UserRequest: Codable {
//        let id: String?
//        let name: String?
//        let email: String?
//        let appVersion: String?
//    }
//    
//    public struct UserResponse: Codable {
//        let accessToken: String
//        let uuid: String
//    }
//    
//    public struct PostSessionResponse: Codable {
//        let sessionId: String
//    }
//}
//
//let baseURL = "https://jelsoft-consumer-latinas-weak.trycloudflare.com"
//
//struct Unknown: Error {}
//
//extension APIClient: DependencyKey {
//    
//    public static let liveValue: APIClient = {
//        .init { data, apiKey in
//            let url = URL(string: "\(baseURL)/api/v1/users")!
//            var request = URLRequest(url: url)
//            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
//            request.httpMethod = "POST"
//            
//            let encoder = JSONEncoder()
//            encoder.keyEncodingStrategy = .convertToSnakeCase
//            let json = try! encoder.encode(data)
//            request.httpBody = json
//            
//            let (data, _) = try! await URLSession.shared.data(for: request)
//            let decoder = JSONDecoder()
//            decoder.keyDecodingStrategy = .convertFromSnakeCase
//            
//            let response = try! decoder.decode(UserResponse.self, from: data)
//            
//            return response
//        } postSession: { apiKey in
//            let url = URL(string: "\(baseURL)/api/calls/sessions/new")!
//            var request = URLRequest(url: url)
//            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
//            request.httpMethod = "POST"
//                                    
//            let (data, _) = try! await URLSession.shared.data(for: request)
//            let decoder = JSONDecoder()
//            decoder.keyDecodingStrategy = .convertFromSnakeCase
//            
//            return try decoder.decode(PostSessionResponse.self, from: data)
//        } pullTracks: { sessionId, data, apiKey in
//            let url = URL(string: "\(baseURL)/api/calls/sessions/\(sessionId)/tracks/new")!
//            var request = URLRequest(url: url)
//            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//            request.httpMethod = "POST"
//    
//            let encoder = JSONEncoder()
//            let json = try! encoder.encode(data)
//            request.httpBody = json
//    
//            let (data, _) = try! await URLSession.shared.data(for: request)
//            let decoder = JSONDecoder()
//    
//            let response = try decoder.decode(PostTracksResponse.self, from: data)
//            return response
//        } renegotiate: { sessionId, data, apiKey in
//            let url = URL(string: "\(baseURL)/api/calls/sessions/\(sessionId)/renegotiate")!
//            var request = URLRequest(url: url)
//            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//            request.httpMethod = "PUT"
//            
//            let encoder = JSONEncoder()
//            let json = try! encoder.encode(data)
//            request.httpBody = json
//            
//            let (data, _) = try! await URLSession.shared.data(for: request)
//            let decoder = JSONDecoder()
//            
//            let response = try! decoder.decode(RenegotiateResponse.self, from: data)
//            
//            return response
//        }
//    }()
//    
//}
//
//extension DependencyValues {
//    
//    public var apiClient: APIClient {
//        get { self[APIClient.self] }
//        set { self[APIClient.self] = newValue }
//    }
//    
//}
//
//
////public class APIClient: ObservableObject {
////    
////    struct UserRequest: Codable {
////        let email: String
////    }
////    
////    struct UserResponse: Codable {
////        
////    }
////    
////    struct Track: Codable {
////        let location: String
////        let mid: String
////        let trackName: String
////    }
////    
////    struct SessionDescription: Codable {
////        let sdp: String
////        let type: String
////    }
////    
////    struct NewSessionRequest: Codable {
////        let sessionDescription: SessionDescription
////    }
////    
////    struct NewSessionResponse: Codable {
////        let sessionDescription: SessionDescription
////        let sessionId: String
////    }
////    
////    struct NewTracksRequest: Codable {
////        let tracks: [Track]
////        let sessionDescription: SessionDescription
////    }
////
////    struct NewTracksResponse: Codable {
////        let requiresImmediateRenegotiation: Bool
////        let tracks: [Track]
////        let sessionDescription: SessionDescription
////        
////        struct Track: Codable {
////            let mid: String
////            let trackName: String
////        }
////    }
////    
////    struct NewPullTracksRequest: Codable {
////        let tracks: [Track]
////        
////        struct Track: Codable {
////            let location: String
////            let trackName: String
////            let sessionId: String
////        }
////    }
////
////    struct RenegotiateRequest: Codable {
////        let sessionDescription: SessionDescription
////    }
////    
////    struct RenegotiateResponse: Codable {
////        
////    }
////    
////    private let baseURL: String
////    
////    init(baseURL: URL) {
////        self.baseURL = baseURL.absoluteString
////    }
////    
////    func postUser(data: UserRequest) async throws -> UserResponse {
////        let url = URL(string: "\(baseURL)/api/v1/users")!
////        var request = URLRequest(url: url)
////        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
////        request.httpMethod = "POST"
////        
////        let encoder = JSONEncoder()
////        let json = try! encoder.encode(data)
////        request.httpBody = json
////        
////        let (data, _) = try! await URLSession.shared.data(for: request)
////        let decoder = JSONDecoder()
////        
////        let response = try! decoder.decode(UserResponse.self, from: data)
////        
////        return response
////    }
////    
////    func postSession(data: NewSessionRequest) async throws -> NewSessionResponse {
////        let url = URL(string: "\(baseURL)/api/v1/calls/sessions")!
////        var request = URLRequest(url: url)
////        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
////        request.httpMethod = "POST"
////        
////        let encoder = JSONEncoder()
////        let json = try! encoder.encode(data)
////        request.httpBody = json
////        
////        let (data, _) = try! await URLSession.shared.data(for: request)
////        let decoder = JSONDecoder()
////        
////        let response = try! decoder.decode(NewSessionResponse.self, from: data)
////        
////        return response
////    }
////    
////    func postLocalTracks(sessionId: String, data: NewTracksRequest) async throws -> NewTracksResponse {
////        let url = URL(string: "\(baseURL)/api/v1/calls/sessions/\(sessionId)/tracks")!
////        var request = URLRequest(url: url)
////        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
////        request.httpMethod = "POST"
////        
////        let encoder = JSONEncoder()
////        let json = try! encoder.encode(data)
////        request.httpBody = json
////        
////        let (data, _) = try! await URLSession.shared.data(for: request)
////        let decoder = JSONDecoder()
////        
////        let response = try! decoder.decode(NewTracksResponse.self, from: data)
////        
////        return response
////    }
////    
////    func pullTracks(sessionId: String, data: NewPullTracksRequest) async throws -> NewTracksResponse {
////        let url = URL(string: "\(baseURL)/api/v1/calls/sessions/\(sessionId)/tracks")!
////        var request = URLRequest(url: url)
////        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
////        request.httpMethod = "POST"
////        
////        let encoder = JSONEncoder()
////        let json = try! encoder.encode(data)
////        request.httpBody = json
////        
////        let (data, _) = try! await URLSession.shared.data(for: request)
////        let decoder = JSONDecoder()
////        
////        let response = try! decoder.decode(NewTracksResponse.self, from: data)
////        
////        return response
////    }
////    
////    func renegotiate(sessionId: String, data: RenegotiateRequest) async throws -> RenegotiateResponse {
////        let url = URL(string: "\(baseURL)/api/v1/calls/sessions/\(sessionId)/renegotiate")!
////        var request = URLRequest(url: url)
////        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
////        request.httpMethod = "PUT"
////        
////        let encoder = JSONEncoder()
////        let json = try! encoder.encode(data)
////        request.httpBody = json
////        
////        let (data, _) = try! await URLSession.shared.data(for: request)
////        let decoder = JSONDecoder()
////        
////        let response = try! decoder.decode(RenegotiateResponse.self, from: data)
////        
////        return response
////    }
////}
