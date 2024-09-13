//
//  File.swift
//  
//
//  Created by Peter Nicholls on 3/9/2024.
//

import Foundation
import ComposableArchitecture

fileprivate var instance: UserKit?

public struct UserKit {
    let store: Store<App.State, App.Action>
    
    public static func configure(apiKey: String) {
        instance = UserKit(apiKey: apiKey, appId: Bundle.main.bundleIdentifier ?? "")
        instance?.store.send(.start)
    }
    
    public static func login(name: String, email: String) {
        instance?.store.send(.login(name, email))
    }
    
    init(apiKey: String, appId: String) {
        self.store = Store.init(initialState: App.State(config: .init(apiKey: apiKey, appId: appId))) {
            App()._printChanges()
        }
    }
}
