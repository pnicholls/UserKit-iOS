//
//  File.swift
//
//
//  Created by Peter Nicholls on 3/9/2024.
//

import Foundation
import ComposableArchitecture
import Combine
import UIKit
import SwiftUI

public class UserKit {
    
    // MARK: - Properties
    
    private static var userKit: UserKit?
        
    public static var shared: UserKit {
        guard let userKit = userKit else {
            assertionFailure("UserKit has not been configured. Please call UserKit.configure()")
            return UserKit()
        }
        
        return userKit
    }
    
    private let store: Store<UserKitApp.State, UserKitApp.Action>?
    
    private var window: UIWindow?
    
    private var cancellables: Set<AnyCancellable> = []
    
    private var isConfigured: Bool {
        window != nil
    }
        
    // MARK: - Functions
    
    public static func configure(apiKey: String) -> UserKit {
        guard userKit == nil else {
            return shared
        }
                        
        userKit = .init(apiKey: apiKey)
            
        NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { notification in
            guard let userKit = userKit, !userKit.isConfigured else {
                return
            }
            
            userKit.presentWindow()
            userKit.configureRootViewController()
        }
        
        return shared
    }
        
    init(apiKey: String? = nil) {
        guard let apiKey = apiKey else {
            self.store = nil
            return
        }
                
        self.store = Store.init(initialState: UserKitApp.State(config: .init(api: .init(key: apiKey)))) {
            UserKitApp()._printChanges()
        }
    }
    
    public func login(id: String?, name: String?, email: String?) {
        store?.send(.login(id, name, email))
    }
    
    private func presentWindow() {
        guard let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            print("No UIWindowScene found")
            return
        }

        window = windowScene.windows.first
                
        store?.send(.configured)
    }
    
    private func configureRootViewController() {
        guard let store = store else {
            return
        }

        let rootView = RootView(store: store)
        let hostingViewController = CustomHostingController(rootView: rootView)
        
        window?.rootViewController?.addChild(hostingViewController)
        hostingViewController.view.frame = .zero
        hostingViewController.view.isHidden = true
        hostingViewController.view.isUserInteractionEnabled = false
        window?.rootViewController?.view.addSubview(hostingViewController.view)
        hostingViewController.didMove(toParent: window?.rootViewController)
    }
}

extension UserKit {
    struct Config: Equatable {
        let api: Api
        
        struct Api: Equatable {
            let key: String
        }
    }
}

struct RootView: View {
    @Perception.Bindable var store: StoreOf<UserKitApp>

    var body: some View {
        if let store = store.scope(state: \.user, action: \.user) {
            UserView(store: store)
        } else {
            EmptyView()
        }
    }
}

class CustomHostingController<Content>: UIHostingController<Content> where Content: View {

    var onDismiss: (() -> Void)?
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        // You can also use this if you need to handle post-dismiss actions
        if isBeingDismissed {
            onDismiss?() // Call the callback if dismissed
        }
    }
}
