// The Swift Programming Language
// https://docs.swift.org/swift-book

import ComposableArchitecture
import SwiftUI
import ReplayKit

@Reducer
public struct UserKitApp {
    
    @Dependency(\.apiClient) var apiClient
    @Dependency(\.webRTCClient) var webRTCClient
    
    @ObservableState
    public struct State {
        let config: UserKit.Config
        var user: User.State?
        var isPresented: Bool = true
    }
    
    public enum Action {
        case api(Api)
        case configured
        case dismiss
        case login(String?, String?, String?)
        case user(User.Action)

        public enum Api {
            case postUserResponse(Result<APIClient.UserResponse, Error>)
        }
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .api(.postUserResponse(.success(let response))):
                state.user = .init(accessToken: response.accessToken, call: nil, webSocket: .init(url: response.webSocketUrl))
                
                return .concatenate([
                    .run { send in
                        await apiClient.setAccessToken(response.accessToken)
                    },
                    .send(.user(.`init`))
                ])
                            
            case .api(.postUserResponse(.failure)):
                return .none
                
            case .configured:
                return .none
                
            case .dismiss:
                return .none
            
            case .login(let id, let name, let email):
                return .run { [state] send in
                    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                    
                    await send(.api(.postUserResponse(Result {
                        try await apiClient.request(
                            apiKey: state.config.api.key,
                            endpoint: .postUser(.init(id: id, name: name, email: email, appVersion: appVersion)),
                            as: APIClient.UserResponse.self
                        )
                    })))
                }
                
            case .user(.call(.destination(.requested(.accept)))):
                state.isPresented = false
                return .none

//            case .user(.call(.pictureInPicture(.start))):
//                state.isPresented = false
//                return .none
//
//            case .user(.call(.pictureInPicture(.stop))):
//                state.isPresented = true
//                return .none
//                
//            case .user(.call(.pictureInPicture(.restore))):
//                state.isPresented = true
//                return .none
                                
            case .user:
                return .none
            }
        }
        .ifLet(\.user, action: \.user) {
            User()
        }
    }
}
