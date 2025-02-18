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
                        
        window = UIWindow(windowScene: windowScene)
        window?.windowLevel = .statusBar
        window?.isHidden = true
        
        store?.send(.configured)
    }
        
    private func configureRootViewController() {
        guard let store = store else {
            return
        }

        let rootView = RootView(store: store)
        let hostingViewController = CustomHostingController(rootView: rootView)
        hostingViewController.view.backgroundColor = .clear
        hostingViewController.view.isUserInteractionEnabled = false
        
        window?.rootViewController = hostingViewController
        
        self.store?.publisher.isPresented.removeDuplicates().sink(receiveValue: { [weak self] present in
            guard let self = self else { return }
                
            if !present {
                self.window?.isHidden = true
                return
            }

            self.window?.makeKeyAndVisible()
            self.window?.isHidden = false
        }).store(in: &cancellables)        
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
        WithPerceptionTracking {
            if let store = store.scope(state: \.user, action: \.user) {
                UserView(store: store)
            }
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
