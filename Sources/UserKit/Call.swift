import AVKit
import Combine
import ComposableArchitecture
import SwiftUI

@Reducer
public struct Call {
    @Dependency(\.audioSessionClient) var audioSessionClient
    @Dependency(\.webRTCClient) var webRTCClient
    @Dependency(\.webSocketClient) var webSocketClient
        
    @Reducer
    public enum Destination {
        case active(Active)
        case requested(Requested)
    }
    
    @ObservableState
    public struct State {
        var destination: Destination.State = .requested(.init())
        var participants: IdentifiedArrayOf<Participant.State>
    }
    
    public enum Action {
        case appeared
        case participants(IdentifiedActionOf<Participant>)
        case destination(Destination.Action)
    }
    
    public var body: some ReducerOf<Self> {
        Scope(state: \.destination, action: \.destination) {
            Scope(state: \.active, action: \.active) {
                Active()
            }
            Scope(state: \.requested, action: \.requested) {
                Requested()
            }
        }
        Reduce { state, action in
            switch action {
            case .appeared:
                return .none
                
            case .destination(.requested(.accept)):
                state.destination = .active(.init(participants: state.participants.filter { $0.role == .host }))
                return .none

            case .destination(.active(.continue)):
                switch state.destination {
                case .active(var active):
                    active.isPictureInPictureActive = true
                    state.destination = .active(active)
                default:
                    break // invalid state
                }
                return .none
                
            case .destination(.active(.end)):
                state.destination = .requested(.init())
                return .run { send in
                    await webRTCClient.close()
                    await audioSessionClient.removeNotificationObservers()
                }
                                
            case .destination:
                return .none
                
            case .participants:
                return .none
            
            }
        }
        .forEach(\.participants, action: \.participants) {
            Participant()
        }
    }
}

struct CallView: View {
    @Environment(\.colorScheme) var colorScheme
    @Bindable var store: StoreOf<Call>
    
    var body: some View {
        ZStack {
            switch store.scope(state: \.destination, action: \.destination).case {
            case .active(let store):
                ActiveView(store: store)
                
            case .requested(let store):
                RequestedView(store: store)
            }
        }
        .onAppear { store.send(.appeared) }
    }
}
