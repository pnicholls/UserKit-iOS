//
//  CameraClient.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

//
//  CameraClient.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

//
//  CameraClient.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import AVKit

// Helper class to handle camera delegate callbacks - moved outside the actor
class CameraBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let handler: (CMSampleBuffer, AVCaptureConnection) -> Void
    
    init(handler: @escaping (CMSampleBuffer, AVCaptureConnection) -> Void) {
        self.handler = handler
        super.init()
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        handler(sampleBuffer, connection)
    }
}

actor CameraClient {
    // These properties need to be accessible from MainActor context
    // but still protected by the actor isolation
    private var _captureSession: AVCaptureSession?
    private var _videoDataOutput: AVCaptureVideoDataOutput?
    
    // Create a nonisolated delegate to maintain actor isolation
    private var bufferDelegate: CameraBufferDelegate?
    
    private let captureQueue = DispatchQueue(label: "com.camera.capture")
    
    struct Buffer {
        let sampleBuffer: CMSampleBuffer
        let connection: AVCaptureConnection
    }
    
    enum CameraError: Error {
        case deviceNotAvailable
        case inputCreationFailed
    }
    
    func requestAccess() async -> Bool {
        return await AVCaptureDevice.requestAccess(for: .video)
    }
    
    func start() async -> AsyncStream<Buffer> {
        AsyncStream { continuation in
            Task {
                await setupCamera { buffer in
                    continuation.yield(buffer)
                }
            }
            
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.stopCapture()
                }
            }
        }
    }
    
    func stop() async {
        await stopCapture()
    }
    
    private func setupCamera(handler: @escaping (Buffer) -> Void) async {
        // Create the required objects within the actor context
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        // Store the local references
        _captureSession = session
        
        // Create an isolated delegate for the buffer
        let bufferDelegate = CameraBufferDelegate { buffer, connection in
            handler(Buffer(sampleBuffer: buffer, connection: connection))
        }
        self.bufferDelegate = bufferDelegate
        
        // Now perform UI-related setup on the main thread
        await MainActor.run {
            // Get front camera device
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                      for: .video,
                                                      position: .front) else {
                return
            }
            
            // Create device input
            guard let input = try? AVCaptureDeviceInput(device: device) else {
                return
            }
            
            // Add input to session
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            // Setup video data output
            let dataOutput = AVCaptureVideoDataOutput()
            dataOutput.setSampleBufferDelegate(
                bufferDelegate,
                queue: self.captureQueue
            )
            dataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            // Add output to session
            if session.canAddOutput(dataOutput) {
                session.addOutput(dataOutput)
            }
            
            // Store the output reference in the actor
            Task {
                await self.setVideoDataOutput(dataOutput)
            }
            
            // Start the capture session
            if !session.isRunning {
                session.startRunning()
            }
        }
    }
    
    private func setVideoDataOutput(_ output: AVCaptureVideoDataOutput) {
        _videoDataOutput = output
    }
    
    private func stopCapture() async {
        // Get a local reference to the capture session inside the actor
        guard let session = _captureSession else { return }
        
        // Perform the UI operation on the main thread
        await MainActor.run {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }
    
    // The CameraBufferDelegate class has been moved outside the actor
}
