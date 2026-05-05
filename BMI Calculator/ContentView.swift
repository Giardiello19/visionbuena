import SwiftUI
import RealityKit
import ARKit
import Vision
import AVFoundation

struct ContentView: View {
    var body: some View {
        HStack(spacing: 0) {
            ARViewContainer(offset: -0.02)
            ARViewContainer(offset: 0.02)
        }
        .edgesIgnoringSafeArea(.all)
    }
}

// =========================

struct ARViewContainer: UIViewRepresentable {

    var offset: Float

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {

        let arView = ARView(frame: .zero)

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        arView.session.run(config)
        arView.session.delegate = context.coordinator

        context.coordinator.setup(arView: arView)

        arView.cameraTransform.translation.x += offset

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

// =========================
// COORDINATOR
// =========================

class Coordinator: NSObject, ARSessionDelegate {

    weak var arView: ARView?

    var videoEntity: ModelEntity?
    var player: AVPlayer?

    let handRequest = VNDetectHumanHandPoseRequest()

    var smoothX: CGFloat = 0.5
    var smoothY: CGFloat = 0.5

    // =========================

    func setup(arView: ARView) {
        self.arView = arView

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        arView.addGestureRecognizer(tap)

        createUI()
    }

    // =========================
    // UI FLOTANTE
    // =========================

    func createUI() {
        guard let arView = arView else { return }

        let anchor = AnchorEntity(.camera)

        let btn = ModelEntity(
            mesh: .generatePlane(width: 0.15, depth: 0.08),
            materials: [SimpleMaterial(color: .red, isMetallic: false)]
        )

        btn.name = "spawnVideo"
        btn.position = [0, -0.25, -0.6]

        anchor.addChild(btn)
        arView.scene.addAnchor(anchor)
    }

    // =========================
    // TAP
    // =========================

    @objc func handleTap(recognizer: UITapGestureRecognizer) {

        guard let arView = arView else { return }

        let location = recognizer.location(in: arView)

        if let entity = arView.entity(at: location) as? ModelEntity {

            if entity.name == "spawnVideo" {
                createVideo()
                return
            }

            if entity.name == "playBtn" {
                player?.play()
                return
            }

            if entity.name == "pauseBtn" {
                player?.pause()
                return
            }

            videoEntity = entity
        }
    }

    // =========================
    // VIDEO HOLOGRAMA
    // =========================

    func createVideo() {

        guard let arView = arView else { return }

        guard let url = Bundle.main.url(forResource: "video", withExtension: "mp4") else {
            print("NO VIDEO ENCONTRADO")
            return
        }

        player = AVPlayer(url: url)

        let material = VideoMaterial(avPlayer: player!)

        let plane = ModelEntity(
            mesh: .generatePlane(width: 0.4, depth: 0.25),
            materials: [material]
        )

        plane.position = [0, 0, -0.6]
        plane.name = "video"

        videoEntity = plane

        let anchor = AnchorEntity(.camera)
        anchor.addChild(plane)

        // BOTONES PLAY / PAUSE

        let play = ModelEntity(
            mesh: .generatePlane(width: 0.08, depth: 0.05),
            materials: [SimpleMaterial(color: .green, isMetallic: false)]
        )
        play.name = "playBtn"
        play.position = [-0.1, -0.2, 0.01]

        let pause = ModelEntity(
            mesh: .generatePlane(width: 0.08, depth: 0.05),
            materials: [SimpleMaterial(color: .yellow, isMetallic: false)]
        )
        pause.name = "pauseBtn"
        pause.position = [0.1, -0.2, 0.01]

        plane.addChild(play)
        plane.addChild(pause)

        arView.scene.addAnchor(anchor)

        player?.play()
    }

    // =========================
    // HAND TRACKING
    // =========================

    func session(_ session: ARSession, didUpdate frame: ARFrame) {

        let handler = VNImageRequestHandler(
            cvPixelBuffer: frame.capturedImage,
            orientation: .up
        )

        try? handler.perform([handRequest])

        guard let result = handRequest.results?.first else { return }

        let points = try? result.recognizedPoints(.all)

        guard let index = points??[.indexTip],
              let thumb = points??[.thumbTip] else { return }

        let pinch = distance(index.location, thumb.location)

        DispatchQueue.main.async {
            self.updateHand(index: index.location, pinch: pinch)
        }
    }

    // =========================
    // CONTROL CON MANO
    // =========================

    func updateHand(index: CGPoint, pinch: CGFloat) {

        guard let arView = arView,
              let entity = videoEntity else { return }

        // SMOOTHING
        smoothX = smoothX * 0.8 + index.x * 0.2
        smoothY = smoothY * 0.8 + index.y * 0.2

        let point = CGPoint(
            x: smoothX * arView.bounds.width,
            y: (1 - smoothY) * arView.bounds.height
        )

        let results = arView.raycast(
            from: point,
            allowing: .estimatedPlane,
            alignment: .any
        )

        if let hit = results.first {
            entity.setTransformMatrix(hit.worldTransform, relativeTo: nil)
        }

        // ESCALA CON PINCH
        let s = max(0.2, min(0.8, pinch * 3))
        entity.scale = SIMD3<Float>(repeating: Float(s))
    }

    func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
    }
}