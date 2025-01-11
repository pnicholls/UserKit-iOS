import AVKit
import Combine
import ComposableArchitecture
import SwiftUI
import WebRTC

import ReplayKit

@Reducer
public struct Call {
    @Dependency(\.apiClient) var apiClient
    @Dependency(\.audioSessionClient) var audioSessionClient
    @Dependency(\.screenRecorderClient) var screenRecorderClient
    @Dependency(\.webRTCClient) var webRTCClient
    @Dependency(\.webSocketClient) var webSocketClient
        
    @Reducer
    public enum Destination {
        case active(Active)
        case requested(Requested)
    }
    
    @ObservableState
    public struct State: Equatable {
        let uuid: UUID = UUID()
        var destination: Destination.State = .requested(.init())
        var isPictureInPictureActive: Bool = false
        var participants: IdentifiedArrayOf<Participant.State>
        var sessionId: String? = nil
        var videoTrack: RTCVideoTrack?
    }
    
    public enum Action {
        public enum ApiClientAction {
            case postSessionResponse(Result<APIClient.PostSessionResponse, any Error>)
            case pullTracksResponse(Result<APIClient.PullTracksResponse, any Error>)
            case renegotiateResponse(Result<APIClient.RenegotiateResponse, any Error>)
        }

        public enum PictureInPictureAction {
            case start
            case stop
            case restore
        }
        
        public enum WebRTC {
            case pull
        }
        
        case apiClient(ApiClientAction)
        case appeared
        case participants(IdentifiedActionOf<Participant>)
        case pictureInPicture(PictureInPictureAction)
        case destination(Destination.Action)
        case webRTC(WebRTC)
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
            case .apiClient(.pullTracksResponse(.failure(_))):
                return .none
                
            case .apiClient(.pullTracksResponse(.success(let response))):
                guard let sessionId = state.sessionId else {
                    return .none
                }
                
                response.tracks.forEach { track in
                    let participant = state.participants.elements.first { participant in
                        participant.tracks.map { $0.id }.contains(track.trackName)
                    }
                    let participantTrack = participant?.tracks.first { $0.id == track.trackName }
                    guard let participant = participant, let participantTrack else {
                        return
                    }
                    state.participants[id: participant.id]?.tracks[id: participantTrack.id]?.mid = track.mid
                }
                
                if response.requiresImmediateRenegotiation {
                    return .run { send in
                        for try await _ in await webRTCClient.setRemoteDescription(.init(sdp: response.sessionDescription.sdp, type: .offer)) {
                            for try await sessionDescription in await webRTCClient.answer() {
                                for try await sessionDescription in await webRTCClient.setLocalDescription(sessionDescription) {
                                    await send(.apiClient(.renegotiateResponse(Result {
                                        try await apiClient.request(endpoint: .renegotiate(sessionId, .init(sessionDescription: .init(sdp: sessionDescription.sdp, type: "answer"))), as: APIClient.RenegotiateResponse.self)
                                    })))
                                }
                            }
                        }
                    }
                }
                
                return .none
                
            case .apiClient(.postSessionResponse(.failure(_))):
                return .none
            
            case .apiClient(.postSessionResponse(.success(let response))):
                state.sessionId = response.sessionId
                return .send(.webRTC(.pull))
            
            case .apiClient(.renegotiateResponse(.failure(_))):
                return .none
                
            case .apiClient(.renegotiateResponse(.success)):
                return .run { [state] send in
                    let transceivers = await webRTCClient.transceivers()
                                    
                    for participant in state.participants.filter({ $0.role == .host }).elements {
                        for track in participant.tracks.elements {
                            if let receiver = transceivers.filter({ $0.mediaType == .video }).first(where: { $0.mid == track.mid })?.receiver {
                                await send(.participants(.element(id: participant.id, action: .setReceiver(track.id, receiver))))
                            }
                        }
                    }
                }
                                                
            case .appeared:
                return .concatenate(
                    .run { send in
                        await audioSessionClient.configure()
                        await audioSessionClient.addNotificationObservers() // TODO: Remove observers when required
                    },
                    .run { send in
                        await webRTCClient.configure()
                    },
                    .run { send in
                        await send(.apiClient(.postSessionResponse(Result {
                            try await apiClient.request(endpoint: .postSession(.init()), as: APIClient.PostSessionResponse.self)
                        })))
                    }
                )
                
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
                
            case .destination(.requested(.accept)):
                state.destination = .active(.init(video: state.videoTrack != nil ? .init(track: state.videoTrack!) : nil))
                state.isPictureInPictureActive = true
                return .none
                
            case .destination(.requested(.decline)):
                return .none
                
            case .participants(.element(id: let id, action: .setReceiver(let trackId, let receiver))):
                guard let track = state.participants[id: id]?.tracks[id: trackId], track.trackType == .video, let track = receiver.track as? RTCVideoTrack else {
                    return .none
                }
                state.videoTrack = track
                
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
            
            case .webRTC(.pull):
                guard let sessionId = state.sessionId else {
                    assertionFailure("Session ID must be set")
                    return .none
                }
                
                let tracks: [APIClient.PullTracksRequest.Track] = state.participants.filter { $0.role == .host }.flatMap { participant -> [APIClient.PullTracksRequest.Track] in
                    return participant.tracks.map {
                        APIClient.PullTracksRequest.Track(
                            location: "remote",
                            trackName: $0.id,
                            sessionId: participant.sessionId
                        )
                    }
                }
                
                guard !tracks.isEmpty else {
                    return .none
                }
                                                        
                return .run { send in
                    await send(.apiClient(.pullTracksResponse(Result {
                        try await apiClient.request(
                            endpoint: .pullTracks(sessionId, .init(tracks: tracks)),
                            as: APIClient.PullTracksResponse.self
                        )
                    })))
                }
            }
        }
        .forEach(\.participants, action: \.participants) {
            Participant()
        }
    }
}

extension Call.Destination.State: Equatable {}

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
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        store.send(.appeared)
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
