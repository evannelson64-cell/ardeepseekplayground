import SwiftUI
import SceneKit

/// Adjust model position with sliders + live 3D preview.
struct GlueView: View {
    let image: UIImage
    let modelUID: String
    let card: FlashCard
    let manager: FlashCardManager
    @Environment(\.dismiss) private var dismiss

    @State private var scale: Float
    @State private var rotation: Float
    @State private var yOffset: Float
    @State private var scene: SCNScene?
    @State private var modelLoaded = false

    init(image: UIImage, modelUID: String, card: FlashCard, manager: FlashCardManager) {
        self.image = image
        self.modelUID = modelUID
        self.card = card
        self.manager = manager
        _scale = State(initialValue: card.modelScale)
        _rotation = State(initialValue: card.modelRotationDegrees)
        _yOffset = State(initialValue: card.modelVerticalOffset)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 3D preview area
            ZStack {
                Color(white: 0.15)
                if let scene = scene {
                    SCNViewRepresentable(scene: scene, scale: $scale, rotation: $rotation, yOffset: $yOffset)
                } else {
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("Loading model\u{2026}").foregroundColor(.white).font(.caption)
                    }
                }
            }
            .frame(height: 280)

            // Sliders
            ScrollView {
                VStack(spacing: 20) {
                    Color.clear.frame(height: 4)
                    VStack(spacing: 4) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text("Scale  \(String(format: "%.1f×", scale))")
                            Spacer()
                        }
                        .font(.subheadline)
                        Slider(value: $scale, in: 0.1...5.0, step: 0.1)
                    }
                    .padding(.horizontal)

                    VStack(spacing: 4) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Rotation  \(String(format: "%.0f°", rotation))")
                            Spacer()
                        }
                        .font(.subheadline)
                        Slider(value: $rotation, in: 0...360, step: 1)
                    }
                    .padding(.horizontal)

                    VStack(spacing: 4) {
                        HStack {
                            Image(systemName: "arrow.up.and.down")
                            Text("Height  \(String(format: "%.2f", yOffset))")
                            Spacer()
                        }
                        .font(.subheadline)
                        Slider(value: $yOffset, in: -0.3...0.5, step: 0.01)
                    }
                    .padding(.horizontal)

                    Button {
                        manager.updateAdjustments(for: card.id, scale: scale,
                                                  rotationDegrees: rotation,
                                                  verticalOffset: yOffset)
                        dismiss()
                    } label: {
                        Label("Save & Continue", systemImage: "checkmark.circle.fill")
                            .font(.headline.bold())
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Position Model")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadModel() }
    }

    private func loadModel() async {
        let s = SCNScene()
        s.background.contents = UIColor.darkGray

        // Floor with the tracked image as texture
        let aspect = image.size.width / image.size.height
        let plane = SCNPlane(width: 0.3, height: 0.3 / aspect)
        plane.firstMaterial?.diffuse.contents = image
        plane.firstMaterial?.isDoubleSided = true
        let floor = SCNNode(geometry: plane)
        floor.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        s.rootNode.addChildNode(floor)

        // Camera
        let cam = SCNCamera()
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 0.4, 0.8)
        camNode.look(at: SCNVector3(0, 0, 0))
        s.rootNode.addChildNode(camNode)

        // Lights
        let amb = SCNNode(); amb.light = SCNLight(); amb.light?.type = .ambient
        amb.light?.color = UIColor(white: 0.5, alpha: 1)
        s.rootNode.addChildNode(amb)
        let dir = SCNNode(); dir.light = SCNLight(); dir.light?.type = .directional
        dir.light?.color = UIColor(white: 0.8, alpha: 1)
        dir.eulerAngles = SCNVector3(-0.5, 0.5, 0)
        s.rootNode.addChildNode(dir)

        // Load model
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("flashcard_models/\(modelUID).usdz")

        if !FileManager.default.fileExists(atPath: url.path) {
            let api = SketchfabAPI()
            do {
                let info = try await api.downloadInfo(for: modelUID)
                guard let usdz = info.usdz, let dl = URL(string: usdz.url) else { scene = s; return }
                let (tmp, _) = try await URLSession.shared.download(from: dl)
                try? FileManager.default.removeItem(at: url)
                try FileManager.default.moveItem(at: tmp, to: url)
            } catch { scene = s; return }
        }

        if let ms = try? SCNScene(url: url, options: nil),
           let child = ms.rootNode.childNodes.first {
            child.name = "glue_model"
            let sc = CGFloat(card.modelScale)
            child.scale = SCNVector3(sc, sc, sc)
            child.eulerAngles = SCNVector3(0, CGFloat(card.modelRotationDegrees * .pi / 180), 0)
            child.position = SCNVector3(CGFloat(card.modelHorizontalOffset.x),
                                        CGFloat(card.modelVerticalOffset),
                                        CGFloat(card.modelHorizontalOffset.y))
            s.rootNode.addChildNode(child)
        }

        scene = s
    }
}

// MARK: - Live-updating SceneKit View

private struct SCNViewRepresentable: UIViewRepresentable {
    let scene: SCNScene
    @Binding var scale: Float
    @Binding var rotation: Float
    @Binding var yOffset: Float

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero)
        v.scene = scene
        v.backgroundColor = UIColor(white: 0.15, alpha: 1)
        v.autoenablesDefaultLighting = true
        v.allowsCameraControl = true  // let user orbit with gesture
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        guard let modelNode = v.scene?.rootNode.childNode(withName: "glue_model", recursively: true)
        else { return }
        let s = CGFloat(scale)
        modelNode.scale = SCNVector3(s, s, s)
        modelNode.eulerAngles = SCNVector3(0, rotation * (Float.pi / 180), 0)
        modelNode.position.y = yOffset
    }
}

