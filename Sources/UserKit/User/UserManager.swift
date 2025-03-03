//
//  UserManager.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import SwiftUI

@MainActor class UserManager: ObservableObject {
    private let accessToken: String
    private let apiClient: APIClient
    private let webRTCClient: WebRTCClient
    private let webSocketClient: WebSocketClient
    
    @Published var call: CallManager?
    @Published var webSocketState: WebSocketState = .disconnected
    
    private let webSocketURL: URL
    private var webSocketTask: Task<Void, Error>?
    
    enum WebSocketState: Equatable {
        case connected
        case connecting
        case disconnected
    }
    
    init(accessToken: String, webSocketURL: URL, apiClient: APIClient, webRTCClient: WebRTCClient) {
        self.accessToken = accessToken
        self.webSocketURL = webSocketURL
        self.apiClient = apiClient
        self.webRTCClient = webRTCClient
        self.webSocketClient = WebSocketClient()
    }
    
    func initialize() async {
        await connectWebSocket()
    }
    
    private func connectWebSocket() async {
        guard webSocketState == .disconnected else {
            if let task = webSocketTask {
                task.cancel()
            }
            return
        }
        
        webSocketState = .connecting
        
        webSocketTask = Task {
            do {
                let socket = try await webSocketClient.connect(to: webSocketURL, with: [])
                webSocketState = .connected
                
                // Launch a heartbeat task
                Task {
                    while !Task.isCancelled {
                        try await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                        try await self.webSocketClient.sendPing()
                    }
                }
                
                // Listen for messages
                for try await message in socket.messages {
                    await handleWebSocketMessage(message)
                }
                
                webSocketState = .disconnected
            } catch {
                webSocketState = .disconnected
                print("WebSocket connection failed: \(error)")
            }
        }
    }
    
    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) async {
        do {
            guard case .string(let messageString) = message else {
                print("Unexpected data received")
                return
            }
            
            let decoder = JSONDecoder()
            guard let data = messageString.data(using: .utf8) else { return }
            
            // Decode the message - simplified for now, add error handling as needed
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let messageType = json["type"] as? String {
                
                switch messageType {
                case "user-socket-pong":
                    // Handle pong - no action needed
                    break
                    
                case "userState":
                    if let stateData = json["state"] as? [String: Any],
                       let callData = stateData["call"] as? [String: Any] {
                        await updateCallState(from: callData)
                    } else if call != nil {
                        // Call ended
                        await endCall()
                    }
                    
                default:
                    print("Unknown message type: \(messageType)")
                }
            }
        } catch {
            print("Failed to decode WebSocket message: \(error)")
        }
    }
    
    private func updateCallState(from callData: [String: Any]) async {
        // Create or update call manager
        if call == nil {
            // Create new call with an alert
            call = CallManager(
                apiClient: apiClient,
                webRTCClient: webRTCClient,
                webSocketClient: webSocketClient,
                alert: AlertInfo(
                    title: "Luke Longworth would like to start a call",
                    acceptText: "Accept",
                    declineText: "Decline"
                )
            )
        }
        
        // Update participants if present
        if let participantsData = callData["participants"] as? [[String: Any]] {
            await call?.updateParticipants(from: participantsData)
        }
    }
    
    private func endCall() async {
        await webRTCClient.close()
        // Stop other services as needed
        call = nil
    }
}
