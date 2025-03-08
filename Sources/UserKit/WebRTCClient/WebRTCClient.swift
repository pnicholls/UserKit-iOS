//
//  WebRTCClient.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

//
//  WebRTCClient.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import WebRTC

actor WebRTCClient {
    private var peerConnection: RTCPeerConnection?
    private var peerConnectionDelegate: PeerConnectionDelegate?
    private var videoSource: RTCVideoSource?
    private var videoCapturer: RTCVideoCapturer?
    private var screenShareSource: RTCVideoSource?
    private var screenShareCapturer: RTCVideoCapturer?
    private var localTransceiversMap: [String: RTCRtpTransceiver] = [:]
    
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()
    
    struct PeerConnectionInitFailed: Error {}
    
    struct SessionDescription {
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
    
    func close() async {
        peerConnection?.close()
    }
    
    func configure() async throws -> RTCPeerConnection {
        let config = RTCConfiguration()
        config.bundlePolicy = .maxBundle
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.cloudflare.com:3478"])]
        
        // Unified plan is more superior than planB
        config.sdpSemantics = .unifiedPlan
        
        // gatherContinually will let WebRTC to listen to any network changes and send any new candidates to the other client
        config.continualGatheringPolicy = .gatherContinually
        
        // Define media constraints. DtlsSrtpKeyAgreement is required to be true to be able to connect with web browsers.
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                             optionalConstraints: ["DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue])
        
        guard let peerConnection = WebRTCClient.factory.peerConnection(with: config, constraints: constraints, delegate: nil) else {
            throw PeerConnectionInitFailed()
        }
        
        self.peerConnection = peerConnection
        
        peerConnectionDelegate = PeerConnectionDelegate()
        self.peerConnection?.delegate = peerConnectionDelegate
                
        addAudioTrack()
        addVideoTrack()
        addScreenShareTrack()
        
        return peerConnection
    }
    
    private func addAudioTrack() {
        let audioConstrains = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = WebRTCClient.factory.audioSource(with: audioConstrains)
        
        let audioTrack = WebRTCClient.factory.audioTrack(with: audioSource, trackId: UUID().uuidString)
        
        let transceiverInit = RTCRtpTransceiverInit()
        transceiverInit.direction = .sendOnly
        
        localTransceiversMap["audio"] = self.peerConnection?.addTransceiver(with: audioTrack, init: transceiverInit)
    }
    
    private func addVideoTrack() {
        self.videoSource = WebRTCClient.factory.videoSource()
        let videoTrack = WebRTCClient.factory.videoTrack(with: videoSource!, trackId: UUID().uuidString)
        self.videoCapturer = RTCVideoCapturer(delegate: videoSource!)
        
        let transceiverInit = RTCRtpTransceiverInit()
        transceiverInit.direction = .sendOnly
        
        guard let transceiver = self.peerConnection?.addTransceiver(with: videoTrack, init: transceiverInit) else {
            return
        }
        
        localTransceiversMap["video"] = transceiver
        
        let parameters = transceiver.sender.parameters
        
        if let encoding = parameters.encodings.first {
            encoding.maxBitrateBps = NSNumber(value: 8_000_000)
            encoding.minBitrateBps = NSNumber(value: 3_000_000)
            encoding.maxFramerate = NSNumber(value: 60)
            encoding.scaleResolutionDownBy = NSNumber(value: 1.0)
            parameters.encodings = [encoding]
            transceiver.sender.parameters = parameters
        }
    }
    
    private func addScreenShareTrack() {
        self.screenShareSource = WebRTCClient.factory.videoSource()
        let screenShareTrack = WebRTCClient.factory.videoTrack(with: screenShareSource!, trackId: UUID().uuidString)
        self.screenShareCapturer = RTCVideoCapturer(delegate: screenShareSource!)
        
        let transceiverInit = RTCRtpTransceiverInit()
        transceiverInit.direction = .sendOnly
        
        guard let transceiver = self.peerConnection?.addTransceiver(with: screenShareTrack, init: transceiverInit) else {
            return
        }
        
        localTransceiversMap["screenShare"] = transceiver
        
        let parameters = transceiver.sender.parameters
        
        if let encoding = parameters.encodings.first {
            encoding.maxBitrateBps = NSNumber(value: 8_000_000)
            encoding.minBitrateBps = NSNumber(value: 3_000_000)
            encoding.maxFramerate = NSNumber(value: 60)
            encoding.scaleResolutionDownBy = NSNumber(value: 1.0)
            parameters.encodings = [encoding]
            transceiver.sender.parameters = parameters
        }
    }
    
    func createOffer() async throws -> SessionDescription {
        guard let peerConnection = peerConnection else {
            struct NoPeerConnectionError: Error {}
            throw NoPeerConnectionError()
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                                 optionalConstraints: nil)
            peerConnection.offer(for: constraints) { (sdp, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let sdp = sdp else {
                    struct NoSdpError: Error {}
                    continuation.resume(throwing: NoSdpError())
                    return
                }
                
                continuation.resume(returning: .init(from: sdp))
            }
        }
    }
    
    func createAnswer() async throws -> SessionDescription {
        guard let peerConnection = peerConnection else {
            struct NoPeerConnectionError: Error {}
            throw NoPeerConnectionError()
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                                 optionalConstraints: nil)
            peerConnection.answer(for: constraints) { (sdp, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let sdp = sdp else {
                    struct NoSdpError: Error {}
                    continuation.resume(throwing: NoSdpError())
                    return
                }
                
                continuation.resume(returning: .init(from: sdp))
            }
        }
    }
    
    func setLocalDescription(_ sessionDescription: SessionDescription) async throws -> SessionDescription {
        guard let peerConnection = peerConnection else {
            struct NoPeerConnectionError: Error {}
            throw NoPeerConnectionError()
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            peerConnection.setLocalDescription(sessionDescription.rtcSessionDescription) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                continuation.resume(returning: sessionDescription)
            }
        }
    }
    
    func localDescription() -> SessionDescription? {
        guard let localDescription = peerConnection?.localDescription else {
            return nil
        }
        
        return SessionDescription(from: localDescription)
    }
    
    func transceivers() -> [RTCRtpTransceiver] {
        guard let peerConnection = peerConnection else {
            return []
        }
                    
        return peerConnection.transceivers
    }
    
    // Function that returns the stored local transceivers map
    func getLocalTransceivers() -> [String: RTCRtpTransceiver] {
        return localTransceiversMap
    }
    
    func setRemoteDescription(_ sessionDescription: SessionDescription) async throws -> SessionDescription {
        guard let peerConnection = peerConnection else {
            struct NoPeerConnectionError: Error {}
            throw NoPeerConnectionError()
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            peerConnection.setRemoteDescription(sessionDescription.rtcSessionDescription) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                continuation.resume(returning: sessionDescription)
            }
        }
    }
    
    func handleVideoSourceBuffer(sampleBuffer: CMSampleBuffer) async {
        if (CMSampleBufferGetNumSamples(sampleBuffer) != 1 || !CMSampleBufferIsValid(sampleBuffer) ||
            !CMSampleBufferDataIsReady(sampleBuffer)) {
            return
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Use the actual dimensions from the buffer
        videoSource!.adaptOutputFormat(toWidth: Int32(width), height: Int32(height), fps: 60)
        
        let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let timeStampNs = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * Float64(NSEC_PER_SEC)
        let videoFrame = RTCVideoFrame(buffer: rtcPixelBuffer,
                                      rotation: RTCVideoRotation._90,
                                      timeStampNs: Int64(timeStampNs))
        
        videoSource!.capturer(videoCapturer!, didCapture: videoFrame)
    }
    
    func handleScreenShareSourceBuffer(sampleBuffer: CMSampleBuffer) async {
        if (CMSampleBufferGetNumSamples(sampleBuffer) != 1 || !CMSampleBufferIsValid(sampleBuffer) ||
            !CMSampleBufferDataIsReady(sampleBuffer)) {
            return
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Use the actual dimensions from the buffer
        screenShareSource!.adaptOutputFormat(toWidth: Int32(width), height: Int32(height), fps: 60)
        
        let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let timeStampNs = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * Float64(NSEC_PER_SEC)
        let videoFrame = RTCVideoFrame(buffer: rtcPixelBuffer,
                                      rotation: RTCVideoRotation._0,  // Keep original orientation
                                      timeStampNs: Int64(timeStampNs))
        
        screenShareSource!.capturer(screenShareCapturer!, didCapture: videoFrame)
    }
}

class PeerConnectionDelegate: NSObject, RTCPeerConnectionDelegate {
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
