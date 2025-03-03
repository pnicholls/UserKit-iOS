//
//  CallView.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import SwiftUI

struct CallView: View {
    @ObservedObject var callManager: CallManager
    
    var body: some View {
        VStack {
            if let pipManager = callManager.pictureInPicture {
                PictureInPictureView(manager: pipManager)
            }
        }
        .onAppear {
            Task {
                await callManager.initialize()
            }
        }
        .alert(
            isPresented: Binding<Bool>(
                get: { callManager.alert != nil },
                set: { if !$0 { callManager.alert = nil } }
            )
        ) {
            if let alert = callManager.alert {
                Alert(
                    title: Text(alert.title),
                    primaryButton: .default(Text(alert.acceptText)) {
                        Task { await callManager.acceptCall() }
                    },
                    secondaryButton: .cancel(Text(alert.declineText)) {
                        Task { await callManager.declineCall() }
                    }
                )
            } else {
                Alert(title: Text(""))
            }
        }
    }
}

