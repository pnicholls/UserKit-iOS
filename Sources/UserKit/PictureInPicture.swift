import AVKit
import Combine
import ComposableArchitecture
import SwiftUI
import WebRTC

@Reducer
public struct PictureInPicture {
    @ObservableState
    public struct State: Equatable {
        var isActive: Bool = false
        var videoTrack: RTCVideoTrack?
    }
    
    public enum Action: Equatable {
        case dismiss
        case restore
        case start
        case started
        case stopped
    }
        
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .dismiss:
                return .none
                
            case .restore:
                return .none
                
            case .start:
                state.isActive = true
                return .none
                
            case .started:
                return .none
                
            case .stopped:
                return .none
                                
            }
        }
    }
}

final class PictureInPictureViewController: UIViewController {
    
    // MARK: - Properties

    private let store: StoreOf<PictureInPicture>
    
    private lazy var pictureInPictureVideoCallViewController: PictureInPictureVideoCallViewController = {
        let pictureInPictureVideoCallViewController = PictureInPictureVideoCallViewController()
        return pictureInPictureVideoCallViewController
    }()

    private lazy var pictureInPictureControllerContentSource: AVPictureInPictureController.ContentSource = {
        let pictureInPictureControllerContentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: view,
            contentViewController: pictureInPictureVideoCallViewController
        )
        return pictureInPictureControllerContentSource
    }()
    
    private var pictureInPictureController: AVPictureInPictureController?
            
    // MARK: - Functions
    
    init(store: StoreOf<PictureInPicture>) {
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
        
        observe { [weak self] in
            guard let self else { return }
            
            if store.isActive {
                pictureInPictureController?.startPictureInPicture()
            } else {
                pictureInPictureController?.stopPictureInPicture()
            }
            
            if let track = store.videoTrack {
                track.add(pictureInPictureVideoCallViewController.videoView)
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // This is required
        store.send(.start)
    }    
}

extension PictureInPictureViewController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        store.send(.started)
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        self.pictureInPictureController = nil
        
        store.send(.stopped)
    }
    
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        // NOP
    }
        
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController) async -> Bool {
        @MainActor func updateStore() async {
            store.send(.restore)
        }
        
        await updateStore()
        return true
    }
}

struct PictureInPictureViewControllerRepresentable: UIViewControllerRepresentable {
    let store: StoreOf<PictureInPicture>
    
    func makeUIViewController(context: Context) -> PictureInPictureViewController {
        PictureInPictureViewController(store: store)
    }
    
    func updateUIViewController(_ uiViewController: PictureInPictureViewController, context: Context) {
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
