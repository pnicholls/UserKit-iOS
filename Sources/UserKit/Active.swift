import AVKit
import Combine
import ComposableArchitecture
import SwiftUI
import WebRTC

@Reducer
public struct Active {
    @Dependency(\.apiClient) var apiClient
    @Dependency(\.audioSessionClient) var audioSessionClient
    @Dependency(\.webRTCClient) var webRTCClient

    @ObservableState
    public struct State: Equatable {
        var sessionId: String? = nil
        var isPictureInPictureActive: Bool = false
        var participants: IdentifiedArrayOf<Participant.State>
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
            case configure
            case pull
        }

        case apiClient(ApiClientAction)
        case appeared
        case `continue`
        case end
        case participants(IdentifiedActionOf<Participant>)
        case pictureInPicture(PictureInPictureAction)
        case webRTC(WebRTC)
    }
    
    public var body: some ReducerOf<Self> {
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
                            if let receiver = transceivers.first(where: { $0.mid == track.mid })?.receiver {
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
                
            case .continue:
                state.isPictureInPictureActive = true
                return .none
                
            case .end:
                state.isPictureInPictureActive = false
                return .none
                
            case .webRTC(.configure):
                return .run { send in
                    await webRTCClient.configure()
                }
                
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
                
            default:
                return .none
            }
        }
        .forEach(\.participants, action: \.participants) {
            Participant()
        }
    }
}

struct ActiveView: View {
    @Environment(\.colorScheme) var colorScheme
    @Bindable var store: StoreOf<Active>
    
    var body: some View {
        WithPerceptionTracking {
            VStack {
                VideoView(store: store)
                
                ForEach(store.scope(state: \.participants, action: \.participants)) { store in
                  ParticipantView(store: store)
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
            }.onAppear {
                store.send(.appeared)
            }
        }
    }
}

fileprivate struct VideoView: UIViewControllerRepresentable {
    var store: StoreOf<Active>

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .green

        let pictureInPictureControllerContentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: viewController.view,
            contentViewController: context.coordinator.pictureInPictureVideoCallViewController
        )

        context.coordinator.pictureInPictureController = AVPictureInPictureController(contentSource: pictureInPictureControllerContentSource)
        context.coordinator.pictureInPictureController?.delegate = context.coordinator
        context.coordinator.pictureInPictureController?.canStartPictureInPictureAutomaticallyFromInline = false
                
        store.publisher.isPictureInPictureActive.removeDuplicates().sink { isPictureInPictureActive in
            guard let pictureInPictureController = context.coordinator.pictureInPictureController else { return }
            
            if isPictureInPictureActive, !pictureInPictureController.isPictureInPictureActive {
                pictureInPictureController.startPictureInPicture()
            }
            
            if !isPictureInPictureActive && pictureInPictureController.isPictureInPictureActive {
                pictureInPictureController.stopPictureInPicture()
            }
        }.store(in: &context.coordinator.cancellables)

        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // NOP
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    class Coordinator: NSObject {
        let store: StoreOf<Active>
        var cancellables: Set<AnyCancellable> = []

        init(store: StoreOf<Active>) {
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
        @MainActor func updateStore() {
            store.send(.pictureInPicture(.restore))
        }

        await updateStore()
        return true
    }
}
