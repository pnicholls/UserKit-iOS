//
//  ScreenRecorderClient.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import ReplayKit

actor ScreenRecorderClient {
    struct Buffer {
        let sampleBuffer: CMSampleBuffer
        let bufferType: RPSampleBufferType
    }
    
    func start() async -> AsyncThrowingStream<Buffer, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                let recorder = RPScreenRecorder.shared()
                recorder.isMicrophoneEnabled = false
                recorder.isCameraEnabled = false

                do {
                    try await recorder.startCapture { sampleBuffer, bufferType, error in
                        if let error = error {
                            continuation.finish(throwing: error)
                        } else {
                            continuation.yield(
                                .init(sampleBuffer: sampleBuffer, bufferType: bufferType)
                            )
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
