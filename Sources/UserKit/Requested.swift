import AVKit
import Combine
import ComposableArchitecture
import SwiftUI

@Reducer
public struct Requested {
    @ObservableState
    public struct State: Equatable {
    }
    
    public enum Action {
        case accept
        case decline
    }
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            return .none
        }
    }
}

struct RequestedView: View {
    @Environment(\.colorScheme) var colorScheme
    @Bindable var store: StoreOf<Requested>
    
    var body: some View {
        WithPerceptionTracking {
            VStack {
                Spacer()
                                
                VStack(spacing: 12) {
                    Button(action: { store.send(.accept) }) {
                        Text("Join Call")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(.white)
                            .background(Color.primary)
                            .cornerRadius(8)
                    }
                    
                    Button(action: { store.send(.decline) }) {
                        Text("Decline")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(Color.primary)
                            .background(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary, lineWidth: 1)
                            )
                    }
                }.padding(.horizontal, 16)
            }
        }
    }
}

