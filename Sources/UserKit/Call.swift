import AVKit
import ComposableArchitecture
import SwiftUI

@Reducer
public struct Call {
    @Dependency(\.webSocketClient) var webSocketClient
    
    @ObservableState
    public struct State: Equatable {
        var participants: IdentifiedArrayOf<Participant.State> = []
        var isPiPActive: Bool = false
    }
    
    public enum Action {
        case `init`
        case decline
        case reload
        case join
        case setPiPActive(Bool)
    }
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .`init`:
                return .none
                
            case .decline:
                return .run { send in
                    let dictionary: [String: Any] = [
                        "type": "participantUpdate",
                        "participant": [
                            "state": "declined",
                            "tracks": []
                        ]
                    ]
                    let jsonData = try! JSONSerialization.data(withJSONObject: dictionary, options: [])
                    let jsonString = String(data: jsonData, encoding: .utf8)
                
                    try await webSocketClient.send(id: WebSocketClient.ID(), message: .string(jsonString!))
                }
                
            case .reload:
                return .none
                
            case .join:
                state.isPiPActive = true
                return .run { send in
                    let dictionary: [String: Any] = [
                        "type": "participantUpdate",
                        "participant": [
                            "state": "joined",
                            "tracks": []
                        ]
                    ]
                    let jsonData = try! JSONSerialization.data(withJSONObject: dictionary, options: [])
                    let jsonString = String(data: jsonData, encoding: .utf8)
                
                    try await webSocketClient.send(id: WebSocketClient.ID(), message: .string(jsonString!))
                }
                
            case let .setPiPActive(isActive):
                state.isPiPActive = isActive
                return .none
            }
        }
    }
}

extension Notification.Name {
    static let pipDidStop = Notification.Name("pipDidStop")
}

struct CallView: View {
    @Environment(\.colorScheme) var colorScheme
    @Bindable var store: StoreOf<Call>
    
    var body: some View {
        VStack {
            PiPCallView(isPiPActive: store.isPiPActive)
                .onAppear {
                    setupAudioSession()
                    setupNotifications()
                }
                .onDisappear {
                    NotificationCenter.default.removeObserver(self)
                }
            
            Spacer()
            
            VStack(spacing: 12) {
                Button(action: handleJoin) {
                    Text("Join Call")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.primary)
                        .cornerRadius(8)
                }
                
                Button(action: handleDecline) {
                    Text("Decline")
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
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback)
            try audioSession.setActive(true, options: [])
        } catch {
            print("Setting category to AVAudioSessionCategoryPlayback failed.")
        }
    }
    
    private func handleJoin() {
        store.send(.join)
    }
    
    private func handleDecline() {
        store.send(.decline)
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .pipDidStop,
            object: nil,
            queue: .main
        ) { [store] _ in
            store.send(.setPiPActive(false))
        }
    }
}

struct PiPCallView: UIViewControllerRepresentable {
    let isPiPActive: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
        func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
            return .zero
        }
        
        func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
            return false
        }
        
        var pipController: AVPictureInPictureController?
        var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer?
        
        // MARK: - AVPictureInPictureControllerDelegate
        
        func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            print("PiP will start")
        }
        
        func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            print("PiP did start")
        }
        
        func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
            print("PiP failed to start with error: \(error.localizedDescription)")
        }
        
        func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            print("PiP will stop")
        }
        
        func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            print("PiP did stop")
            Task { @MainActor in
                NotificationCenter.default.post(name: .pipDidStop, object: nil)
            }
        }
        
        func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
            print("PiP restore UI requested")
            Task { @MainActor in
                NotificationCenter.default.post(name: .pipDidStop, object: nil)
                completionHandler(true)
            }
        }
        
        // MARK: - AVPictureInPictureSampleBufferPlaybackDelegate
        
        func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
            // For static frame, no action needed
        }
        
        func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
            // For static frame, no action needed
        }
        
        func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
            completionHandler()
        }
        
        func createStaticSampleBuffer() -> CMSampleBuffer? {
            let width = 90
            let height = 160
            
            // Create a green CGImage
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
            guard let context = CGContext(data: nil,
                                        width: width,
                                        height: height,
                                        bitsPerComponent: 8,
                                        bytesPerRow: width * 4,
                                        space: colorSpace,
                                        bitmapInfo: bitmapInfo.rawValue) else {
                return nil
            }
            
            context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            
            guard let image = context.makeImage() else { return nil }
            
            var pixelBuffer: CVPixelBuffer?
            let attrs = [
                kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
            ] as CFDictionary
            
            CVPixelBufferCreate(kCFAllocatorDefault,
                               width,
                               height,
                               kCVPixelFormatType_32ARGB,
                               attrs,
                               &pixelBuffer)
            
            if let pixelBuffer = pixelBuffer {
                CVPixelBufferLockBaseAddress(pixelBuffer, [])
                let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)
                
                let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
                guard let context = CGContext(data: pixelData,
                                            width: width,
                                            height: height,
                                            bitsPerComponent: 8,
                                            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                            space: rgbColorSpace,
                                            bitmapInfo: bitmapInfo.rawValue)
                else {
                    return nil
                }
                
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
                
                var timing = CMSampleTimingInfo()
                timing.duration = CMTime(value: 1, timescale: 30)
                timing.presentationTimeStamp = CMTime(value: 0, timescale: 30)
                timing.decodeTimeStamp = CMTime.invalid
                
                var videoInfo: CMVideoFormatDescription?
                CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                           imageBuffer: pixelBuffer,
                                                           formatDescriptionOut: &videoInfo)
                
                if let videoInfo = videoInfo {
                    var sampleBuffer: CMSampleBuffer?
                    CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: pixelBuffer,
                                                     dataReady: true,
                                                     makeDataReadyCallback: nil,
                                                     refcon: nil,
                                                     formatDescription: videoInfo,
                                                     sampleTiming: &timing,
                                                     sampleBufferOut: &sampleBuffer)
                    return sampleBuffer
                }
            }
            return nil
        }
        
        func setupPiPController() {
            guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
            
            if sampleBufferDisplayLayer == nil {
                let displayLayer = AVSampleBufferDisplayLayer()
                displayLayer.videoGravity = .resizeAspect
                sampleBufferDisplayLayer = displayLayer
                
                // Create PiP controller with sample buffer display layer
                let contentSource = AVPictureInPictureController.ContentSource(
                    sampleBufferDisplayLayer: displayLayer,
                    playbackDelegate: self
                )
                
                pipController = AVPictureInPictureController(contentSource: contentSource)
                pipController?.delegate = self
                pipController?.canStartPictureInPictureAutomaticallyFromInline = false
                
                // Enqueue a static frame
//                if let sampleBuffer = createStaticSampleBuffer() {
//                    displayLayer.flushAndRemoveImage()
//                    displayLayer.enqueue(sampleBuffer)
//                }
            }
        }
        
        func startPiPIfNeeded() {
            guard let pipController = pipController else {
                print("No PiP controller available")
                return
            }
            
            if !pipController.isPictureInPictureActive {
                print("Attempting to start PiP")
                // Ensure we have a frame displayed
                if let displayLayer = sampleBufferDisplayLayer,
                   let sampleBuffer = createStaticSampleBuffer() {
                    displayLayer.flushAndRemoveImage()
                    displayLayer.enqueue(sampleBuffer)
                }
                pipController.startPictureInPicture()
            }
        }
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .yellow
        let containerView = UIView()
        containerView.backgroundColor = .blue  // Change from .blue to .clear
        
        viewController.view.addSubview(containerView)
        containerView.frame = viewController.view.bounds
        containerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // Setup the sample buffer display layer
        context.coordinator.setupPiPController()
        if let displayLayer = context.coordinator.sampleBufferDisplayLayer {
            displayLayer.frame = containerView.bounds
            containerView.layer.addSublayer(displayLayer)
        }
        
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if isPiPActive {
            context.coordinator.startPiPIfNeeded()
        }
    }
    
    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        coordinator.sampleBufferDisplayLayer?.removeFromSuperlayer()
    }
}

#Preview("Light Mode") {
    CallView(store: Store(initialState: Call.State()) {
        Call()
    })
    .environment(\.colorScheme, .light)
}

#Preview("Dark Mode") {
    CallView(store: Store(initialState: Call.State()) {
        Call()
    })
    .environment(\.colorScheme, .dark)
}
