import Foundation
import ARKit
import AVFoundation
import Combine
import simd

struct TrackSample: Codable {
    let elapsedSeconds: Double
    let arTimestamp: Double
    let cameraToOrigin: [Float]
    let trackingState: String
    let fx: Float
    let fy: Float
    let cx: Float
    let cy: Float
    let imageWidth: Int
    let imageHeight: Int
}

struct TrackFile: Codable {
    let format: String
    let coordinateSystem: String
    let matrixLayout: String
    let originToARWorld: [Float]
    let samples: [TrackSample]
}

func flatten(_ m: simd_float4x4) -> [Float] {
    [m.columns.0.x,m.columns.0.y,m.columns.0.z,m.columns.0.w,
     m.columns.1.x,m.columns.1.y,m.columns.1.z,m.columns.1.w,
     m.columns.2.x,m.columns.2.y,m.columns.2.z,m.columns.2.w,
     m.columns.3.x,m.columns.3.y,m.columns.3.z,m.columns.3.w]
}

enum TrackingMode: Int, CaseIterable {
    case camera, tags, rigid
    var title: String {
        switch self { case .camera: return "Camera"; case .tags: return "Tags"; case .rigid: return "Rigid" }
    }
    var symbol: String {
        switch self { case .camera: return "video"; case .tags: return "viewfinder"; case .rigid: return "cube" }
    }
}

final class TrackingStore: ObservableObject {
    @Published private(set) var trackingMode: TrackingMode = .camera
    private var activeTrackingMode: TrackingMode = .camera // Access only on mctrack.frames.

    func cycleTrackingMode() {
        guard !recording else { return }
        let next = TrackingMode(rawValue: (trackingMode.rawValue + 1) % TrackingMode.allCases.count) ?? .camera
        trackingMode = next
        queue.async {
            self.activeTrackingMode = next
            // Clear previous mode's preview immediately, including when there are no detections.
            DispatchQueue.main.async { [weak self] in self?.onClearMarkers?() }
        }
        if next == .rigid { message = rigidReady ? "Rigid cube ready" : "Calibrate cube to begin" }
    }

    @Published private(set) var rigidCalibrating = false
    @Published private(set) var rigidReady = false
    @Published private(set) var rigidDetectedIDs = "None"
    @Published private(set) var rigidFaceCount = 0
    @Published private(set) var rigidConnectedCount = 0
    @Published var showRigidAxis = true
    @Published var rigidAxisLength: Double = 1.0
    @Published var rigidTagMillimeters: Double = 75
    @Published var rigidCubeMillimeters: Double = 90
    private let rigidTracking = RigidTracking()
    private var rigidSamples: [RigidSample] = []
    private var lastRigidPreview: simd_float4x4?
    var onRigidPose: ((simd_float4x4?) -> Void)?

    func startRigidCalibration() {
        guard !recording else { return }
        queue.async {
            self.tagTracking.tagSize = self.rigidTagMillimeters / 1000
            self.rigidTracking.tagSize = Float(self.rigidTagMillimeters / 1000)
            self.rigidTracking.cubeEdge = Float(self.rigidCubeMillimeters / 1000)
            self.rigidTracking.start()
            DispatchQueue.main.async {
                self.rigidCalibrating = true; self.rigidReady = false
                self.rigidDetectedIDs = "None"; self.rigidFaceCount = 0; self.rigidConnectedCount = 0; self.message = "Rotate cube; show adjacent faces together"
            }
        }
    }
    func finishRigidCalibration() {
        queue.async {
            let success = self.rigidTracking.finish()
            let ids = self.rigidTracking.observedIDs.map(String.init).joined(separator: ", ")
            DispatchQueue.main.async {
                self.rigidReady = success
                if success { self.rigidTagMillimeters = Double(self.rigidTracking.tagSize) * 1000 }
                self.rigidCalibrating = !success
                self.rigidDetectedIDs = ids
                self.message = success ? "Cube calibrated (\(self.rigidTracking.model.count) faces)" : "Need all five connected faces; keep rotating"
            }
        }
    }
    func updateRigidDimensions() {
        guard !recording else { return }
        rigidTagMillimeters = max(10, min(300, rigidTagMillimeters))
        rigidCubeMillimeters = max(20, min(500, rigidCubeMillimeters))
        let tag = Float(rigidTagMillimeters / 1000), edge = Float(rigidCubeMillimeters / 1000)
        queue.async {
            if abs(self.rigidTracking.tagSize - tag) > 0.00001 || abs(self.rigidTracking.cubeEdge - edge) > 0.00001 {
                self.rigidTracking.invalidate()
                self.rigidTracking.tagSize = tag
                self.rigidTracking.cubeEdge = edge
                DispatchQueue.main.async { self.rigidReady = false; self.rigidCalibrating = false; self.message = "Dimensions changed; recalibrate cube"; self.onRigidPose?(nil) }
            }
        }
    }

    @Published var recording = false
    @Published var saving = false
    @Published var resolution = 1080
    @Published var fps = 30
    @Published var supports4K = ARWorldTrackingConfiguration.supportedVideoFormats.contains {
        max(Int($0.imageResolution.width), Int($0.imageResolution.height)) >= 3840
    }

    func cycleFPS() {
        guard !recording else { return }
        let modes = resolution == 2160 ? [30, 24] : [30, 60, 24]
        guard let index = modes.firstIndex(of: fps) else { fps = 30; return }
        fps = modes[(index + 1) % modes.count]
    }

    func cycleResolution() {
        guard !recording, supports4K else { return }
        resolution = resolution == 1080 ? 2160 : 1080
        if resolution == 2160 && fps == 60 { fps = 30 }
    }
    @Published var hasOrigin = false
    @Published var canPlaceOrigin = false
    @Published var status = "Initializing tracking"
    @Published var message = "Scan a textured floor"
    @Published var takes: [URL] = []
    @Published var showTakes = false
    @Published var latestTake: URL?

    // All ARFrame work runs on the ARSession delegate serial queue.
    private let queue = DispatchQueue(label: "mctrack.frames")
    private var origin = matrix_identity_float4x4
    private var selectedOrigin = false
    private var samples: [TrackSample] = []
    private var startTimestamp: Double?
    private var lastTimestamp: Double = -1
    private var writer: TakeWriter?
    private var activeFolder: URL?
    private var lastStatus = ""
    private var activeTakeNumber = 0
    private let tagTracking = TagTracking()
    private var markerObservations: [MarkerObservation] = []
    // UI receives only the most recent scan. Never retain pixel buffers.
    var onMarkers: (([LiveMarker]) -> Void)?
    var onClearMarkers: (() -> Void)?

    let takesFolder: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("Takes", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    init() {
        rigidReady = rigidTracking.ready
        if rigidReady {
            rigidTagMillimeters = Double(rigidTracking.tagSize) * 1000
            rigidCubeMillimeters = Double(rigidTracking.cubeEdge) * 1000
            rigidDetectedIDs = rigidTracking.model.keys.sorted().map(String.init).joined(separator: ", ")
        }
        refreshTakes()
    }

    func refreshTakes() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: takesFolder, includingPropertiesForKeys: nil)) ?? []
        DispatchQueue.main.async { self.takes = urls.filter { $0.hasDirectoryPath }.sorted { $0.lastPathComponent > $1.lastPathComponent } }
    }

    func setOrigin(_ matrix: simd_float4x4) {
        queue.async {
            self.origin = matrix
            self.selectedOrigin = true
            DispatchQueue.main.async {
                self.hasOrigin = true
                self.message = "Origin set"
            }
        }
    }

    func resetOrigin() {
        queue.async {
            guard self.writer == nil else { return }
            self.selectedOrigin = false
            self.origin = matrix_identity_float4x4
            DispatchQueue.main.async { self.hasOrigin = false; self.message = "Tap to set origin" }
        }
    }

    func begin(rotation: Int = 90) {
        guard !recording, !saving else { return }
        let resolution = self.resolution, fps = self.fps
        recording = true
        queue.async {
            guard self.writer == nil else { return }
            let number = UserDefaults.standard.integer(forKey: "McTrackNextTakeNumber") + 1
            self.activeTakeNumber = number
            UserDefaults.standard.set(number, forKey: "McTrackNextTakeNumber")
            // A temporary name is used while recording; rename to completion time when saved.
            let folder = self.takesFolder.appendingPathComponent(String(format: "Recording_%03d_%@", number, Self.dateName()), isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let writer = try TakeWriter(url: folder.appendingPathComponent("video.mov"), resolution: resolution, fps: fps, rotation: rotation)
                self.writer = writer
                self.activeFolder = folder
                self.samples.removeAll(keepingCapacity: true)
                self.markerObservations.removeAll(keepingCapacity: true)
                self.rigidSamples.removeAll(keepingCapacity: true)
                self.startTimestamp = nil
                self.lastTimestamp = -1
                DispatchQueue.main.async { self.recording = true; self.message = "Recording" }
            } catch {
                DispatchQueue.main.async { self.recording = false; self.message = "Record error: \(error.localizedDescription)" }
            }
        }
    }

    func end() {
        guard recording, !saving else { return }
        saving = true
        queue.async {
            guard let writer = self.writer, let folder = self.activeFolder else { DispatchQueue.main.async { self.saving = false; self.recording = false }; return }
            self.writer = nil
            self.activeFolder = nil
            let samples = self.samples
            let markerSamples = self.markerObservations
            let rigidSamples = self.rigidSamples
            let rigidModel = self.rigidTracking
            let calibration = rigidModel.model.mapValues(flatten)
            let calibratedTagSize = Double(rigidModel.tagSize)
            let calibratedEdge = Double(rigidModel.calibratedEdge)
            let calibrationReady = rigidModel.ready
            let recordedMode = self.activeTrackingMode
            let origin = self.origin
            let originSelected = self.selectedOrigin
            let takeNumber = self.activeTakeNumber
            DispatchQueue.main.async { self.recording = false; self.message = "Saving take…" }
            writer.finish { result in
                do {
                    let track = TrackFile(format: "McTrack_v2", coordinateSystem: "Origin-local ARKit right-handed coordinates, meters; +Y up. Camera-to-origin transforms.", matrixLayout: "column-major", originToARWorld: flatten(origin), samples: samples)
                    let data = try JSONEncoder.pretty.encode(track)
                    try data.write(to: folder.appendingPathComponent("tracking.json"), options: .atomic)
                    let markerFile = MarkerFile(format: "McTrack_Markers_v1", family: "tagStandard41h12", tagSizeMeters: recordedMode == .rigid ? self.rigidTagMillimeters / 1000 : 0.0889, coordinateSystem: "origin-local ARKit right-handed meters, +Y up, column-major", observations: markerSamples)
                    try JSONEncoder.pretty.encode(markerFile).write(to: folder.appendingPathComponent("markers.json"), options: .atomic)
                    if recordedMode == .rigid {
                        let rigid = RigidFile(format: "McTrack_Rigid_v1", tagSizeMeters: calibratedTagSize,
                            cubeEdgeMeters: calibratedEdge, tagIDs: calibration.keys.sorted(),
                            samples: rigidSamples, calibrationStatus: calibrationReady ? "calibrated" : "incomplete", cubeFromTag: calibration)
                        try JSONEncoder.pretty.encode(rigid).write(to: folder.appendingPathComponent("rigid.json"), options: .atomic)
                    }
                    try JSONEncoder.pretty.encode(writer.writtenVideoTimestamps).write(to: folder.appendingPathComponent("video_timestamps.json"), options: .atomic)
                    let metadata: [String: Any] = ["appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.2", "appBuild": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "122", "exportSchemaVersion": 3, "markerCornerConvention": "AprilTag native order, sensor pixels, top-left origin", "videoTransform": "clockwise \(writer.rotation) degrees, aspect fill, center crop", "videoTimestamps": "video_timestamps.json", "video": "video.mov", "tracking": "tracking.json", "markers": "markers.json", "trackingMode": recordedMode.title, "sampleCount": samples.count, "videoOrientation": writer.rotation % 180 == 0 ? "landscape" : "portrait", "originSelected": originSelected, "videoRotationDegrees": writer.rotation, "videoPixelSize": [writer.width, writer.height], "videoFPS": writer.fps, "rigidAxisLength": self.rigidAxisLength, "audioRequested": true, "audioStatus": writer.audioStatus, "lensSource": "ARKit camera intrinsics (pixel units)", "stabilization": "No explicit AVFoundation stabilization enabled; source ARKit capturedImage", "captureClock": "ARFrame.timestamp", "trackingUnits": "meters"]
                    let meta = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
                    try meta.write(to: folder.appendingPathComponent("metadata.json"), options: .atomic)
                    let finalName = String(format: "Take_%03d_%@", takeNumber, Self.friendlyDateName())
                    var finalFolder = self.takesFolder.appendingPathComponent(finalName, isDirectory: true)
                    if FileManager.default.fileExists(atPath: finalFolder.path) {
                        finalFolder = self.takesFolder.appendingPathComponent(finalName + "_" + UUID().uuidString.prefix(6), isDirectory: true)
                    }
                    try FileManager.default.moveItem(at: folder, to: finalFolder)
                    DispatchQueue.main.async {
                        self.saving = false
                        self.latestTake = finalFolder
                        self.message = result == nil ? "Take saved" : "Saved with video warning"
                        self.refreshTakes()
                    }
                } catch {
                    DispatchQueue.main.async { self.saving = false; self.message = "Save error: \(error.localizedDescription)" }
                }
            }
        }
    }

    func process(_ frame: ARFrame) {
        queue.async {
            let state: String
            switch frame.camera.trackingState {
            case .normal: state = "Tracking normal"
            case .notAvailable: state = "Tracking unavailable"
            case .limited: state = "Tracking limited"
            }
            if state != self.lastStatus {
                self.lastStatus = state
                DispatchQueue.main.async { self.status = state }
            }
            // Detection runs even when not recording, allowing live marker previews.
            if self.activeTrackingMode == .tags || self.activeTrackingMode == .rigid {
                self.tagTracking.tagSize = self.activeTrackingMode == .rigid ? Double(self.rigidTracking.tagSize) : 0.0889
                let elapsed = self.writer != nil ? self.startTimestamp.map { frame.timestamp - $0 } : nil
                if let (live, observations) = self.tagTracking.detect(frame: frame, origin: self.origin, elapsed: elapsed) {
                if self.writer != nil { self.markerObservations.append(contentsOf: observations) }
                if self.activeTrackingMode == .rigid {
                    self.rigidTracking.updateCalibration(live)
                    if self.rigidTracking.calibrating {
                        let ids = self.rigidTracking.observedIDs.map(String.init).joined(separator: ", ")
                        let faceCount = self.rigidTracking.observedIDs.count
                        let connected = self.rigidTracking.connectedCount
                        DispatchQueue.main.async {
                            self.rigidDetectedIDs = ids.isEmpty ? "None" : ids
                            self.rigidFaceCount = faceCount
                            self.rigidConnectedCount = connected
                            if faceCount >= 5 && connected < faceCount {
                                self.message = "Show adjacent faces together to connect calibration"
                            }
                        }
                        if self.rigidTracking.canFinish {
                            let success = self.rigidTracking.finish()
                            if success {
                                DispatchQueue.main.async {
                                    self.rigidTagMillimeters = Double(self.rigidTracking.tagSize) * 1000
                                    self.rigidReady = true; self.rigidCalibrating = false
                                    self.message = "Cube calibrated automatically (5 faces)"
                                }
                            }
                        }
                    }
                    if abs(self.tagTracking.tagSize - Double(self.rigidTracking.tagSize)) < 0.000001, let estimate = self.rigidTracking.estimate(live) {
                        self.lastRigidPreview = estimate.0
                        if self.writer != nil, let elapsed {
                            self.rigidSamples.append(RigidSample(elapsedSeconds: elapsed,
                                arTimestamp: frame.timestamp, rigidToOrigin: flatten(simd_inverse(self.origin) * estimate.0),
                                visibleTagIDs: estimate.1))
                        }
                        DispatchQueue.main.async { [weak self] in self?.onRigidPose?(estimate.0) }
                    }
                }
                // Empty scans also update the UI, so stale gizmos can be hidden.
                DispatchQueue.main.async { [weak self] in self?.onMarkers?(live) }
                }
            }
            guard let writer = self.writer else { return }
            guard frame.timestamp > self.lastTimestamp else { return }
            self.lastTimestamp = frame.timestamp
            if self.startTimestamp == nil { self.startTimestamp = frame.timestamp }
            guard let start = self.startTimestamp else { return }
            let camera = frame.camera
            let k = camera.intrinsics
            let resolution = camera.imageResolution
            let local = simd_inverse(self.origin) * camera.transform
            self.samples.append(TrackSample(elapsedSeconds: frame.timestamp - start, arTimestamp: frame.timestamp, cameraToOrigin: flatten(local), trackingState: state, fx: k.columns.0.x, fy: k.columns.1.y, cx: k.columns.2.x, cy: k.columns.2.y, imageWidth: Int(resolution.width), imageHeight: Int(resolution.height)))
            writer.appendVideo(frame.capturedImage, arTimestamp: frame.timestamp)
        }
    }

    private static func friendlyDateName() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd-yy_hh-mm-a"
        return f.string(from: Date())
    }

    private static func dateName() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss_SSS"; return f.string(from: Date())
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }
}
