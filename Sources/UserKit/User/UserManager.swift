//
//  UserManager.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import SwiftUI

struct Credentials: Codable {
    let apiKey: String
    let id: String?
    let name: String?
    let email: String?
}

class UserManager {
    
    // MARK: - Types
    
    struct User: Codable {
        let call: Call?
    }
    
    enum State {
        case none
        case some(User)
    }
    
    // MARK: - Properties
    
    private let apiClient: APIClient

    private let callManager: CallManager
    
    private let storage: Storage
    
    private let webSocket: WebSocket
    
    private let state: StateSync<State>
    
    // MARK: - Functions
    
    init(apiClient: APIClient, callManager: CallManager, storage: Storage, webSocket: WebSocket) {
        self.apiClient = apiClient
        self.callManager = callManager
        self.storage = storage
        self.webSocket = webSocket
        self.state = .init(.none)
        
        state.onDidMutate = { [weak self] newState, oldState in
            switch newState {
            case .some(let state):
                self?.callManager.update(state: state.call)
            case .none:
                self?.callManager.update(state: nil)
            }
        }
    }
    
    func login(apiKey: String, id: String?, name: String?, email: String?) async throws {
        enum UserKitError: Error {
            case loginCredentialRequired
        }
        
        if (id?.isEmpty ?? true) && (name?.isEmpty ?? true) && (email?.isEmpty ?? true) {
            throw UserKitError.loginCredentialRequired
        }
        
        let credentials = Credentials(apiKey: apiKey, id: id, name: name, email: email)
        storage.save(credentials, forType: AppUserCredentials.self)
                
        try await connect()
    }
    
    func connect() async throws {
        guard let credentials = storage.get(AppUserCredentials.self) else {
            assertionFailure("Connect called with no credentials found")
            return
        }
                
        let response = try await apiClient.request(
            apiKey: credentials.apiKey,
            endpoint: .postUser(
                .init(
                    id: credentials.id,
                    name: credentials.name,
                    email: credentials.email,
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                )
            ),
            as: APIClient.UserResponse.self
        )

        await apiClient.setAccessToken(response.accessToken)

        let socket = try await webSocket.connect(to: response.webSocketUrl, accessToken: response.accessToken)
        
        for try await message in socket.messages {
            await handle(message: message)
        }
    }
    
    private func handle(message: URLSessionWebSocketTask.Message) async {
        do {
            guard case .string(let messageString) = message,
                  let data = messageString.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messageType = json["type"] as? String else {
                assertionFailure("Invalid WebSocket message format")
                return
            }

            switch messageType {
            case "user-socket-pong":
                // NOP
                break
            
            case "userState":
                update(state: json)
                
            default:
                print("Unknown message type: \(messageType)")
            }
        } catch {
            self.state.mutate { $0 = .none }
            assertionFailure("Failed to process WebSocket message: \(error)")
        }
    }
    
    private func update(state: [String: Any]) {
        do {
            let state = state["state"] as? [String: Any]
            let data = try JSONSerialization.data(withJSONObject: state ?? [:])
            let user = try JSONDecoder().decode(User.self, from: data)
            self.state.mutate {
                $0 = .some(user)
            }
        } catch {
            self.state.mutate { $0 = .none }
            assertionFailure("Failed to update user state \(error)")
        }
    }
}
