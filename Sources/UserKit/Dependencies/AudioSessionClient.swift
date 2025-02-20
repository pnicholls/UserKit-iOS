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
    public var configure: @Sendable () async -> Void
    public var addNotificationObservers: @Sendable () async -> Void
    public var removeNotificationObservers: @Sendable () async -> Void
}

extension AudioSessionClient: DependencyKey {
    public static var liveValue: AudioSessionClient {
        let client = Client()
        return AudioSessionClient(
            configure: { await client.configure() },
            addNotificationObservers: { await client.addNotificationObservers() },
            removeNotificationObservers: { await client.removeNotificationObservers() }
        )
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
    private var observer: NSObjectProtocol?

    func configure() {
        do {
            try audioSession.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
            print("Audio session configured: category=\(audioSession.category), outputs=\(audioSession.currentRoute.outputs)")
        } catch {
            print("Error configuring audio session: \(error)") // Use print instead of assertionFailure for better runtime feedback
        }
    }
    
    func addNotificationObservers() {
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] notification in
            guard let self, let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
            
            let currentOutputs = audioSession.currentRoute.outputs
            print("Route changed: reason=\(reason), outputs=\(currentOutputs)")
            
            // Only force Speaker if no external devices (e.g., Bluetooth) are preferred
            if reason == .oldDeviceUnavailable || currentOutputs.contains(where: { $0.portType == .builtInReceiver }) {
                do {
                    try audioSession.overrideOutputAudioPort(.speaker)
                    print("Forced output to Speaker")
                } catch {
                    print("Failed to force Speaker: \(error)")
                }
            }
        }
    }
    
    func removeNotificationObservers() {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }
}
