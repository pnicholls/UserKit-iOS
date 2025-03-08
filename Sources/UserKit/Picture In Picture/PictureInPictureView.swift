//
//  PictureInPictureView.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import SwiftUI
import UIKit

struct PictureInPictureView: UIViewControllerRepresentable {    
    func makeUIViewController(context: Context) -> PictureInPictureViewController {
        return PictureInPictureViewController()
    }
    
    func updateUIViewController(_ uiViewController: PictureInPictureViewController, context: Context) {
        // Update if needed
    }
}
