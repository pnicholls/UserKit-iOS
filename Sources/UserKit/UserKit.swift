//
//  File.swift
//
//
//  Created by Peter Nicholls on 3/9/2024.
//

import Foundation
import UIKit
import SwiftUI

let sdkVersion = """
0.1.0
"""

public class UserKit {
    
    // MARK: - Types
    
    public enum Availability {
        case active, inactive
    }
    
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
    
    private let availabilityManager: AvailabilityManager
    
    private let callManager: CallManager
    
    private let device: Device
    
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
        self.device = Device()
        self.apiClient = APIClient(device: device)
        self.storage = Storage()
        self.availabilityManager = AvailabilityManager(apiClient: apiClient, storage: storage)
        self.webRTCClient = WebRTCClient()
        self.webSocket = WebSocket()
        self.callManager = CallManager(apiClient: apiClient, webRTCClient: webRTCClient, webSocketClient: webSocket)
        self.userManager = UserManager(apiClient: apiClient, callManager: callManager, storage: storage, webSocket: webSocket)
    }
    
    public func login(id: String?, name: String?, email: String?) async throws {
        try await userManager.login(apiKey: apiKey, id: id, name: name, email: email)
    }
        
    public func availability() async throws -> Availability {
        try await availabilityManager.availability()
    }
    
    public func call() {
        Task {
            await callManager.call()
        }
    }
}

struct RootView: View {
    var body: some View {
        EmptyView()
    }
}
