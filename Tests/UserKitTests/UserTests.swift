//
//  UserTests.swift
//  UserKit
//
//  Created by Peter Nicholls on 14/1/2025.
//

import ComposableArchitecture
import XCTest
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

        await store.send(.`init`)

    }
}
