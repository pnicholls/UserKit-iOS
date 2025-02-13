//
//  Untitled.swift
//  UserKit
//
//  Created by Peter Nicholls on 12/1/2025.
//

import Foundation
import Dependencies
import DependenciesMacros
import AVFoundation

public struct CameraClient {
    public var requestAccess: @Sendable () async -> Bool
    public var start: @Sendable () async -> AsyncThrowingStream<Buffer, Error> = { .finished() }
    public var stop: @Sendable () async -> ()
}

extension CameraClient {
    public struct Buffer {
        let sampleBuffer: CMSampleBuffer
        let connection: AVCaptureConnection
    }
}

extension CameraClient: DependencyKey {
    public static var liveValue: CameraClient {
        let client = Client()
        return CameraClient(
            requestAccess: {
                await client.requestAccess()
            },
            start: {
                await client.start()
            },
            stop: {
                await client.stopCapture()
            }
        )
    }
}

extension DependencyValues {
    public var cameraClient: CameraClient {
        get { self[CameraClient.self] }
        set { self[CameraClient.self] = newValue }
    }
}

private actor Client: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var captureSession: AVCaptureSession?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private let captureQueue = DispatchQueue(label: "com.camera.capture")
    private var continuation: AsyncThrowingStream<CameraClient.Buffer, Error>.Continuation?
    
    func requestAccess() async -> Bool {
        return await AVCaptureDevice.requestAccess(for: .video)
    }
    
    func start() -> AsyncThrowingStream<CameraClient.Buffer, Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            
            Task {
                await setupCamera()
                await startCapture()
            }
            
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.stopCapture()
                }
            }
        }
    }
    
    private func setupCamera() async {
        // Initialize capture session
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        // Get front camera device
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                 for: .video,
                                                 position: .front) else {
            continuation?.finish(throwing: CameraError.deviceNotAvailable)
            return
        }
        
        // Create device input
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            continuation?.finish(throwing: CameraError.inputCreationFailed)
            return
        }
        
        // Add input to session
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        // Setup video data output
        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.setSampleBufferDelegate(self, queue: captureQueue)
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
    }
    
    private func startCapture() async {
        guard let session = captureSession else { return }
        
        if !session.isRunning {
            session.startRunning()
        }
    }
    
    func stopCapture() async {
        guard let session = captureSession else { return }
        
        if session.isRunning {
            session.stopRunning()
        }
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        Task { [weak self] in
            await self?.continuation?.yield(.init(sampleBuffer: sampleBuffer, connection: connection))
        }
    }
}

enum CameraError: Error {
    case deviceNotAvailable
    case inputCreationFailed
}
