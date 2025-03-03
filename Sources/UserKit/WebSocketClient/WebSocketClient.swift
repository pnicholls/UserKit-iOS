//
//  WebSocketClient.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import Foundation

actor WebSocketClient {
    private var socketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    
    struct ConnectionError: Error {}
    struct SendError: Error {}
    
    // Helper struct to represent the combined stream of messages
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
    
    func connect(to url: URL, with protocols: [String]) async throws -> WebSocketStream {
        self.session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
        
        socketTask = session?.webSocketTask(with: url, protocols: protocols)
        guard let task = socketTask else {
            throw ConnectionError()
        }
        
        task.resume()
        
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
        socketTask?.cancel(with: .normalClosure, reason: nil)
        socketTask = nil
        session = nil
    }
}
