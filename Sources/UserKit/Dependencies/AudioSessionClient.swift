//
//  File.swift
//  
//
//  Created by Peter Nicholls on 16/9/2024.
//

import AVKit
import Dependencies
import DependenciesMacros

public struct AudioSessionClient {
    public var configure: @Sendable () async -> ()
    public var addNotificationObservers: @Sendable () async -> ()
    public var removeNotificationObservers: @Sendable () async -> ()
}

extension AudioSessionClient: DependencyKey {
    public static var liveValue: AudioSessionClient {
        let client = Client()
        
        return AudioSessionClient(configure: {
            await client.configure()
        }, addNotificationObservers: {
            await client.addNotificationObservers()
        }, removeNotificationObservers: {
            await client.removeNotificationObservers()
        })
    }
}

extension DependencyValues {
    public var audioSessionClient: AudioSessionClient {
        get { self[AudioSessionClient.self] }
        set { self[AudioSessionClient.self] = newValue }
    }
}

private actor Client {
    let audioSession = AVAudioSession.sharedInstance()

    func configure() -> () {
        do {
            try audioSession.setCategory(.playAndRecord, options: [
                .defaultToSpeaker,
                .allowBluetooth,
            ])
            try audioSession.setActive(true)
            try audioSession.overrideOutputAudioPort(.speaker)
            
            print("Audio session initialized successfully")
        } catch {
            assertionFailure("Error configuring audio session: \(error)")
        }
    }
    
    func addNotificationObservers() -> () {
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { notification in
            do {
                try self.audioSession.overrideOutputAudioPort(.speaker)
            } catch {
                assertionFailure("Failed to force audio to speaker: \(error)")
            }
        }
    }
    
    func removeNotificationObservers() -> () {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
    }
}
