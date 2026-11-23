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
        private let rigidGizmo = SCNNode()
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
            store.onRigidPose = { [weak self] pose in self?.showRigidPose(pose) }
            view.scene.rootNode.addChildNode(reticle)
            view.scene.rootNode.addChildNode(gizmo)
            view.scene.rootNode.addChildNode(groundGrid)
            view.scene.rootNode.addChildNode(rigidGizmo)
            rigidGizmo.isHidden = true
            makeRigidGizmo()
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
            rigidGizmo.isHidden = true
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
            if store.trackingMode == .rigid && !store.rigidCalibrating {
                markerNodes.values.forEach { $0.removeFromParentNode() }
                markerNodes.removeAll(); lastMarkerSeen.removeAll()
                return
            }
            // Keep the last measured pose visible during brief missed scans.
            // Never fabricate marker samples or interpolate raw recorded data.
            let visibleIDs = Set(markers.map(\.id))
            for (id, node) in markerNodes where !visibleIDs.contains(id) {
                let age = now - (lastMarkerSeen[id] ?? 0)
                // Rigid calibration shows only currently observed tags.
                if store.trackingMode == .rigid { node.removeFromParentNode(); markerNodes.removeValue(forKey: id); lastMarkerSeen.removeValue(forKey: id); continue }
                node.isHidden = false
                node.opacity = age > 0.20 ? 0.48 : 1.0
            }
            for marker in markers {
                let node: SCNNode
                if let existing = markerNodes[marker.id] { node = existing }
                else {
                    node = SCNNode()
                    // Short RGB axes, centered at the tag, oriented in tag local coordinates.
                    // Pastel axes are intentionally unglowed: distinct from the luminous origin gizmo.
                    let tagRed = UIColor(red: 1.0, green: 0.55, blue: 0.53, alpha: 1)
                    let tagGreen = UIColor(red: 0.52, green: 1.0, blue: 0.57, alpha: 1)
                    let tagBlue = UIColor(red: 0.53, green: 0.71, blue: 1.0, alpha: 1)
                    segment(.zero, SIMD3<Float>(0.065,0,0), radius: 0.0015, color: tagRed, parent: node)
                    segment(.zero, SIMD3<Float>(0,0.065,0), radius: 0.0015, color: tagGreen, parent: node)
                    segment(.zero, SIMD3<Float>(0,0,0.065), radius: 0.0015, color: tagBlue, parent: node)
                    // Flat transparent artwork instead of 3D cylinders for tag corners.
                    let corners = SCNPlane(width: 0.112, height: 0.112)
                    let cornerMaterial = overlayMaterial(named: "CoralTagCorners")
                    corners.materials = [cornerMaterial]
                    let cornerNode = SCNNode(geometry: corners)
                    cornerNode.position.z = 0.001
                    node.addChildNode(cornerNode)
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

        private func showRigidPose(_ pose: simd_float4x4?) {
            guard let pose else { return }
            rigidGizmo.simdTransform = pose
            rigidGizmo.simdScale = SIMD3<Float>(repeating: Float(store.rigidCubeMillimeters / 1000))
            rigidGizmo.isHidden = false
        }
        private func makeRigidGizmo() {
            // A solid invisible cube writes depth; only the visible edges survive depth testing.
            // All coordinates are cube-local, and can be rescaled with the calibrated edge.
            let cube = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
            let occluder = SCNMaterial()
            occluder.colorBufferWriteMask = []
            occluder.writesToDepthBuffer = true
            occluder.readsFromDepthBuffer = true
            occluder.lightingModel = .constant
            cube.materials = Array(repeating: occluder, count: 6)
            let solid = SCNNode(geometry: cube)
            solid.renderingOrder = -1
            rigidGizmo.addChildNode(solid)
            let h: Float = 0.5
            let color = UIColor(red: 1, green: 0.55, blue: 0.52, alpha: 1)
            let vertices: [SIMD3<Float>] = [SIMD3(-h,-h,-h), SIMD3(h,-h,-h), SIMD3(h,h,-h), SIMD3(-h,h,-h), SIMD3(-h,-h,h), SIMD3(h,-h,h), SIMD3(h,h,h), SIMD3(-h,h,h)]
            let pairs = [(0,1),(1,2),(2,3),(3,0),(4,5),(5,6),(6,7),(7,4),(0,4),(1,5),(2,6),(3,7)]
            for (i,j) in pairs {
                segment(vertices[i], vertices[j], radius: 0.012, color: color, parent: rigidGizmo)
            }
            segment(SIMD3(0,-0.65,0), SIMD3(0,0.65,0), radius: 0.015,
                    color: UIColor(red: 0.65, green: 1, blue: 0.75, alpha: 1), parent: rigidGizmo)
            rigidGizmo.simdScale = SIMD3<Float>(repeating: Float(store.rigidCubeMillimeters / 1000))
        }
        private func material(_ color: UIColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.lightingModel = .constant
            m.isDoubleSided = true
            m.readsFromDepthBuffer = true
            m.emission.contents = color.withAlphaComponent(0.25)
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

        // Explicitly colored PNGs avoid UIKit/SceneKit runtime gradient differences.
        // Constant lighting, no additive blending, and no emissive white contribution.
        private func overlayMaterial(named name: String) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = UIImage(named: name)
            m.lightingModel = .constant
            m.isDoubleSided = true
            m.transparencyMode = .aOne
            m.blendMode = .alpha
            m.writesToDepthBuffer = false
            m.readsFromDepthBuffer = false
            return m
        }

        private func makeReticle() {
            let plane = SCNPlane(width: 0.24, height: 0.24)
            plane.materials = [overlayMaterial(named: "CoralTarget")]
            let node = SCNNode(geometry: plane)
            node.eulerAngles.x = -.pi / 2
            node.position.y = 0.008
            reticle.addChildNode(node)
        }

        private func makeGroundGrid() {
            let plane = SCNPlane(width: 5, height: 5)
            let m = overlayMaterial(named: "CoralGrid")
            // Reveal near the placement target. This changes alpha only, never RGB.
            m.setValue(SCNVector3(0.5, 0.5, 0), forKey: "revealUV")
            m.shaderModifiers = [.surface: """
                uniform vec3 revealUV;
                float distanceMeters = distance(_surface.diffuseTexcoord, revealUV.xy) * 5.0;
                float fade = 1.0 - smoothstep(0.06, 0.825, distanceMeters);
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
            // Restore the distinct glowing origin axes; tag axes remain plain pastel.
            let axes: [(SIMD3<Float>, UIColor)] = [
                (SIMD3<Float>(1,0,0), UIColor(red: 1, green: 0.58, blue: 0.56, alpha: 1)),
                (SIMD3<Float>(0,1,0), UIColor(red: 0.54, green: 1, blue: 0.58, alpha: 1)),
                (SIMD3<Float>(0,0,1), UIColor(red: 0.55, green: 0.74, blue: 1, alpha: 1))
            ]
            for (direction, color) in axes {
                segment(.zero, direction * 0.28, radius: 0.0035, color: color, parent: gizmo)
                // Transparent wider sleeves form a gentle luminous halo.
                segment(.zero, direction * 0.28, radius: 0.010, color: color.withAlphaComponent(0.22), parent: gizmo)
                for index in 0..<6 {
                    let start = Float(index) * 0.046 + 0.008
                    let end = start + 0.024
                    segment(-direction * start, -direction * end, radius: 0.002, color: color.withAlphaComponent(0.68), parent: gizmo)
                }
            }
            let center = SCNSphere(radius: 0.006)
            center.materials = [material(UIColor(red: 1, green: 0.87, blue: 0.81, alpha: 1))]
            gizmo.addChildNode(SCNNode(geometry: center))
        }
    }
}
