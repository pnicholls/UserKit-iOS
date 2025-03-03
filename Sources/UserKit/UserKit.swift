//
//  File.swift
//
//
//  Created by Peter Nicholls on 3/9/2024.
//

import Foundation
import Combine
import UIKit
import SwiftUI

@MainActor
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
    
    private let config: Config
    private let userKitManager: UserKitManager
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
            
            Task { @MainActor in
                await userKit.presentWindow()
                await userKit.configureRootViewController()
            }
        }
        
        return shared
    }
    
    init(apiKey: String? = nil) {
        guard let apiKey = apiKey else {
            self.config = Config(api: Config.Api(key: ""))
            self.userKitManager = UserKitManager(config: Config(api: Config.Api(key: "")))
            return
        }
        
        self.config = Config(api: Config.Api(key: apiKey))
        self.userKitManager = UserKitManager(config: self.config)
    }
    
    public func login(id: String?, name: String?, email: String?) {
        Task {
            try? await userKitManager.login(id: id, name: name, email: email)
        }
    }
    
    private func presentWindow() async {
        guard let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            print("No UIWindowScene found")
            return
        }
        
        window = UIWindow(windowScene: windowScene)
        window?.windowLevel = .statusBar
        window?.isHidden = true
    }
    
    private func configureRootViewController() async {
        let rootView = RootView(userKitManager: userKitManager)
        let hostingViewController = CustomHostingController(rootView: rootView)
        hostingViewController.view.backgroundColor = .clear
        hostingViewController.view.isUserInteractionEnabled = false
        
        window?.rootViewController = hostingViewController
        
        userKitManager.$isPresented
            .removeDuplicates()
            .sink { [weak self] present in
                guard let self = self else { return }
                
                if !present {
                    self.window?.isHidden = true
                    return
                }
                
                self.window?.makeKeyAndVisible()
                self.window?.isHidden = false
            }
            .store(in: &cancellables)
    }
    
    struct Config: Equatable {
        let api: Api
        
        struct Api: Equatable {
            let key: String
        }
    }
}

@MainActor class UserKitManager: ObservableObject {
    private let config: UserKit.Config
    private let apiClient: APIClient
    private let webRTCClient: WebRTCClient
    
    @Published var user: UserManager?
    @Published var isPresented: Bool = true
    
    init(config: UserKit.Config) {
        self.config = config
        self.apiClient = APIClient()
        self.webRTCClient = WebRTCClient()
    }
    
    func login(id: String?, name: String?, email: String?) async throws {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let userRequest = APIClient.UserRequest(id: id, name: name, email: email, appVersion: appVersion)
        
        do {
            let response = try await apiClient.request(
                apiKey: config.api.key,
                endpoint: .postUser(userRequest),
                as: APIClient.UserResponse.self
            )
            
            await apiClient.setAccessToken(response.accessToken)
            user = UserManager(
                accessToken: response.accessToken,
                webSocketURL: response.webSocketUrl,
                apiClient: apiClient,
                webRTCClient: webRTCClient
            )
            
            await user?.initialize()
        } catch {
            throw error
        }
    }
    
    func updateUIState() {
        if let callState = user?.call {
            if callState.alert != nil || callState.pictureInPicture?.state == .starting {
                isPresented = true
            } else {
                isPresented = false
            }
        } else {
            isPresented = false
        }
    }
}

// Helper Views
struct RootView: View {
    @ObservedObject var userKitManager: UserKitManager
    
    var body: some View {
        if let user = userKitManager.user {
            UserView(userManager: user)
        }
    }
}

class CustomHostingController<Content>: UIHostingController<Content> where Content: View {
    var onDismiss: (() -> Void)?
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        if isBeingDismissed {
            onDismiss?()
        }
    }
}
