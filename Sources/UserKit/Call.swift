import AVKit
import Combine
import ComposableArchitecture
import SwiftUI
import WebRTC

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
        var isPictureInPictureActive: Bool = false
        var participants: IdentifiedArrayOf<Participant.State>
        var videoTrack: RTCVideoTrack?
    }
    
    public enum Action {
        public enum PictureInPictureAction {
            case start
            case stop
            case restore
        }
        
        case appeared
        case participants(IdentifiedActionOf<Participant>)
        case pictureInPicture(PictureInPictureAction)
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
                state.isPictureInPictureActive = true
                return .none

            case .destination(.active(.continue)):
                state.isPictureInPictureActive = true
                return .none
                
            case .destination(.active(.end)):
                state.isPictureInPictureActive = false
                state.destination = .requested(.init())
                return .run { send in
                    await webRTCClient.close()
                    await audioSessionClient.removeNotificationObservers()
                }
                
            case .destination(.active(.participants(.element(id: let id, action: .setReceiver(let trackId, let receiver))))):
                // This seems wrong
                guard let track = state.participants[id: id]?.tracks[id: trackId], track.trackType == .video, let track = receiver.track as? RTCVideoTrack else {
                    return .none
                }
                state.videoTrack = track
                return .none
                                
            case .destination:
                return .none
                
            case .participants:
                return .none
                
            case .pictureInPicture(.start):
                state.isPictureInPictureActive = true
                return .none
                
            case .pictureInPicture(.stop):
                state.isPictureInPictureActive = false
                return .none

            case .pictureInPicture(.restore):
                return .none
            
            }
        }
        .forEach(\.participants, action: \.participants) {
            Participant()
        }
    }
}

final class CallViewController: UIViewController {
    
    // MARK: - Properties

    private let store: StoreOf<Call>
    
    private lazy var pictureInPictureVideoCallViewController: PictureInPictureVideoCallViewController = {
        let pictureInPictureVideoCallViewController = PictureInPictureVideoCallViewController()
        return pictureInPictureVideoCallViewController
    }()

    private lazy var pictureInPictureControllerContentSource: AVPictureInPictureController.ContentSource = {
        let pictureInPictureControllerContentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: hostingViewController.view,
            contentViewController: pictureInPictureVideoCallViewController
        )
        return pictureInPictureControllerContentSource
    }()
    
    private var pictureInPictureController: AVPictureInPictureController?
    
    private lazy var hostingViewController: ContainerHostingController = {
        let hostingViewController = ContainerHostingController(rootView: EmptyView())
        hostingViewController.view.translatesAutoresizingMaskIntoConstraints = false
        return hostingViewController
    }()
        
    // MARK: - Functions
    
    init(store: StoreOf<Call>) {
        self.store = store
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        pictureInPictureController = AVPictureInPictureController(contentSource: pictureInPictureControllerContentSource)
        pictureInPictureController?.canStartPictureInPictureAutomaticallyFromInline = false
        pictureInPictureController?.delegate = self
        
        view.addSubview(hostingViewController.view)
                
        NSLayoutConstraint.activate([
            hostingViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
                
        observe { [weak self] in
            guard let self else { return }
            
            if store.isPictureInPictureActive {
                pictureInPictureController?.startPictureInPicture()
            } else {
                pictureInPictureController?.stopPictureInPicture()
            }
            
            if let track = store.videoTrack {
                track.add(pictureInPictureVideoCallViewController.videoView)
            }
            
            switch store.scope(state: \.destination, action: \.destination).case {
            case .active(let store):
                let view = ActiveView(store: store)
                hostingViewController.updateView(view)
                
            case .requested(let store):
                let view = RequestedView(store: store)
                hostingViewController.updateView(view)
            }
        }
    }
}

extension CallViewController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        store.send(.pictureInPicture(.start))
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        store.send(.pictureInPicture(.stop))
    }
    
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        store.send(.pictureInPicture(.stop))
    }
        
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController) async -> Bool {
        @MainActor func updateStore() async {
            store.send(.pictureInPicture(.restore))
        }
        
        await updateStore()
        return true
    }
}

struct CallViewControllerRepresentable: UIViewControllerRepresentable {
    let store: StoreOf<Call>
    
    func makeUIViewController(context: Context) -> CallViewController {
        CallViewController(store: store)
    }
    
    func updateUIViewController(_ uiViewController: CallViewController, context: Context) {
        // Update controller if needed
    }
}

class ContainerHostingController: UIHostingController<AnyView> {
    func updateView<V: View>(_ view: V) {
        self.rootView = AnyView(view)
    }
    
    init<V: View>(rootView: V) {
        super.init(rootView: AnyView(rootView))
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}

final class PictureInPictureVideoCallViewController: AVPictureInPictureVideoCallViewController {
    lazy var videoView: RTCMTLVideoView = {
        let videoView = RTCMTLVideoView()
        videoView.translatesAutoresizingMaskIntoConstraints = false
        return videoView
    }()
    
    convenience init() {
        self.init(nibName: nil, bundle: nil)
    }
        
    override func viewDidLoad() {
        super.viewDidLoad()
                
        view.addSubview(videoView)
        
        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
}
