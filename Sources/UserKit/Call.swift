import AVKit
import Combine
import ComposableArchitecture
import SwiftUI

@Reducer
public struct Call {
    @Dependency(\.webSocketClient) var webSocketClient
        
    @ObservableState
    public struct State: Equatable {
        var participants: IdentifiedArrayOf<Participant.State> = []
        var isPictureInPictureActive: Bool = false
    }
    
    public enum Action {
        case `init`
        case decline
        case reload
        case join
        case pictureInPicture(PictureInPictureAction)
        
        public enum PictureInPictureAction {
            case started
            case stopped
            case restore
        }
    }
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .`init`:
                return .none
                
            case .decline:
                return .run { send in
                    let dictionary: [String: Any] = [
                        "type": "participantUpdate",
                        "participant": [
                            "state": "declined",
                            "tracks": []
                        ]
                    ]
                    let jsonData = try! JSONSerialization.data(withJSONObject: dictionary, options: [])
                    let jsonString = String(data: jsonData, encoding: .utf8)
                
                    try await webSocketClient.send(id: WebSocketClient.ID(), message: .string(jsonString!))
                }
                
            case .reload:
                return .none
                
            case .join:
                state.isPictureInPictureActive = true
                return .run { send in
                    let dictionary: [String: Any] = [
                        "type": "participantUpdate",
                        "participant": [
                            "state": "joined",
                            "tracks": []
                        ]
                    ]
                    let jsonData = try! JSONSerialization.data(withJSONObject: dictionary, options: [])
                    let jsonString = String(data: jsonData, encoding: .utf8)
                
                    try await webSocketClient.send(id: WebSocketClient.ID(), message: .string(jsonString!))
                }
                
            case .pictureInPicture(.started):
                return .none
            
            case .pictureInPicture(.stopped):
                return .none
                
            case .pictureInPicture(.restore):
                return .none
            
            }
        }
    }
}

struct CallView: View {
    @Environment(\.colorScheme) var colorScheme
    @Bindable var store: StoreOf<Call>
    
    var body: some View {
        if let store = store.scope(state: \.callState, action: \.user) {
            UserView(store: store)
        } else {
            EmptyView()
        }

    }
}

struct VideoView: UIViewControllerRepresentable {
    var store: StoreOf<Call>
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .systemGray
        
//        let placeholderView = PlaceholderView()
//        placeholderView.frame = viewController.view.bounds
//        context.coordinator.pictureInPictureVideoCallViewController.view.addSubview(placeholderView)
        
        let pictureInPictureControllerContentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: viewController.view,
            contentViewController: context.coordinator.pictureInPictureVideoCallViewController
        )
        
        context.coordinator.pictureInPictureController = AVPictureInPictureController(contentSource: pictureInPictureControllerContentSource)
        context.coordinator.pictureInPictureController?.delegate = context.coordinator
        context.coordinator.pictureInPictureController?.canStartPictureInPictureAutomaticallyFromInline = true

        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        store.publisher.isPictureInPictureActive.removeDuplicates().sink { isPictureInPictureActive in
            guard let pictureInPictureController = context.coordinator.pictureInPictureController else { return }
            
            if isPictureInPictureActive, !pictureInPictureController.isPictureInPictureActive {
                pictureInPictureController.startPictureInPicture()
            }
        }.store(in: &context.coordinator.cancellables)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }
    
    class Coordinator: NSObject {
        let store: StoreOf<Call>
        var cancellables: Set<AnyCancellable> = []
        
        init(store: StoreOf<Call>) {
            self.store = store
        }
        
        lazy var pictureInPictureVideoCallViewController: AVPictureInPictureVideoCallViewController = {
            let pictureInPictureVideoCallViewController = AVPictureInPictureVideoCallViewController()
            return pictureInPictureVideoCallViewController
        }()
        
        var pictureInPictureController: AVPictureInPictureController? = nil
    }
}

extension VideoView.Coordinator: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        store.send(.pictureInPicture(.stopped))
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController) async -> Bool {
        @MainActor func updateStore() {
            store.send(.pictureInPicture(.restore))
        }
        
        await updateStore()
        return true
    }
}

class PlaceholderView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        
        backgroundColor = .red
    }
}

#Preview("Light Mode") {
    CallView(store: Store(initialState: Call.State()) {
        Call()
    })
    .environment(\.colorScheme, .light)
}

#Preview("Dark Mode") {
    CallView(store: Store(initialState: Call.State()) {
        Call()
    })
    .environment(\.colorScheme, .dark)
}
