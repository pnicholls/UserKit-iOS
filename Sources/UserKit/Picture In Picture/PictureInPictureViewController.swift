//
//  PictureInPictureViewController.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import AVKit
import SwiftUI
import WebRTC

protocol PictureInPictureViewControllerDelegate: AnyObject {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController)
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController)
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController)
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController) async -> Bool
}

final class PictureInPictureViewController: UIViewController {
    
    // MARK: - Properties
        
    weak var delegate: PictureInPictureViewControllerDelegate?
    
    lazy var pictureInPictureController: AVPictureInPictureController = {
        let pictureInPictureController = AVPictureInPictureController(contentSource: pictureInPictureControllerContentSource)
        return pictureInPictureController
    }()
        
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
    
    private var videoTrack: RTCVideoTrack? {
        didSet {
            videoTrack?.add(pictureInPictureVideoCallViewController.videoView)
        }
    }
                
    // MARK: - Functions
            
    override func viewDidLoad() {
        super.viewDidLoad()
                        
        view.backgroundColor = .clear
        
        // Picture in picture needs to be called here,
        // something about being a lazy var causes it not to start
        pictureInPictureController.delegate = self
        pictureInPictureController.canStartPictureInPictureAutomaticallyFromInline = false
    }
        
    func set(track: RTCVideoTrack?) {
        self.videoTrack = track
    }
}

extension PictureInPictureViewController: AVPictureInPictureControllerDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: any Error) {
        assertionFailure("Failed to start picture in picture: \(error)")
    }
    
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        delegate?.pictureInPictureControllerWillStartPictureInPicture(pictureInPictureController)
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        delegate?.pictureInPictureControllerDidStopPictureInPicture(pictureInPictureController)
    }
    
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        delegate?.pictureInPictureControllerWillStopPictureInPicture(pictureInPictureController)
    }
        
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController) async -> Bool {
        guard let delegate = delegate else {
            return true
        }
        
        return await delegate.pictureInPictureController(pictureInPictureController)
    }
}

class PictureInPictureVideoCallViewController: AVPictureInPictureVideoCallViewController {
    
    // MARK: - Properties
    
    lazy var videoView: RTCMTLVideoView = {
        let videoView = RTCMTLVideoView()
        videoView.translatesAutoresizingMaskIntoConstraints = false
        return videoView
    }()
        
    // MARK: - Functions
    
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
