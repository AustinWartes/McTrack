import Foundation
import AVFoundation
import CoreImage
import CoreVideo

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
    private var audioCount = 0
    private var finishing = false
    private(set) var audioStatus = "not initialized"

    init(url: URL) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1080,
            AVVideoHeightKey: 1920,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 10_000_000]
        ])
        videoInput.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1080,
            kCVPixelBufferHeightKey as String: 1920,
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
        guard writer.status == .writing, videoInput.isReadyForMoreMediaData, arTimestamp > previousVideo,
              let pool = adaptor.pixelBufferPool else { return }
        var destination: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &destination) == kCVReturnSuccess,
              let output = destination else { return }
        let source = CIImage(cvPixelBuffer: buffer)
        // ARKit's captured image is landscape sensor data. Rotate actual pixels into portrait.
        let rotated = source.oriented(.right)
        let extent = rotated.extent
        let scale = max(1080 / extent.width, 1920 / extent.height)
        let scaled = rotated.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let x = (scaled.extent.width - 1080) / 2 + scaled.extent.minX
        let y = (scaled.extent.height - 1920) / 2 + scaled.extent.minY
        let cropped = scaled.cropped(to: CGRect(x: x, y: y, width: 1080, height: 1920))
            .transformed(by: CGAffineTransform(translationX: -x, y: -y))
        context.render(cropped, to: output)
        if adaptor.append(output, withPresentationTime: CMTime(seconds: arTimestamp, preferredTimescale: 1_000_000)) {
            previousVideo = arTimestamp
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
