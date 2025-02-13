//
//  UserTests.swift
//  UserKit
//
//  Created by Peter Nicholls on 14/1/2025.
//

import ComposableArchitecture
import XCTest
import Testing

@testable import UserKit

@MainActor
final class UserFeatureSocketTests: XCTestCase {
    func testInit() async {
        let store = TestStore(initialState: User.State(
            accessToken: "example-token",
            webSocket: .init(url: URL(string: "https://example.com")!))
        ) {
            User()
        }

        // Mock WebSocketClient behavior
        store.dependencies.continuousClock = ImmediateClock()
        store.dependencies.webSocketClient = .init(
            open: { _, _, _ in
                AsyncStream { continuation in
                    continuation.yield(.didOpen(protocol: nil)) // Simulate WebSocket opening
                    continuation.finish()
                }
            },
            receive: { _ in
                AsyncStream { continuation in
                    continuation.finish() // No incoming messages
                }
            },
            send: { _, _ in },
            sendPing: { @Sendable _ in try await Task.never() }
        )

        await store.send(.`init`)
        
        await store.receive(\.webSocket.connect) {
            $0.webSocket.state = .connecting
        }
        
        await store.receive(\.webSocket.client.didOpen) {
            $0.webSocket.state = .connected
        }
        
        await store.send(.webSocket(.disconnect))
        
        await store.finish()
    }
}


