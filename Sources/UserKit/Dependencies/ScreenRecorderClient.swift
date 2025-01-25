//
//  File.swift
//  
//
//  Created by Peter Nicholls on 16/9/2024.
//

import Foundation
import Dependencies
import DependenciesMacros
import ReplayKit

public struct ScreenRecorderClient {
    public var start: @Sendable () async -> AsyncThrowingStream<Buffer, Error> = { .finished() }
}

extension ScreenRecorderClient {
    public struct Buffer {
        let sampleBuffer: CMSampleBuffer
        let bufferType: RPSampleBufferType
    }
}

extension ScreenRecorderClient: DependencyKey {
    public static var liveValue: ScreenRecorderClient {
        let client = Client()
        return ScreenRecorderClient(start: {
            await client.start()
        })
    }
}

extension DependencyValues {
    public var screenRecorderClient: ScreenRecorderClient {
        get { self[ScreenRecorderClient.self] }
        set { self[ScreenRecorderClient.self] = newValue }
    }
}

private actor Client {
    func start() -> AsyncThrowingStream<ScreenRecorderClient.Buffer, Error> {
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
