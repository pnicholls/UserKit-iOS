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
    }
    
    public enum Action: Equatable {
        case appeared
        case start
        case started
    }
        
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appeared:
                return .none
                
            case .start:
                state.isActive = true
                return .none
                
            case .started:
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
    
    init(store: StoreOf<PictureInPicture>) {
        self.store = store
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubview(hostingViewController.view)
                
        NSLayoutConstraint.activate([
            hostingViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        pictureInPictureController = AVPictureInPictureController(contentSource: pictureInPictureControllerContentSource)
        pictureInPictureController?.canStartPictureInPictureAutomaticallyFromInline = false
        pictureInPictureController?.delegate = self
        
        // Create UIButton
        let button = UIButton(type: .system)
        
        // Set button title
        button.setTitle("Tap Me", for: .normal)
        
        // Set button appearance
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.frame = CGRect(x: 100, y: 200, width: 150, height: 50)
        
        // Add target action
        button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        
        // Add button to view
        view.addSubview(button)
        
        observe { [weak self] in
            guard let self else { return }
            
            if store.isActive {
                pictureInPictureController?.startPictureInPicture()
            } else {
                pictureInPictureController?.stopPictureInPicture()
            }
        }
    }
    
    @objc private func buttonTapped() {
        store.send(.start)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        store.send(.appeared)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        pictureInPictureController?.stopPictureInPicture()
    }
}

extension PictureInPictureViewController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
//        store.send(.started)
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
//        store.send(.pictureInPicture(.stop))
    }
    
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
//        store.send(.pictureInPicture(.stop))
    }
        
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController) async -> Bool {
//        @MainActor func updateStore() async {
//            store.send(.pictureInPicture(.restore))
//        }
//        
//        await updateStore()
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
