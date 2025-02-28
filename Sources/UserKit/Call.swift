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
    @Dependency(\.cameraClient) var cameraClient
    @Dependency(\.screenRecorderClient) var screenRecorderClient
    @Dependency(\.webRTCClient) var webRTCClient
    @Dependency(\.webSocketClient) var webSocketClient
            
    @ObservableState
    public struct State: Equatable {
        @Presents var alert: AlertState<Action.Alert>?
        var pictureInPicture: PictureInPicture.State?
        var participants: IdentifiedArrayOf<Participant.State>
        var sessionId: String? = nil
    }
    
    public enum Action {
        @CasePathable
        public enum Alert {
            case accept
            case `continue`
            case decline
            case end
        }
        
        public enum ApiClientAction {
            case postSessionResponse(Result<APIClient.PostSessionResponse, any Error>)
        }
        
        public enum WebRTC: Equatable {
            public enum Configure: Equatable {
                case failure
                case success
            }
            
            case configure(Configure)
            case push
            case pull
        }
        
        case alert(PresentationAction<Alert>)
        case apiClient(ApiClientAction)
        case appeared
        case participants(IdentifiedActionOf<Participant>)
        case pictureInPicture(PictureInPicture.Action)
        case webRTC(WebRTC)
    }
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .alert(.presented(.accept)):
                state.alert = nil
                state.pictureInPicture = .init()
                
                guard let participant = state.participants.first(where: { $0.role == .user }) else {
                    return .none
                }

                state.participants[id: participant.id]?.state = .joined
                
                switch state.sessionId {
                case .some:
                    return .run { send in
                        do {
                            try await webRTCClient.configure()
                            await send(.webRTC(.configure(.success)))
                        } catch {
                            await send(.webRTC(.configure(.failure)))
                        }
                    }
                default:
                    return .none
                }
                
            case .alert(.presented(.continue)):
                let videoTrack = state.participants.flatMap { $0.tracks.compactMap { $0.receiver?.track } }.first as? RTCVideoTrack
                state.pictureInPicture = .init(state: .starting, videoTrack: videoTrack)
                state.alert = nil
                return .none
                
            case .alert(.presented(.decline)):
                guard let participant = state.participants.first(where: { $0.role == .user }) else {
                    return .none
                }

                state.participants[id: participant.id]?.state = .declined
                return .none
                
            case .alert(.presented(.end)):
                state.alert = nil
                return .run { send in
                    await webRTCClient.close()
                    await audioSessionClient.removeNotificationObservers()
                }
                
            case .alert(.dismiss):
                state.alert = nil
                return .none
                                                                
            case .apiClient(.postSessionResponse(.failure(_))):
                return .none
            
            case .apiClient(.postSessionResponse(.success(let response))):
                state.sessionId = response.sessionId

                guard let participant = state.participants.first(where: { $0.role == .user }) else {
                    return .none
                }
                
                switch participant.state {
                case .joined:
                    return .run { send in
                        do {
                            try await webRTCClient.configure()
                            await send(.webRTC(.configure(.success)))
                        } catch {
                            await send(.webRTC(.configure(.failure)))
                        }
                    }
                default:
                    return .none
                }
                                                
            case .appeared:
                return .run { send in
                    await send(.apiClient(.postSessionResponse(Result {
                        try await apiClient.request(endpoint: .postSession(.init()), as: APIClient.PostSessionResponse.self)
                    })))
                }
                                                
            case .participants(.element(id: let participantId, action: .tracks(.element(id: let trackId, action: .request)))):
                guard let track = state.participants[id: participantId]?.tracks[id: trackId] else {
                    return .none
                }
                
                switch track.type {
                case .screenShare:
                    state.pictureInPicture?.state = .stopped
                    
                    return .concatenate(
                        .run { send in try await Task.sleep(nanoseconds: 1 * 1_000_000_000) },
                        .send(.participants(.element(id: participantId, action: .tracks(.element(id: trackId, action: .start)))))
                    )
                    
                default:
                    break
                }

                return .none
                
            case .participants(.element(id: let participantId, action: .tracks(.element(id: let trackId, action: .requestAccepted)))):
                guard let track = state.participants[id: participantId]?.tracks[id: trackId] else {
                    return .none
                }
                state.participants[id: participantId]?.tracks[id: trackId]?.state = .active
                
                switch track.type {
                case .screenShare:
                    let videoTrack = state.participants.flatMap { $0.tracks.compactMap { $0.receiver?.track } }.first as? RTCVideoTrack
                    state.pictureInPicture = .init(state: .starting, videoTrack: videoTrack)
                default:
                    break
                }

                return .run { [state] send in
                    guard let participant = state.participants.first(where: { $0.role == .user }), participant.state == .joined else {
                        return
                    }
                    
                    let tracks: [[String: Any]] = await webRTCClient.localTransceivers().map { type, transceiver in
                        let transceiverTrackId = transceiver.sender.track!.trackId
                        let trackState = state.participants[id: participantId]?.tracks[id: transceiverTrackId]
                        
                        return [
                            "id": "\(state.sessionId!)/\(transceiverTrackId)",
                            "type": type,
                            "state": transceiverTrackId == trackId ? "active" : (trackState?.state.rawValue ?? "inactive")
                        ]
                    }
                    
                    let data: [String: Any] = [
                        "state": participant.state.rawValue,
                        "transceiverSessionId": state.sessionId!,
                        "tracks": tracks
                    ]

                    let participantUpdate: [String: Any] = [
                        "type": "participantUpdate",
                        "participant": data
                    ]

                    let jsonData = try JSONSerialization.data(withJSONObject: participantUpdate, options: .prettyPrinted)
                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                        try await webSocketClient.send(id: WebSocketClient.ID(), message: .string(jsonString))
                    }
                }
                
            case .participants(.element(id: let participantId, action: .tracks(.element(id: _, action: .pull)))):
                return .none
                
            case .participants(.element(id: let id, action: .setReceiver(let trackId, let receiver))):
                guard let track = state.participants[id: id]?.tracks[id: trackId], track.type == .video, let track = receiver.track as? RTCVideoTrack else {
                    return .none
                }
                
                state.pictureInPicture?.videoTrack = track
                return .none
                                                
            case .participants:
                return .none
                            
            case .pictureInPicture(.restore):
                state.pictureInPicture = nil
                
                guard let participant = state.participants.first(where: { $0.role == .user }) else {
                    return .none
                }
                
                if participant.tracks.contains(where: { $0.type == .screenShare && $0.state == .requested }) {
                    return .none
                }
                
                state.alert = AlertState {
                    TextState("You are still in a call with Luke Longworth")
                } actions: {
                    ButtonState(action: .continue) {
                        TextState("Continue")
                    }
                    ButtonState(action: .end) {
                        TextState("End")
                    }
                }
                return .none
                
            case .pictureInPicture(.started):
                return .none
                
            case .pictureInPicture:
                return .none
                
            case .webRTC(.configure(.failure)):
                return .none
                
            case .webRTC(.configure(.success)):
                return .concatenate(
                    .send(.webRTC(.push)),
                    .run { send in
                        let jsonData = try JSONSerialization.data(withJSONObject: ["type": "participantJoined"], options: .prettyPrinted)
                        if let jsonString = String(data: jsonData, encoding: .utf8) {
                            try await webSocketClient.send(id: WebSocketClient.ID(), message: .string(jsonString))
                        }
                    }
                )
                
            case .webRTC(.push):
                guard let sessionId = state.sessionId else {
                    assertionFailure("Session ID must be set")
                    return .none
                }
                                                                        
                return .run { [state] send in
                    for try await offer in await webRTCClient.offer() {
                        for try await sessionDescription in await webRTCClient.setLocalDescription(offer) {
                            let transceivers = await webRTCClient.localTransceivers()
                            
                            let tracks = transceivers.map { type, transceiver in
                                APIClient.PushTracksRequest.Track(
                                    location: "local",
                                    trackName: transceiver.sender.track!.trackId,
                                    mid: transceiver.mid
                                )
                            }
                            
                            guard !tracks.isEmpty else {
                                return
                            }

                            let response = try await apiClient.request(
                                endpoint: .pushTracks(sessionId, .init(sessionDescription: .init(sdp: sessionDescription.sdp, type: "offer"), tracks: tracks)),
                                as: APIClient.PushTracksResponse.self
                            )

                            await webRTCClient.setRemoteDescription(.init(sdp: response.sessionDescription.sdp, type: .answer))

                            guard let participant = state.participants.first(where: { $0.role == .user }) else {
                                return
                            }

                            let localTracks: [[String: Any]] = await webRTCClient.localTransceivers().map { type, transceiver in
                                [
                                    "id": "\(state.sessionId!)/\(transceiver.sender.track!.trackId)",
                                    "type": type,
                                    "state": "inactive"
                                ]
                            }
                            
                            let data: [String: Any] = [
                                "state": participant.state.rawValue,
                                "transceiverSessionId": state.sessionId!,
                                "tracks": localTracks
                            ]

                            let participantUpdate: [String: Any] = [
                                "type": "participantUpdate",
                                "participant": data
                            ]

                            let jsonData = try JSONSerialization.data(withJSONObject: participantUpdate, options: .prettyPrinted)
                            if let jsonString = String(data: jsonData, encoding: .utf8) {
                                try await webSocketClient.send(id: WebSocketClient.ID(), message: .string(jsonString))
                            }

                            for participant in state.participants {
                                for track in participant.tracks {
                                    switch track.pullState {
                                    case .notPulled, .failed(_):
                                        await send(.participants(.element(id: participant.id, action: .tracks(.element(id: track.id, action: .pull)))))
                                    default:
                                        break
                                    }
                                }
                            }
                        }
                    }
                }
                
            case .webRTC(.pull):
                return .none
//                guard let sessionId = state.sessionId else {
//                    return .none
//                }
//                
//                var tracks: [APIClient.PullTracksRequest.Track] = []
//                state.participants.filter { $0.role == .host }.forEach { participant in
//                    guard let participantSessionId = participant.sessionId else {
//                        return
//                    }
//                    
//                    participant.tracks.filter { $0.pullState == .notPulled }.forEach { track in
//                        state.participants[id: participant.id]?.tracks[id: track.id]?.pullState = .pulling
//
//                        tracks.append(APIClient.PullTracksRequest.Track(
//                            location: "remote",
//                            trackName: track.id,
//                            sessionId: participantSessionId
//                        ))
//                    }
//                }
//                
//                guard !tracks.isEmpty else {
//                    return .none
//                }
                
//                return .run {
//                    let pullTracksResponse = try await apiClient.request(
//                        endpoint: .pullTracks(sessionId, .init(tracks: tracks)),
//                        as: APIClient.PullTracksResponse.self
//                    )
//                                    
//                    pullTracksResponse.tracks.forEach { track in
//                        let participant = state.participants.elements.first { participant in
//                            participant.tracks.map { $0.id }.contains(track.trackName)
//                        }
//                        let participantTrack = participant?.tracks.first { $0.id == track.trackName }
//                        guard let participant = participant, let participantTrack else {
//                            return
//                        }
//                        state.participants[id: participant.id]?.tracks[id: participantTrack.id]?.mid = track.mid
//                        
//                        switch track.errorCode {
//                        case .none:
//                            state.participants[id: participant.id]?.tracks[id: participantTrack.id]?.pullState = .pulled
//                        case .some(let errorCode):
//                            state.participants[id: participant.id]?.tracks[id: participantTrack.id]?.pullState = .failed(.init(rawValue: errorCode) ?? .unknown)
//                        }
//                    }
//      
//                    if let sessionDescription = pullTracksResponse.sessionDescription, pullTracksResponse.requiresImmediateRenegotiation {
//                        return .run { send in
//                            for try await _ in await webRTCClient.setRemoteDescription(.init(sdp: sessionDescription.sdp, type: .offer)) {
//                                for try await sessionDescription in await webRTCClient.answer() {
//                                    for try await sessionDescription in await webRTCClient.setLocalDescription(sessionDescription) {
//                                        
//    //                                    return .merge(
//    //                                        .run { [state] send in
//    //                                            let transceivers = await webRTCClient.transceivers()
//    //
//    //                                            for participant in state.participants.filter({ $0.role == .host }).elements {
//    //                                                for track in participant.tracks.elements {
//    //                                                    if let receiver = transceivers.filter({ $0.mediaType == .video }).first(where: { $0.mid == track.mid })?.receiver {
//    //                                                        await send(.participants(.element(id: participant.id, action: .setReceiver(track.id, receiver))))
//    //                                                    }
//    //                                                }
//    //                                            }
//    //                                        }
//    //                                    )
//                                        
//                                        await send(.apiClient(.renegotiateResponse(Result {
//                                            try await apiClient.request(endpoint: .renegotiate(sessionId, .init(sessionDescription: .init(sdp: sessionDescription.sdp, type: "answer"))), as: APIClient.RenegotiateResponse.self)
//                                        })))
//                                    }
//                                }
//                            }
//                        }
//                    }
//                    
//                    return .run { [participants = state.participants] send in
//                        try await Task.sleep(nanoseconds: 3 * 1_000_000_000)
//                        
//                        for participant in participants {
//                            for track in participant.tracks {
//                                if case .failed(_) = track.pullState {
//                                    await send(.participants(.element(id: participant.id, action: .tracks(.element(id: track.id, action: .pull)))))
//                                }
//                            }
//                        }
//                    }

//                }
            }
        }
        .forEach(\.participants, action: \.participants) {
            Participant()
        }
        .ifLet(\.pictureInPicture, action: \.pictureInPicture) {
            PictureInPicture()
        }
    }
}

struct CallView: View {
    @Perception.Bindable var store: StoreOf<Call>
    
    var body: some View {
        WithPerceptionTracking {
            VStack {
                if let store = store.scope(state: \.pictureInPicture, action: \.pictureInPicture) {
                    PictureInPictureViewControllerRepresentable(store: store)
                }
            }
            .alert($store.scope(state: \.alert, action: \.alert))
        }
        .onAppear { store.send(.appeared) }
    }
}
