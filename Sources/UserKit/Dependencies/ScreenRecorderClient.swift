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
    public var start: @Sendable () async -> AsyncThrowingStream<Buffer, Error> = {  .finished() }
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
    let recorder = RPScreenRecorder.shared()
        
    func start() -> AsyncThrowingStream<ScreenRecorderClient.Buffer, Error> {
        AsyncThrowingStream { continuation in
            recorder.isMicrophoneEnabled = false
            recorder.isCameraEnabled = false
            recorder.startCapture { sampleBuffer, bufferType, error in
                guard error == nil else {
                    continuation.finish(throwing: error)
                    return
                }
                
                if bufferType == .video {
                    continuation.yield(ScreenRecorderClient.Buffer(sampleBuffer: sampleBuffer, bufferType: bufferType))
                }
            } completionHandler: { error in
                guard error == nil else {
                    continuation.finish(throwing: error)
                    return
                }
            }
        }
    }
}
