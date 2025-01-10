//
//  File.swift
//  
//
//  Created by Peter Nicholls on 23/10/2024.
//

import ComposableArchitecture
import SwiftUI
import WebRTC
import AVKit
import Combine

@Reducer
public struct Video {
   @Dependency(\.webRTCClient) var webRTCClient
   
   @ObservableState
   public struct State: Equatable {
       var receiver: RTCRtpReceiver?
       var isPictureInPictureActive: Bool = false
   }
   
   public enum Action {
       case pictureInPicture(PictureInPictureAction)
       
       public enum PictureInPictureAction {
           case start
           case stop
           case restore
       }
   }
   
   public var body: some Reducer<State, Action> {
       Reduce { state, action in
           switch action {
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
   }
}

struct VideoView: View {
   @State var store: StoreOf<Video>
   
   var body: some View {
       if let track = store.receiver?.track as? RTCVideoTrack {
           TrackView(track: track, store: store)
       }
   }
}

struct TrackView: UIViewControllerRepresentable {
   var track: RTCVideoTrack
   var store: StoreOf<Video>
   
   func makeUIViewController(context: Context) -> UIViewController {
       let viewController = UIViewController()
       let videoView = RTCMTLVideoView()
       videoView.translatesAutoresizingMaskIntoConstraints = false
       
       viewController.view.addSubview(videoView)
       
       NSLayoutConstraint.activate([
           videoView.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
           videoView.topAnchor.constraint(equalTo: viewController.view.topAnchor),
           videoView.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
           videoView.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor)
       ])
       
       // Store the track and add it to the main video view
       context.coordinator.track = track
       track.add(videoView)
       
       let pictureInPictureControllerContentSource = AVPictureInPictureController.ContentSource(
           activeVideoCallSourceView: videoView,
           contentViewController: context.coordinator.pictureInPictureVideoCallViewController
       )
       
       context.coordinator.pictureInPictureController = AVPictureInPictureController(contentSource: pictureInPictureControllerContentSource)
       context.coordinator.pictureInPictureController?.delegate = context.coordinator
       context.coordinator.pictureInPictureController?.canStartPictureInPictureAutomaticallyFromInline = true
       
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
       // No updates needed since track is passed as prop
   }
   
   func makeCoordinator() -> Coordinator {
       Coordinator(store: store)
   }
   
   class Coordinator: NSObject {
       let store: StoreOf<Video>
       var cancellables: Set<AnyCancellable> = []
       let videoView = RTCMTLVideoView()
       var track: RTCVideoTrack?
       
       init(store: StoreOf<Video>) {
           self.store = store
       }
       
       lazy var pictureInPictureVideoCallViewController: AVPictureInPictureVideoCallViewController = {
           let pictureInPictureVideoCallViewController = AVPictureInPictureVideoCallViewController()
           videoView.translatesAutoresizingMaskIntoConstraints = false
           pictureInPictureVideoCallViewController.view.addSubview(videoView)
           
           NSLayoutConstraint.activate([
                videoView.leadingAnchor.constraint(equalTo: pictureInPictureVideoCallViewController.view.leadingAnchor),
                videoView.topAnchor.constraint(equalTo: pictureInPictureVideoCallViewController.view.topAnchor),
                videoView.trailingAnchor.constraint(equalTo: pictureInPictureVideoCallViewController.view.trailingAnchor),
                videoView.bottomAnchor.constraint(equalTo: pictureInPictureVideoCallViewController.view.bottomAnchor)
           ])
           
           if let track = self.track {
               track.add(videoView)
           }
           
           return pictureInPictureVideoCallViewController
       }()
       
       var pictureInPictureController: AVPictureInPictureController? = nil
   }
}

extension TrackView.Coordinator: AVPictureInPictureControllerDelegate {
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
