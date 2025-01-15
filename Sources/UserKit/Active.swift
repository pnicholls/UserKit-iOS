import AVKit
import Combine
import ComposableArchitecture
import SwiftUI
import WebRTC

@Reducer
public struct Active {
    @ObservableState
    public struct State: Equatable {
        var video: Video.State? = nil
    }
    
    public enum Action {
        case `continue`
        case end
        case video(Video.Action)
    }
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .continue:
                return .none
                
            case .end:
                return .none

            }
        }
        .ifLet(\.video, action: \.video) {
            Video()
        }
    }
}

struct ActiveView: View {
    @Environment(\.colorScheme) var colorScheme
    @Perception.Bindable var store: StoreOf<Active>
    
    var body: some View {
        WithPerceptionTracking {
            VStack {
                if let store = store.scope(state: \.video, action: \.video) {
                    VideoView(store: store)
                }
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button(action: { store.send(.continue) }) {
                        Text("Continue Call")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(.white)
                            .background(Color.primary)
                            .cornerRadius(8)
                    }
                    
                    Button(action: { store.send(.end) }) {
                        Text("End Call")
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
