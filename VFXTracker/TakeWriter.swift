import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import ImageIO

// AVAssetWriter receives ARKit camera buffers and microphone CMSampleBuffers.
// Both clocks are host-time based. Audio samples are retimed to the first ARFrame.
final class TakeWriter: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var audioInput: AVAssetWriterInput?
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let audioSession = AVCaptureSession()
    private let audioQueue = DispatchQueue(label: "mctrack.audio")
    private let lock = NSLock()
    private var started = false
    private var firstTimestamp: Double?
    private var previousVideo: Double = -1
    private(set) var writtenVideoTimestamps: [Double] = []
    private var audioCount = 0
    private var finishing = false
    let resolution: Int
    let fps: Int
    let rotation: Int
    let width: Int
    let height: Int
    private(set) var audioStatus = "not initialized"

    init(url: URL, resolution: Int = 1080, fps: Int = 30, rotation: Int = 90) throws {
        self.resolution = resolution
        self.fps = fps
        self.rotation = rotation
        let long = resolution == 2160 ? 3840 : 1920
        let width = rotation % 180 == 0 ? long : resolution
        let height = rotation % 180 == 0 ? resolution : long
        self.width = width
        self.height = height
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: resolution == 2160 ? 35_000_000 : 10_000_000]
        ])
        videoInput.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        super.init()
        writer.add(videoInput)
        configureAudio()
    }

    private func configureAudio() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            audioStatus = "Microphone permission not granted. Video only."
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            return
        }
        guard let device = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device),
              audioSession.canAddInput(input) else { audioStatus = "No microphone input"; return }
        audioSession.addInput(input)
        let output = AVCaptureAudioDataOutput()
        guard audioSession.canAddOutput(output) else { audioStatus = "Cannot add microphone output"; return }
        audioSession.addOutput(output)
        output.setSampleBufferDelegate(self, queue: audioQueue)
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96000
        ])
        audio.expectsMediaDataInRealTime = true
        if writer.canAdd(audio) { writer.add(audio); audioInput = audio; audioStatus = "microphone enabled" }
        else { audioStatus = "Audio writer unavailable" }
        audioQueue.async { self.audioSession.startRunning() }
    }

    func appendVideo(_ buffer: CVPixelBuffer, arTimestamp: Double) {
        lock.lock(); defer { lock.unlock() }
        if !started {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: CMTime(seconds: arTimestamp, preferredTimescale: 1_000_000))
            firstTimestamp = arTimestamp
            started = true
        }
        // Keep all ARKit pose samples; only write video frames at the chosen output rate.
        guard previousVideo < 0 || arTimestamp - previousVideo >= (1.0 / Double(fps) - 0.002) else { return }
        guard writer.status == .writing, videoInput.isReadyForMoreMediaData, arTimestamp > previousVideo,
              let pool = adaptor.pixelBufferPool else { return }
        var destination: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &destination) == kCVReturnSuccess,
              let output = destination else { return }
        let source = CIImage(cvPixelBuffer: buffer)
        // ARKit's captured image is landscape sensor data. Rotate actual pixels into portrait.
        let rotated = source.oriented(rotation == 90 ? .right : rotation == 180 ? .down : rotation == 270 ? .left : .up)
        let extent = rotated.extent
        let scale = max(CGFloat(width) / extent.width, CGFloat(height) / extent.height)
        let scaled = rotated.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let x = (scaled.extent.width - CGFloat(width)) / 2 + scaled.extent.minX
        let y = (scaled.extent.height - CGFloat(height)) / 2 + scaled.extent.minY
        let cropped = scaled.cropped(to: CGRect(x: x, y: y, width: CGFloat(width), height: CGFloat(height)))
            .transformed(by: CGAffineTransform(translationX: -x, y: -y))
        context.render(cropped, to: output)
        if adaptor.append(output, withPresentationTime: CMTime(seconds: arTimestamp, preferredTimescale: 1_000_000)) {
            previousVideo = arTimestamp
            writtenVideoTimestamps.append(arTimestamp)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.lock(); defer { lock.unlock() }
        guard started, !finishing, writer.status == .writing, let audioInput = audioInput, audioInput.isReadyForMoreMediaData else { return }
        // AVCaptureAudioDataOutput PTS and ARFrame.timestamp both use the device host clock.
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts.isValid, pts.seconds >= (firstTimestamp ?? Double.infinity) else { return }
        if audioInput.append(sampleBuffer) { audioCount += 1 }
    }

    func finish(_ completion: @escaping (Error?) -> Void) {
        audioQueue.async { if self.audioSession.isRunning { self.audioSession.stopRunning() } }
        lock.lock()
        finishing = true
        let didStart = started
        if didStart {
            videoInput.markAsFinished()
            audioInput?.markAsFinished()
            if audioCount == 0 { audioStatus = "No audio samples captured" }
        }
        lock.unlock()
        guard didStart else { completion(NSError(domain: "McTrack", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video frames captured"])); return }
        writer.finishWriting { completion(self.writer.error) }
    }
}
