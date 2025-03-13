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
    private let setupQueue = DispatchQueue(label: "com.camera.setup", qos: .userInitiated)
    
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
        guard (_captureSession?.isRunning ?? false) else {
            return
        }
        
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
        
        // Get front camera device on the main thread since device access needs it
        let deviceInfo: (AVCaptureDevice, AVCaptureDeviceInput)? = await MainActor.run {
            // Get front camera device
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                      for: .video,
                                                      position: .front) else {
                return nil
            }
            
            // Create device input
            guard let input = try? AVCaptureDeviceInput(device: device) else {
                return nil
            }
            
            return (device, input)
        }
        
        guard let (device, input) = deviceInfo else {
            print("Camera device or input unavailable")
            return
        }
        
        // Now perform camera setup on a background thread
        await withCheckedContinuation { continuation in
            setupQueue.async {
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
                
                // Important: Start the capture session on background thread
                print("Starting camera capture session on background thread")
                if !session.isRunning {
                    session.startRunning()
                }
                
                // Store the output reference in the actor
                Task {
                    await self.setVideoDataOutput(dataOutput)
                    continuation.resume()
                }
            }
        }
    }
    
    private func setVideoDataOutput(_ output: AVCaptureVideoDataOutput) {
        _videoDataOutput = output
    }
    
    private func stopCapture() async {
        // Get a local reference to the capture session inside the actor
        guard let session = _captureSession else { return }
        
        // Perform the stopRunning operation on a background thread
        await withCheckedContinuation { continuation in
            setupQueue.async {
                if session.isRunning {
                    session.stopRunning()
                }
                Task {
                    continuation.resume()
                }
            }
        }
    }
}
