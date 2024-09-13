//
//  File.swift
//  
//
//  Created by Peter Nicholls on 3/9/2024.
//

import Foundation
import Dependencies
import DependenciesMacros
import SwiftPhoenixClient

public struct WebSocketClient {
    public var connect: @Sendable (_ url: String, _ accessToken: String) async -> AsyncThrowingStream<Event, Error> = { _, _ in .finished() }
    public var join: @Sendable (_ topic: String) async -> AsyncThrowingStream<Event, Error> = { _ in .finished() }
    public var push: @Sendable (_ topic: String, _ event: String, _ payload: [String: Any]) async -> AsyncThrowingStream<Event, Error> = { _, _, _ in .finished() }
    
    public enum Event {
        case socket(Socket)
        case channel(Channel)
        
        public enum Socket {
            case connected
        }
        
        public enum Channel {
            case joined
            case push(Dictionary<String, Any>)
        }
    }
}

extension WebSocketClient: DependencyKey {
    
    public static var liveValue: WebSocketClient {
        let client = Client()
        return WebSocketClient(connect: { url, accessToken in
            await client.connect(url: url, accessToken: accessToken)
        }, join: { topic in
            await client.join(topic: topic)
        }, push: { topic, event, payload in
            await client.push(topic: topic, event: event, payload: payload)
        })
    }
    
}

extension DependencyValues {
    
    public var webSocketClient: WebSocketClient {
        get { self[WebSocketClient.self] }
        set { self[WebSocketClient.self] = newValue }
    }
    
}

private actor Client {
    private var socket: Socket? = nil
    private var channels: [String: Channel] = [:]
    
    func connect(url: String, accessToken: String) -> AsyncThrowingStream<WebSocketClient.Event, Error> {
        AsyncThrowingStream { continuation in
            self.socket = Socket(url, params: ["access_token": accessToken])
            socket?.logger = { message in print("LOG:", message) }
                        
            socket?.onOpen {
                continuation.yield(.socket(.connected))
                continuation.finish()
            }
            
            socket?.connect()
        }
    }
    
    func join(topic: String) -> AsyncThrowingStream<WebSocketClient.Event, Error> {
        AsyncThrowingStream { continuation in
            guard let socket = socket else {
                struct JoinFailed: Error {}
                return continuation.finish(throwing: JoinFailed())
            }
            
            let channel = socket.channel(topic)
            channels.updateValue(channel, forKey: topic)
            
            let push = channel.join()
            push.receive("ok") { message in
                continuation.yield(.channel(.joined))
                continuation.finish()
            }
        }
    }
    
    func push(topic: String, event: String, payload: Payload) -> AsyncThrowingStream<WebSocketClient.Event, Error> {
        AsyncThrowingStream { continuation in
            guard let channel = channels[topic] else {
                struct NoChannelError: Error {}
                return continuation.finish(throwing: NoChannelError())
            }
            
            let push = channel.push(event, payload: payload)
            push.receive("ok") { message in
                print("message", message)
                continuation.yield(.channel(.push(message.payload)))
                continuation.finish()
            }
        }
    }
    
}
