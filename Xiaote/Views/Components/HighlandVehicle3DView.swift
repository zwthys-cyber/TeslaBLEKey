import SceneKit
import SwiftUI

struct HighlandVehicle3DView: UIViewRepresentable {
    let isLocked: Bool?
    let isFrunkOpen: Bool
    let isTrunkOpen: Bool
    let isChargePortOpen: Bool
    let doorStates: [String: Bool]
    let reduceMotion: Bool
    @Binding var loadFailed: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false

        guard let url = Bundle.main.url(forResource: "Model3Highland", withExtension: "usdz"),
              let scene = try? SCNScene(url: url, options: nil) else {
            DispatchQueue.main.async { loadFailed = true }
            return view
        }

        DispatchQueue.main.async { loadFailed = false }
        view.scene = scene
        context.coordinator.prepare(scene: scene)
        addCameraAndLighting(to: scene)
        updateState(in: context.coordinator, animated: false)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        updateState(in: context.coordinator, animated: !reduceMotion)
        view.rendersContinuously = false
        view.setNeedsDisplay()
    }

    private func addCameraAndLighting(to scene: SCNScene) {
        let camera = SCNNode()
        camera.name = "xiaote_camera"
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 34
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 100
        camera.position = SCNVector3(5.2, 5.8, 3.0)
        camera.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(camera)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 1_250
        key.eulerAngles = SCNVector3(-0.8, 0.55, 0.35)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.intensity = 650
        fill.position = SCNVector3(-3, -1, 4)
        scene.rootNode.addChildNode(fill)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 420
        ambient.light?.color = UIColor(white: 0.72, alpha: 1)
        scene.rootNode.addChildNode(ambient)
    }

    private func updateState(in coordinator: Coordinator, animated: Bool) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.32 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        coordinator.rotate("door_left_front_pivot", open: doorStates["左前门"] == true, axis: .y, angle: -0.58)
        coordinator.rotate("door_left_rear_pivot", open: doorStates["左后门"] == true, axis: .y, angle: -0.52)
        coordinator.rotate("door_right_front_pivot", open: doorStates["右前门"] == true, axis: .y, angle: 0.58)
        coordinator.rotate("door_right_rear_pivot", open: doorStates["右后门"] == true, axis: .y, angle: 0.52)
        coordinator.rotate("frunk_pivot", open: isFrunkOpen, axis: .x, angle: -0.58)
        coordinator.rotate("trunk_pivot", open: isTrunkOpen, axis: .x, angle: 0.65)
        coordinator.rotate("charge_port_pivot", open: isChargePortOpen, axis: .y, angle: -0.72)
        coordinator.rotate("mirror_left_pivot", open: isLocked == true, axis: .y, angle: 0.48)
        coordinator.rotate("mirror_right_pivot", open: isLocked == true, axis: .y, angle: -0.48)

        SCNTransaction.commit()
    }

    final class Coordinator {
        enum Axis { case x, y, z }

        private var nodes: [String: SCNNode] = [:]
        private var baseTransforms: [String: SCNMatrix4] = [:]

        func prepare(scene: SCNScene) {
            let names = [
                "door_left_front_pivot", "door_left_rear_pivot",
                "door_right_front_pivot", "door_right_rear_pivot",
                "frunk_pivot", "trunk_pivot", "charge_port_pivot",
                "mirror_left_pivot", "mirror_right_pivot"
            ]
            for name in names {
                guard let node = scene.rootNode.childNode(withName: name, recursively: true) else { continue }
                nodes[name] = node
                baseTransforms[name] = node.transform
            }
        }

        func rotate(_ name: String, open: Bool, axis: Axis, angle: Float) {
            guard let node = nodes[name], let base = baseTransforms[name] else { return }
            guard open else {
                node.transform = base
                return
            }

            let vector: SCNVector3
            switch axis {
            case .x: vector = SCNVector3(1, 0, 0)
            case .y: vector = SCNVector3(0, 1, 0)
            case .z: vector = SCNVector3(0, 0, 1)
            }
            let stateRotation = SCNMatrix4MakeRotation(angle, vector.x, vector.y, vector.z)
            node.transform = SCNMatrix4Mult(base, stateRotation)
        }
    }
}
