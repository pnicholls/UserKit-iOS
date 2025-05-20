//
//  AvailabilityManager.swift
//  UserKit
//
//  Created by Peter Nicholls on 18/5/2025.
//

import SwiftUI
import Network

class AvailabilityManager {

    // MARK: - Types
            
    // MARK: - Properties
    
    var isLoggedIn: Bool {
        storage.get(AppUserCredentials.self) != nil
    }
    
    private let apiClient: APIClient
    
    private let storage: Storage
    
    // MARK: - Functions
    
    init(apiClient: APIClient, storage: Storage) {
        self.apiClient = apiClient
        self.storage = storage
    }
    
    func availability() async throws -> UserKit.Availability {
        let response = try await apiClient.request(
            endpoint: .availability,
            as: APIClient.AvailabilityResponse.self
        )
        
        return response.available ? .active : .inactive
    }
}
