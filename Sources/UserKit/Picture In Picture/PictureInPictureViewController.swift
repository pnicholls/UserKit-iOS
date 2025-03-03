//
//  PictureInPictureViewController.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import AVKit
import SwiftUI
import WebRTC
import Combine

// Helper function to create an async timer stream
func timerStream(interval: TimeInterval) -> AsyncStream<Date> {
    AsyncStream { continuation in
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            continuation.yield(Date())
        }
        
        continuation.onTermination = { _ in
            timer.invalidate()
        }
        
        // Add timer to RunLoop to ensure it fires
        RunLoop.current.add(timer, forMode: .common)
    }
}



final class PictureInPictureViewController: UIViewController {
    
    // MARK: - Properties

    private let manager: PictureInPictureManager
    private var cancellables = Set<AnyCancellable>()
    
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
    
    private var pictureInPictureController: AVPictureInPictureController?
    private var managerObservation: Task<Void, Never>?
            
    // MARK: - Functions
    
    init(manager: PictureInPictureManager) {
        self.manager = manager
        
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
        
        setupManagerObservation()
        setupTrackObservation()
    }
    
    private func setupManagerObservation() {
        // Create a Task that uses our timer stream
        managerObservation = Task { [weak self] in
            // Use our timer stream with 0.1s interval
            for await _ in timerStream(interval: 0.1) {
                guard let self = self else { break }
                
                // This doesn't use Task.sleep at all
                await MainActor.run {
                    self.updateUI()
                }
                
                // Check for cancellation
                if Task.isCancelled { break }
            }
        }
    }
    
    private func setupTrackObservation() {
        // Set the initial video track if it exists
        if let track = manager.videoTrack {
            print("PiP Controller: Adding initial video track to view")
            attachTrackToView(track)
        }
        
        // Use Combine to observe track changes
        manager.trackChanged
            .receive(on: RunLoop.main)
            .sink { [weak self] track in
                print("PiP Controller: Track changed notification received")
                self?.attachTrackToView(track)
            }
            .store(in: &cancellables)
    }
    
    private func attachTrackToView(_ track: RTCVideoTrack) {
        print("PiP Controller: Attaching track to view")
        track.add(pictureInPictureVideoCallViewController.videoView)
    }
    
    private func updateUI() {
        switch manager.state {
        case .starting where !(pictureInPictureController?.isPictureInPictureActive ?? false):
            print("PiP Controller: Starting PiP")
            pictureInPictureController?.startPictureInPicture()
        case .started where !(pictureInPictureController?.isPictureInPictureActive ?? false):
            print("PiP Controller: Starting PiP (from started state)")
            pictureInPictureController?.startPictureInPicture()
        case .stopped:
            print("PiP Controller: Stopping PiP")
            pictureInPictureController?.stopPictureInPicture()
        default:
            break
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // This is required
        Task {
            await MainActor.run {
                manager.start()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        managerObservation?.cancel()
    }
}

extension PictureInPictureViewController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("PiP Delegate: Will start PiP")
        Task {
            await MainActor.run {
                manager.started()
            }
        }
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("PiP Delegate: Did stop PiP")
        self.pictureInPictureController = nil
        
        Task {
            await MainActor.run {
                manager.stopped()
            }
        }
    }
    
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("PiP Delegate: Will stop PiP")
        // NOP
    }
        
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController) async -> Bool {
        print("PiP Delegate: Should restore PiP")
        await MainActor.run {
            manager.restore()
        }
        return true
    }
}

// View controller representable adaptor
class PictureInPictureVideoCallViewController: AVPictureInPictureVideoCallViewController {
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
