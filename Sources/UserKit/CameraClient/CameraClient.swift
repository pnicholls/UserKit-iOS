//
//  CameraClient.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import AVKit

actor CameraClient {
    private var captureSession: AVCaptureSession?
    private var videoDataOutput: AVCaptureVideoDataOutput?
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
        // Run on main thread for UI-related capture session setup
        await MainActor.run {
            // Initialize capture session
            let session = AVCaptureSession()
            session.sessionPreset = .high
            
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
                CameraBufferDelegate { buffer, connection in
                    handler(Buffer(sampleBuffer: buffer, connection: connection))
                },
                queue: captureQueue
            )
            dataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            // Add output to session
            if session.canAddOutput(dataOutput) {
                session.addOutput(dataOutput)
            }
            
            // Store references
            self.captureSession = session
            self.videoDataOutput = dataOutput
            
            // Start capture
            if !session.isRunning {
                session.startRunning()
            }
        }
    }
    
    private func stopCapture() async {
        // Run on main thread for UI-related capture session teardown
        await MainActor.run {
            guard let session = captureSession, session.isRunning else { return }
            session.stopRunning()
        }
    }
    
    // Helper class to handle camera delegate callbacks
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
}
