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
       var track: RTCVideoTrack
   }
   
   public enum Action {
   }
   
   public var body: some Reducer<State, Action> {
       Reduce { state, action in
           return .none
       }
   }
}

struct VideoView: View {
   @State var store: StoreOf<Video>
   
   var body: some View {
       TrackView(track: store.track)
   }
}

struct TrackView: UIViewRepresentable {
    var track: RTCVideoTrack
    
    func makeUIView(context: Context) -> some RTCMTLVideoView {
        let videoView = RTCMTLVideoView()
        track.add(videoView)
        return videoView
    }
    
    func updateUIView(_ uiView: UIViewType, context: Context) {
        
    }
}
