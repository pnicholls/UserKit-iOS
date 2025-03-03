//
//  PictureInPictureView.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import SwiftUI
import UIKit

struct PictureInPictureView: UIViewControllerRepresentable {
    @ObservedObject var manager: PictureInPictureManager
    
    func makeUIViewController(context: Context) -> PictureInPictureViewController {
        return PictureInPictureViewController(manager: manager)
    }
    
    func updateUIViewController(_ uiViewController: PictureInPictureViewController, context: Context) {
        // Update if needed
    }
}
