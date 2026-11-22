import SwiftUI
import ARKit
import SceneKit
import simd
import UIKit

struct ARCameraView: UIViewRepresentable {
    @ObservedObject var store: TrackingStore
    @Binding var coordinatorRef: Coordinator?

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.scene = SCNScene()
        view.delegate = context.coordinator
        view.session.delegate = context.coordinator
        view.automaticallyUpdatesLighting = false
        view.autoenablesDefaultLighting = false
        view.rendersContinuously = true
        view.contentMode = .scaleAspectFill
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal]
        context.coordinator.applyVideoFormat(to: configuration)
        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        context.coordinator.setup(in: view)
        DispatchQueue.main.async { self.coordinatorRef = context.coordinator }
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {
        context.coordinator.updateFormatIfNeeded()
    }

    static func dismantleUIView(_ view: ARSCNView, coordinator: Coordinator) {
        view.session.pause()
    }

    final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        private let store: TrackingStore
        private weak var view: ARSCNView?
        private let reticle = SCNNode()
        private let gizmo = SCNNode()
        private let groundGrid = SCNNode()
        private var markerNodes: [Int: SCNNode] = [:]
        private var lastMarkerSeen: [Int: TimeInterval] = [:]
        private var gridMaterial: SCNMaterial?
        private var gridOrigin: simd_float4x4?
        private var lastRaycast: TimeInterval = 0
        private var currentPlacement: simd_float4x4?
        private var placed = false
        private var configuredResolution = 1080

        func applyVideoFormat(to configuration: ARWorldTrackingConfiguration) {
            let target = store.resolution
            let formats = ARWorldTrackingConfiguration.supportedVideoFormats
            let matches = formats.filter { format in
                let width = Int(format.imageResolution.width)
                let height = Int(format.imageResolution.height)
                let longSide = max(width, height)
                return target == 2160 ? longSide >= 3840 : longSide >= 1920 && longSide < 3840
            }
            if let selected = matches.sorted(by: { abs($0.framesPerSecond - 60) < abs($1.framesPerSecond - 60) }).first {
                configuration.videoFormat = selected
            }
            configuredResolution = target
        }

        func updateFormatIfNeeded() {
            guard configuredResolution != store.resolution, !store.recording, let view = view else { return }
            let config = ARWorldTrackingConfiguration()
            config.worldAlignment = .gravity
            config.planeDetection = [.horizontal]
            applyVideoFormat(to: config)
            // Reconfiguration resets the session and invalidates the previously placed origin.
            placed = false
            reticle.isHidden = true
            gizmo.isHidden = true
            groundGrid.isHidden = true
            gridOrigin = nil
            currentPlacement = nil
            store.resetOrigin()
            view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }

        init(store: TrackingStore) { self.store = store }

        func setup(in view: ARSCNView) {
            self.view = view
            makeReticle()
            makeGizmo()
            makeGroundGrid()
            store.onMarkers = { [weak self] markers in self?.showMarkers(markers) }
            store.onClearMarkers = { [weak self] in self?.clearMarkerPreview() }
            view.scene.rootNode.addChildNode(reticle)
            view.scene.rootNode.addChildNode(gizmo)
            view.scene.rootNode.addChildNode(groundGrid)
            reticle.isHidden = true
            gizmo.isHidden = true
            groundGrid.isHidden = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            view.addGestureRecognizer(tap)
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            store.process(frame)
            let now = frame.timestamp
            guard now - lastRaycast > 0.033 else { return }
            lastRaycast = now
            DispatchQueue.main.async { [weak self] in self?.updatePlacement() }
        }

        private func updatePlacement() {
            guard let view = view, !placed else { return }
            let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            guard let query = view.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .horizontal),
                  let result = view.session.raycast(query).first else {
                reticle.isHidden = true
                currentPlacement = nil
                if store.canPlaceOrigin { store.canPlaceOrigin = false }
                return
            }
            currentPlacement = result.worldTransform
            reticle.simdTransform = result.worldTransform
            reticle.isHidden = false
            if gridOrigin == nil || abs((gridOrigin?.columns.3.y ?? 0) - result.worldTransform.columns.3.y) > 0.025 {
                // Follow the candidate surface height until the origin is committed.
                // Rebase when moving between a desk and the floor; never move a placed origin.
                gridOrigin = result.worldTransform
                groundGrid.simdTransform = result.worldTransform
            }
            if let base = gridOrigin {
                let local = simd_inverse(base) * result.worldTransform
                // SCNPlane is rotated -90 degrees about X: local +Y maps to world -Z.
                // The shader uses UV with V increasing along the plane's local +Y.
                // Keep the mesh recentered in world space, snapped to whole dot intervals.
                let dotSpacing: Float = 0.05
                let localX = local.columns.3.x
                let localZ = local.columns.3.z
                if abs(localX) > 1.5 || abs(localZ) > 1.5 {
                    var shifted = base
                    let stepX = (localX / dotSpacing).rounded(.towardZero) * dotSpacing
                    let stepZ = (localZ / dotSpacing).rounded(.towardZero) * dotSpacing
                    let worldShift = simd_mul(base, SIMD4<Float>(stepX, 0, stepZ, 0))
                    shifted.columns.3 += worldShift
                    gridOrigin = shifted
                    groundGrid.simdTransform = shifted
                }
                let updatedBase = gridOrigin ?? base
                let updatedLocal = simd_inverse(updatedBase) * result.worldTransform
                let u = 0.5 + updatedLocal.columns.3.x / 5.0
                let v = 0.5 + updatedLocal.columns.3.z / 5.0
                gridMaterial?.setValue(SCNVector3(u, v, 0), forKey: "revealUV")
                groundGrid.isHidden = false
            }
            if !store.canPlaceOrigin { store.canPlaceOrigin = true }
            if store.message == "Scan a textured floor" { store.message = "Tap to set origin" }
        }

        @objc private func tapped(_ gesture: UITapGestureRecognizer) { placeOrigin() }

        func placeOrigin() {
            guard !placed, let matrix = currentPlacement else { return }
            placed = true
            gizmo.simdTransform = matrix
            gizmo.isHidden = false
            reticle.isHidden = true
            groundGrid.isHidden = true
            store.setOrigin(matrix)
        }

        func clearMarkerPreview() {
            markerNodes.values.forEach { $0.removeFromParentNode() }
            markerNodes.removeAll()
            lastMarkerSeen.removeAll()
        }

        func resetPlacement() {
            guard !store.recording else { return }
            placed = false
            gizmo.isHidden = true
            groundGrid.isHidden = true
            gridOrigin = nil
            currentPlacement = nil
            store.resetOrigin()
        }

        private func showMarkers(_ markers: [LiveMarker]) {
            guard let view = view else { return }
            let now = ProcessInfo.processInfo.systemUptime
            // Keep the last measured pose visible during brief missed scans.
            // Never fabricate marker samples or interpolate raw recorded data.
            let visibleIDs = Set(markers.map(\.id))
            for (id, node) in markerNodes where !visibleIDs.contains(id) {
                let age = now - (lastMarkerSeen[id] ?? 0)
                // Retain the last measured pose until mode reset; never invent measurements.
                node.isHidden = false
                node.opacity = age > 0.20 ? 0.48 : 1.0
            }
            for marker in markers {
                let node: SCNNode
                if let existing = markerNodes[marker.id] { node = existing }
                else {
                    node = SCNNode()
                    // Short RGB axes, centered at the tag, oriented in tag local coordinates.
                    segment(SIMD3<Float>(0,0,0), SIMD3<Float>(0.065,0,0), radius: 0.0015, color: .red, parent: node)
                    segment(SIMD3<Float>(0,0,0), SIMD3<Float>(0,0.065,0), radius: 0.0015, color: .green, parent: node)
                    segment(SIMD3<Float>(0,0,0), SIMD3<Float>(0,0,0.065), radius: 0.0015, color: .blue, parent: node)
                    // Emissive corner brackets around the physical 88.9mm tag boundary.
                    let half: Float = 0.04445
                    let arm: Float = 0.014
                    let bracketColor = UIColor(red: 1, green: 0.38, blue: 0.38, alpha: 1)
                    for sx: Float in [-1, 1] {
                        for sy: Float in [-1, 1] {
                            let x = sx * half, y = sy * half
                            segment(SIMD3<Float>(x, y, 0.001), SIMD3<Float>(x-sx*arm, y, 0.001), radius: 0.0013, color: bracketColor, parent: node)
                            segment(SIMD3<Float>(x, y, 0.001), SIMD3<Float>(x, y-sy*arm, 0.001), radius: 0.0013, color: bracketColor, parent: node)
                        }
                    }
                    let label = SCNText(string: "TAG \(marker.id)", extrusionDepth: 0)
                    label.font = UIFont.monospacedSystemFont(ofSize: 8, weight: .bold)
                    label.firstMaterial = material(.white)
                    let labelNode = SCNNode(geometry: label)
                    labelNode.scale = SCNVector3(0.002, 0.002, 0.002)
                    labelNode.position = SCNVector3(0, 0.075, 0)
                    node.addChildNode(labelNode)
                    view.scene.rootNode.addChildNode(node)
                    markerNodes[marker.id] = node
                }
                node.simdTransform = marker.transform
                node.isHidden = false
                node.opacity = 1.0
                lastMarkerSeen[marker.id] = now
            }

        }

        private func material(_ color: UIColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.lightingModel = .constant
            m.isDoubleSided = true
            m.readsFromDepthBuffer = true
            return m
        }

        private func segment(_ a: SIMD3<Float>, _ b: SIMD3<Float>, radius: CGFloat, color: UIColor, parent: SCNNode) {
            let delta = b - a
            let length = simd_length(delta)
            guard length > 0.0001 else { return }
            let shape = SCNCylinder(radius: radius, height: CGFloat(length))
            shape.radialSegmentCount = 7
            shape.materials = [material(color)]
            let node = SCNNode(geometry: shape)
            node.simdPosition = (a + b) / 2
            node.simdOrientation = simd_quatf(from: SIMD3<Float>(0,1,0), to: simd_normalize(delta))
            parent.addChildNode(node)
        }

        // All placement graphics are flat, unlit, and double-sided.
        // The ring is an opaque texture, so no overlapping torus/shadow geometry is needed.
        private func makeReticle() {
            let size: CGFloat = 512
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            let image = renderer.image { context in
                let cg = context.cgContext
                let coral = UIColor(red: 231/255, green: 125/255, blue: 118/255, alpha: 1)
                let ivory = UIColor(red: 242/255, green: 240/255, blue: 236/255, alpha: 1)
                for i in stride(from: 70, through: 18, by: -4) {
                    cg.setStrokeColor(coral.withAlphaComponent(0.025 + CGFloat(70-i) / 3500).cgColor)
                    cg.setLineWidth(CGFloat(i))
                    cg.strokeEllipse(in: CGRect(x: 45, y: 45, width: 422, height: 422))
                }
                cg.setStrokeColor(coral.cgColor)
                cg.setLineWidth(17)
                cg.strokeEllipse(in: CGRect(x: 45, y: 45, width: 422, height: 422))
                cg.setStrokeColor(coral.cgColor)
                cg.setLineWidth(12)
                cg.strokeEllipse(in: CGRect(x: 215, y: 215, width: 82, height: 82))
                cg.setFillColor(ivory.cgColor)
                cg.fillEllipse(in: CGRect(x: 237, y: 237, width: 38, height: 38))
            }
            let plane = SCNPlane(width: 0.24, height: 0.24)
            let m = material(.white)
            m.diffuse.contents = image
            m.transparencyMode = .aOne
            m.writesToDepthBuffer = false
            m.readsFromDepthBuffer = false
            plane.materials = [m]
            let node = SCNNode(geometry: plane)
            node.eulerAngles.x = -.pi / 2
            node.position.y = 0.008
            reticle.addChildNode(node)
        }

        private func makeGroundGrid() {
            let size: CGFloat = 2048
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            let image = renderer.image { context in
                let cg = context.cgContext
                let coral = UIColor(red: 1, green: 0.29, blue: 0.32, alpha: 1)
                let count = 100
                let step = size / CGFloat(count)
                // Very faint connecting lines. The alpha-reveal shader fades the entire pattern.
                cg.setStrokeColor(coral.withAlphaComponent(0.13).cgColor)
                cg.setLineWidth(0.65)
                for n in 0...count {
                    let v = CGFloat(n) * step
                    cg.move(to: CGPoint(x: v, y: 0)); cg.addLine(to: CGPoint(x: v, y: size))
                    cg.move(to: CGPoint(x: 0, y: v)); cg.addLine(to: CGPoint(x: size, y: v))
                }
                cg.strokePath()
                for x in 0...count {
                    for y in 0...count {
                        let px = CGFloat(x) * step
                        let py = CGFloat(y) * step
                        // Deliberately exaggerated coral bloom: broad translucent halo,
                        // saturated inner glow, and a small white-hot center.
                        for (radius, alpha) in [(10.0, 0.045), (7.0, 0.09), (4.5, 0.20), (2.5, 0.60)] {
                            let r = CGFloat(radius)
                            cg.setFillColor(coral.withAlphaComponent(CGFloat(alpha)).cgColor)
                            cg.fillEllipse(in: CGRect(x: px-r, y: py-r, width: r*2, height: r*2))
                        }
                        cg.setFillColor(UIColor(red: 1, green: 0.94, blue: 0.88, alpha: 1).cgColor)
                        cg.fillEllipse(in: CGRect(x: px-1.05, y: py-1.05, width: 2.1, height: 2.1))
                    }
                }
            }
            let plane = SCNPlane(width: 5, height: 5)
            let m = material(.white)
            m.diffuse.contents = image
            m.transparencyMode = .aOne
            m.writesToDepthBuffer = false
            m.readsFromDepthBuffer = false
            m.setValue(SCNVector3(0.5, 0.5, 0), forKey: "revealUV")
            m.shaderModifiers = [.surface: """
                uniform vec3 revealUV;
                float distanceMeters = distance(_surface.diffuseTexcoord, revealUV.xy) * 5.0;
                float fade = 0.95 * (1.0 - smoothstep(0.03, 0.57, distanceMeters));
                _surface.diffuse.a *= fade;
            """]
            plane.materials = [m]
            gridMaterial = m
            let node = SCNNode(geometry: plane)
            node.eulerAngles.x = -.pi / 2
            node.position.y = 0.003
            groundGrid.addChildNode(node)
        }

        private func makeGizmo() {
            let axes: [(SIMD3<Float>, UIColor)] = [
                (SIMD3<Float>(1,0,0), .systemRed),
                (SIMD3<Float>(0,1,0), .systemGreen),
                (SIMD3<Float>(0,0,1), .systemBlue)
            ]
            for (direction, color) in axes {
                segment(.zero, direction * 0.28, radius: 0.0035, color: color, parent: gizmo)
                for index in 0..<6 {
                    let start = Float(index) * 0.046 + 0.008
                    let end = start + 0.024
                    segment(-direction * start, -direction * end, radius: 0.002, color: color.withAlphaComponent(0.68), parent: gizmo)
                }
            }
            let center = SCNSphere(radius: 0.006)
            center.materials = [material(.white)]
            gizmo.addChildNode(SCNNode(geometry: center))
        }
    }
}
