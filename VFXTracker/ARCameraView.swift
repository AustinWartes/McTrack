import SwiftUI
import ARKit
import SceneKit

struct ARCameraView: UIViewRepresentable {
    @ObservedObject var store: TrackingStore

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.automaticallyUpdatesLighting = false
        view.autoenablesDefaultLighting = false
        view.scene = SCNScene()
        view.delegate = context.coordinator
        view.rendersContinuously = true
        view.antialiasingMode = .none
        view.contentMode = .scaleAspectFill

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.isLightEstimationEnabled = false
        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        // A visual reference 1.5 m in front of the initial camera.
        // ARKit world origin itself remains at the initial camera position.
        addAxisGizmo(to: view.scene.rootNode, position: SCNVector3(0, 0, -1.5))
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    private func addAxisGizmo(to root: SCNNode, position: SCNVector3) {
        let group = SCNNode()
        group.position = position
        let length: CGFloat = 0.28
        let radius: CGFloat = 0.004

        func axis(_ color: UIColor, direction: SCNVector3) -> SCNNode {
            let cylinder = SCNCylinder(radius: radius, height: length)
            cylinder.radialSegmentCount = 8
            cylinder.firstMaterial?.diffuse.contents = color
            let node = SCNNode(geometry: cylinder)
            node.position = SCNVector3(direction.x * Float(length / 2),
                                        direction.y * Float(length / 2),
                                        direction.z * Float(length / 2))
            node.simdLook(at: SIMD3<Float>(direction.x, direction.y, direction.z),
                          up: SIMD3<Float>(0, 1, 0),
                          localFront: SIMD3<Float>(0, 1, 0))
            return node
        }

        group.addChildNode(axis(.systemRed, direction: SCNVector3(1, 0, 0)))
        group.addChildNode(axis(.systemGreen, direction: SCNVector3(0, 1, 0)))
        group.addChildNode(axis(.systemBlue, direction: SCNVector3(0, 0, -1)))
        root.addChildNode(group)
    }

    final class Coordinator: NSObject, ARSCNViewDelegate {
        private let store: TrackingStore
        init(store: TrackingStore) { self.store = store }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard let sceneView = renderer as? ARSCNView,
                  let frame = sceneView.session.currentFrame else { return }
            store.updateTrackingState(frame.camera.trackingState)
            store.append(frame: frame)
        }
    }
}
