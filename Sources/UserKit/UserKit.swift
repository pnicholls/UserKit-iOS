//
//  File.swift
//
//
//  Created by Peter Nicholls on 3/9/2024.
//

import Foundation
import UIKit
import SwiftUI

public class UserKit {
    
    // MARK: - Properties
    
    public var isLoggedIn: Bool {
        return userManager.isLoggedIn
    }
    
    private static var userKit: UserKit?
        
    public static var shared: UserKit {
        guard let userKit = userKit else {
            fatalError("UserKit has not been configured. Please call UserKit.configure()")
        }
        
        return userKit
    }
    
    private let apiKey: String
    
    private let apiClient: APIClient
    
    private let callManager: CallManager
    
    private let storage: Storage
    
    private let userManager: UserManager
    
    private let webRTCClient: WebRTCClient
    
    private let webSocket: WebSocket
        
    // MARK: - Functions
    
    @discardableResult
    public static func configure(apiKey: String) -> UserKit {
        guard userKit == nil else {
            return shared
        }
                        
        userKit = .init(apiKey: apiKey)
                        
        if let userKit = userKit, userKit.isLoggedIn {
            Task {
                do {
                    try await userKit.userManager.connect()
                } catch {
                    print("Failed to connect to UserKit: \(error)")
                }
            }
        }
        
        return shared
    }
        
    init(apiKey: String) {
        self.apiKey = apiKey
        self.apiClient = APIClient()
        self.storage = Storage()
        self.webRTCClient = WebRTCClient()
        self.webSocket = WebSocket()
        self.callManager = CallManager(apiClient: apiClient, webRTCClient: webRTCClient, webSocketClient: webSocket)
        self.userManager = UserManager(apiClient: apiClient, callManager: callManager, storage: storage, webSocket: webSocket)
    }
    
    public func login(id: String?, name: String?, email: String?) async throws {
        try await userManager.login(apiKey: apiKey, id: id, name: name, email: email)
    }    
}

struct RootView: View {
    var body: some View {
        EmptyView()
    }
}
