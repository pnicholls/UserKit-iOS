//
//  File.swift
//  
//
//  Created by Peter Nicholls on 3/9/2024.
//

import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct WebSocketClient {
    struct ID: Hashable, @unchecked Sendable {
        let rawValue: AnyHashable

        init<RawValue: Hashable & Sendable>(_ rawValue: RawValue) {
            self.rawValue = rawValue
        }

        init() {
            struct RawValue: Hashable, Sendable {}
            self.rawValue = RawValue()
        }
    }

    @CasePathable
    public enum Action {
        case didOpen(protocol: String?)
        case didClose(code: URLSessionWebSocketTask.CloseCode, reason: Data?)
    }

    @CasePathable
    public enum Message: Equatable {
        struct Unknown: Error {}
 
        case data(Data)
        case string(String)

        init(_ message: URLSessionWebSocketTask.Message) throws {
            switch message {
                case let .data(data): self = .data(data)
                case let .string(string): self = .string(string)
                @unknown default: throw Unknown()
            }
        }
    }

    var open: @Sendable (_ id: ID, _ url: URL, _ protocols: [String]) async -> AsyncStream<Action> = { _, _, _ in .finished }
    var receive: @Sendable (_ id: ID) async throws -> AsyncStream<Result<Message, any Error>>
    var send: @Sendable (_ id: ID, _ message: URLSessionWebSocketTask.Message) async throws -> Void
    var sendPing: @Sendable (_ id: ID) async throws -> Void
}

extension WebSocketClient: DependencyKey {
    public static var liveValue: Self {
        return Self(
            open: { await WebSocketActor.shared.open(id: $0, url: $1, protocols: $2) },
            receive: { try await WebSocketActor.shared.receive(id: $0) },
            send: { try await WebSocketActor.shared.send(id: $0, message: $1) },
            sendPing: { try await WebSocketActor.shared.sendPing(id: $0) }
        )

    @globalActor final actor WebSocketActor {
        private final class Delegate: NSObject, @unchecked Sendable, URLSessionWebSocketDelegate {
            var continuation: AsyncStream<Action>.Continuation?

            nonisolated func urlSession(_: URLSession, webSocketTask _: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
                self.continuation?.yield(.didOpen(protocol: `protocol`))
            }

            nonisolated func urlSession(_: URLSession, webSocketTask _: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
                self.continuation?.yield(.didClose(code: closeCode, reason: reason))
                self.continuation?.finish()
            }
        }

        typealias Dependencies = (socket: URLSessionWebSocketTask, delegate: Delegate)

        static let shared = WebSocketActor()

        var dependencies: [ID: Dependencies] = [:]

        func open(id: ID, url: URL, protocols: [String]) -> AsyncStream<Action> {
            let delegate = Delegate()
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let socket = session.webSocketTask(with: url, protocols: protocols)
            defer { socket.resume() }
            var continuation: AsyncStream<Action>.Continuation!
            let stream = AsyncStream<Action> {
              $0.onTermination = { _ in
                socket.cancel()
                Task { await self.removeDependencies(id: id) }
              }
              continuation = $0
            }
            delegate.continuation = continuation
            self.dependencies[id] = (socket, delegate)
            return stream
        }

        func close(id: ID, with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) async throws {
            defer { self.dependencies[id] = nil }
            try self.socket(id: id).cancel(with: closeCode, reason: reason)
        }

        func receive(id: ID) throws -> AsyncStream<Result<Message, any Error>> {
            let socket = try self.socket(id: id)
            return AsyncStream { continuation in
                let task = Task {
                    while !Task.isCancelled {
                        continuation.yield(await Result { try await Message(socket.receive()) })
                    }
                    continuation.finish()
                }
          
                continuation.onTermination = { _ in task.cancel() }
            }
        }

        func send(id: ID, message: URLSessionWebSocketTask.Message) async throws {
            try await self.socket(id: id).send(message)
        }

        func sendPing(id: ID) async throws {
            let socket = try self.socket(id: id)
      
            let data = try JSONSerialization.data(withJSONObject: ["type": "user-socket-ping"])
            try await socket.send(.string(String(data: data, encoding: .utf8)!))
        }

        private func socket(id: ID) throws -> URLSessionWebSocketTask {
            guard let dependencies = self.dependencies[id]?.socket else {
                struct Closed: Error {}
                throw Closed()
            }
      
            return dependencies
        }

        private func removeDependencies(id: ID) {
            self.dependencies[id] = nil
        }
    }
    }

    public static let testValue = Self()
}

extension DependencyValues {
    var webSocketClient: WebSocketClient {
        get { self[WebSocketClient.self] }
        set { self[WebSocketClient.self] = newValue }
    }
}
