//
//  WebSocketClient.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import Foundation

actor WebSocket {
    
    // MARK: - Properties
            
    public var connectionState: ConnectionState {
        state
    }
    
    private var state: ConnectionState = .disconnected
    private var socketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    
    enum ConnectionState {
            case disconnected
            case connecting
            case connected
            case disconnecting
        }
    
    struct ConnectionError: Error {}
    struct SendError: Error {}
    
    struct WebSocketStream {
        let messages: AsyncStream<URLSessionWebSocketTask.Message>
        
        init(_ task: URLSessionWebSocketTask) {
            messages = AsyncStream { continuation in
                func receiveNext() {
                    task.receive { result in
                        switch result {
                        case .success(let message):
                            continuation.yield(message)
                            if task.state == .running {
                                receiveNext()
                            } else {
                                continuation.finish()
                            }
                        case .failure:
                            continuation.finish()
                        }
                    }
                }
                
                receiveNext()
                
                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        }
    }
    
    func connect(to url: URL) async throws -> WebSocketStream {
        state = .connecting
        self.session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
        
        socketTask = session?.webSocketTask(with: url, protocols: [])
        guard let task = socketTask else {
            state = .disconnected
            throw ConnectionError()
        }
        
        task.resume()
        state = .connected
        
        Task.detached { [weak self] in
            while let self = self, await self.state == .connected, task.state == .running {
                do {
                    try await self.sendPing()
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                } catch {
                    assertionFailure("Ping failed: \(error)")
                }
            }
        }
        
        return WebSocketStream(task)
    }
    
    func send(message: URLSessionWebSocketTask.Message) async throws {
        guard let task = socketTask, task.state == .running else {
            throw SendError()
        }
        
        try await task.send(message)
    }
    
    func sendPing() async throws {
        guard let task = socketTask, task.state == .running else {
            throw SendError()
        }
        
        let data = try JSONSerialization.data(withJSONObject: ["type": "user-socket-ping"])
        try await task.send(.string(String(data: data, encoding: .utf8)!))
    }
    
    func disconnect() {
        state = .disconnecting
        socketTask?.cancel(with: .normalClosure, reason: nil)
        socketTask = nil
        session = nil
        state = .disconnected
    }
}
