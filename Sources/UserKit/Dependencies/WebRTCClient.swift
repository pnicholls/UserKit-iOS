//
//  File.swift
//  
//
//  Created by Peter Nicholls on 10/9/2024.
//

import Foundation
import Dependencies
import DependenciesMacros
import WebRTC

public struct WebRTCClient {
    public var configure: @Sendable () async -> ()
    public var answer: @Sendable () async -> AsyncThrowingStream<SessionDescription, Error> = {  .finished() }
    public var offer: @Sendable () async -> AsyncThrowingStream<SessionDescription, Error> = {  .finished() }
    public var setLocalDescription: @Sendable (_ sessionDescription: SessionDescription) async -> AsyncThrowingStream<SessionDescription, Error> = { _ in .finished() }
    public var localDescription: @Sendable () async -> SessionDescription
    public var transceivers: @Sendable () async -> [RTCRtpTransceiver]
    public var setRemoteDescription: @Sendable (_ sessionDescription: SessionDescription) async -> AsyncThrowingStream<SessionDescription, Error> = { _ in .finished() }
    public var handleSourceBuffer: @Sendable (_ sampleBuffer: CMSampleBuffer) async -> ()
}

extension WebRTCClient {
    public struct Transceiver {
        public let location: String
        public let mid: String
        public let trackName: String?
    }
    
    enum SdpType: String, Codable {
        case offer, prAnswer, answer, rollback
        
        var rtcSdpType: RTCSdpType {
            switch self {
            case .offer:    return .offer
            case .answer:   return .answer
            case .prAnswer: return .prAnswer
            case .rollback: return .rollback
            }
        }
    }
    
    public struct SessionDescription {
        let sdp: String
        let type: SdpType
        
        init(sdp: String, type: SdpType) {
            self.sdp = sdp
            self.type = type
        }
        
        init(from rtcSessionDescription: RTCSessionDescription) {
            self.sdp = rtcSessionDescription.sdp
            
            switch rtcSessionDescription.type {
            case .offer:    self.type = .offer
            case .prAnswer: self.type = .prAnswer
            case .answer:   self.type = .answer
            case .rollback: self.type = .rollback
            @unknown default:
                fatalError("Unknown RTCSessionDescription type: \(rtcSessionDescription.type.rawValue)")
            }
        }
        
        var rtcSessionDescription: RTCSessionDescription {
            return RTCSessionDescription(type: self.type.rtcSdpType, sdp: self.sdp)
        }
    }
}

extension WebRTCClient: DependencyKey {
    
    public static var liveValue: WebRTCClient {
        let client = Client()
        return WebRTCClient(configure: {
            await client.configure()
        }, answer: {
            await client.answer()
        }, offer: {
            await client.offer()
        }, setLocalDescription: { sessionDescription in
            await client.setLocalDescription(sessionDescription: sessionDescription)
        }, localDescription: {
            await client.localDescription()
        }, transceivers: {
            await client.transceivers()
        }, setRemoteDescription: { sessionDescription in
            await client.setRemoteDescription(sessionDescription: sessionDescription)
        }, handleSourceBuffer: { sampleBuffer in
            await client.handleSourceBuffer(sampleBuffer: sampleBuffer)
        })
    }
    
}

extension DependencyValues {
    
    public var webRTCClient: WebRTCClient {
        get { self[WebRTCClient.self] }
        set { self[WebRTCClient.self] = newValue }
    }
    
}

private actor Client: NSObject {
    var peerConnection: RTCPeerConnection?
    var peerConnectionDelegate: PeerConnectionDelegate?
    var videoSource: RTCVideoSource?
    var videoCapturer: RTCVideoCapturer?
    private let mediaConstrains = [kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                                   kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue]
    
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()
    
    func configure() async {
        let config = RTCConfiguration()
        config.bundlePolicy = .maxBundle
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.cloudflare.com:3478"])]
        
        // Unified plan is more superior than planB
        config.sdpSemantics = .unifiedPlan
        
        // gatherContinually will let WebRTC to listen to any network changes and send any new candidates to the other client
        config.continualGatheringPolicy = .gatherContinually
        
        // Define media constraints. DtlsSrtpKeyAgreement is required to be true to be able to connect with web browsers.
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                              optionalConstraints: ["DtlsSrtpKeyAgreement":kRTCMediaConstraintsValueTrue])
        
        guard let peerConnection = Client.factory.peerConnection(with: config, constraints: constraints, delegate: nil) else {
            fatalError("Could not create new RTCPeerConnection")
        }
        
        self.peerConnection = peerConnection
        
        peerConnectionDelegate = PeerConnectionDelegate()
        self.peerConnection?.delegate = peerConnectionDelegate
        
        addAudioTrack()
        addVideoTrack()
    }
    
    func addAudioTrack() {
        let audioConstrains = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = Client.factory.audioSource(with: audioConstrains)
        let audioTrack = Client.factory.audioTrack(with: audioSource, trackId: "audio0")
        self.peerConnection?.addTransceiver(with: audioTrack)
    }
    
    func addVideoTrack() {
        self.videoSource = Client.factory.videoSource()
        let videoTrack = Client.factory.videoTrack(with: videoSource!, trackId: "videoSourceTrackId")
        self.videoCapturer = RTCVideoCapturer(delegate: videoSource!)
        let transceiver = self.peerConnection?.addTransceiver(with: videoTrack)
    }
    
    func offer() -> AsyncThrowingStream<WebRTCClient.SessionDescription, Error> {
        AsyncThrowingStream { continuation in
            guard let peerConnection = peerConnection else {
                struct NoPeerConnectionError: Error {}
                return continuation.finish(throwing: NoPeerConnectionError())
            }
            
            let constrains = RTCMediaConstraints(mandatoryConstraints: self.mediaConstrains,
                                                 optionalConstraints: nil)
            peerConnection.offer(for: constrains) { (sdp, error) in
                guard error == nil else {
                    return continuation.finish(throwing: error)
                }
                
                guard let sdp = sdp else {
                    struct NoSdpError: Error {}
                    return continuation.finish(throwing: NoSdpError())
                }
                
                continuation.yield(.init(from: sdp))
                continuation.finish()
            }
        }
    }
    
    func answer() -> AsyncThrowingStream<WebRTCClient.SessionDescription, Error> {
        AsyncThrowingStream { continuation in
            guard let peerConnection = peerConnection else {
                struct NoPeerConnectionError: Error {}
                return continuation.finish(throwing: NoPeerConnectionError())
            }
            
            let constrains = RTCMediaConstraints(mandatoryConstraints: self.mediaConstrains,
                                                 optionalConstraints: nil)
            peerConnection.answer(for: constrains) { (sdp, error) in
                guard error == nil else {
                    return continuation.finish(throwing: error)
                }
                
                guard let sdp = sdp else {
                    struct NoSdpError: Error {}
                    return continuation.finish(throwing: NoSdpError())
                }
                
                continuation.yield(.init(from: sdp))
                continuation.finish()
            }
        }
    }
    
    func setLocalDescription(sessionDescription: WebRTCClient.SessionDescription) -> AsyncThrowingStream<WebRTCClient.SessionDescription, Error> {
        AsyncThrowingStream { continuation in
            guard let peerConnection = peerConnection else {
                struct NoPeerConnectionError: Error {}
                return continuation.finish(throwing: NoPeerConnectionError())
            }
            
            peerConnection.setLocalDescription(sessionDescription.rtcSessionDescription) { error in
                guard error == nil else {
                    return continuation.finish(throwing: error)
                }
                
                continuation.yield(sessionDescription)
                continuation.finish()
            }
        }
    }
    
    func localDescription() -> WebRTCClient.SessionDescription {
        guard let localDescription = peerConnection?.localDescription else {
            fatalError()
        }
        
        return WebRTCClient.SessionDescription.init(from: localDescription)
    }
    
    func transceivers() -> [RTCRtpTransceiver] {
        guard let peerConnection = peerConnection else {
            fatalError()
        }
            
//        let videoTrack = peerConnection.transceivers.first { $0.mediaType == .video }?.receiver.track as? RTCVideoTrack
//        print(videoTrack)
        
        return peerConnection.transceivers
    }
    
    func setRemoteDescription(sessionDescription: WebRTCClient.SessionDescription) -> AsyncThrowingStream<WebRTCClient.SessionDescription, Error> {
        AsyncThrowingStream { continuation in
            guard let peerConnection = peerConnection else {
                struct NoPeerConnectionError: Error {}
                return continuation.finish(throwing: NoPeerConnectionError())
            }
            
            peerConnection.setRemoteDescription(sessionDescription.rtcSessionDescription) { error in
                guard error == nil else {
                    return continuation.finish(throwing: error)
                }
                
                continuation.yield(sessionDescription)
                continuation.finish()
            }
        }
    }
    
    func handleSourceBuffer(sampleBuffer: CMSampleBuffer) async {
        if (CMSampleBufferGetNumSamples(sampleBuffer) != 1 || !CMSampleBufferIsValid(sampleBuffer) ||
            !CMSampleBufferDataIsReady(sampleBuffer)) {
            return;
        }
        
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (pixelBuffer == nil) {
            return;
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer!);
        let height = CVPixelBufferGetHeight(pixelBuffer!);
        
        print(width, height)
        
        videoSource!.adaptOutputFormat(toWidth: Int32(width), height: Int32(height), fps: 30)
        
        let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer!)
        let timeStampNs =
            CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * Float64(NSEC_PER_SEC)
        let videoFrame =  RTCVideoFrame(buffer: rtcPixelBuffer, rotation: RTCVideoRotation._0, timeStampNs: Int64(timeStampNs))
        
        videoSource!.capturer(videoCapturer!, didCapture: videoFrame)
    }
}

final class PeerConnectionDelegate: NSObject, RTCPeerConnectionDelegate  {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("peerConnection new signaling state: \(stateChanged)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        print("peerConnection new peer connection state: \(newState)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("peerConnection did add stream")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("peerConnection did remove stream")
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("peerConnection should negotiate")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("peerConnection new connection state: \(newState)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("peerConnection new gathering state: \(newState)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("didGenerate candidate")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("peerConnection did remove candidate(s)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("peerConnection did open data channel")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        print("peerConnection didStartReceivingOn ", transceiver.receiver.track?.trackId)
    }
}
