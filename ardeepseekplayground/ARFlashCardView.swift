import SwiftUI
import RealityKit
import ARKit
import Combine

// MARK: - SwiftUI Wrapper

struct ARFlashCardView: View {
    @ObservedObject var manager: FlashCardManager
    @Environment(\.dismiss) private var dismiss
    @State private var isLoadingModel = false

    var body: some View {
        ZStack {
            ARFlashCardContainer(manager: manager, isLoading: $isLoadingModel)
                .edgesIgnoringSafeArea(.all)

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Label("Close", systemImage: "xmark.circle.fill")
                            .font(.title2)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                    .padding()
                    Spacer()
                }
                Spacer()

                if isLoadingModel {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Loading 3D model\u{2026}")
                            .font(.subheadline)
                    }
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

// MARK: - UIViewRepresentable AR View

struct ARFlashCardContainer: UIViewRepresentable {
    @ObservedObject var manager: FlashCardManager
    @Binding var isLoading: Bool

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.setup(arView: arView)
        return arView
    }

    func updateUIView(_: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(manager: manager, isLoading: $isLoading)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        let manager: FlashCardManager
        @Binding var isLoading: Bool
        var modelCache: [String: Entity] = [:]
        weak var arView: ARView?
        private var updateSubscription: (any Cancellable)?
        private let api = SketchfabAPI()

        init(manager: FlashCardManager, isLoading: Binding<Bool>) {
            self.manager = manager
            _isLoading = isLoading
        }

        @MainActor
        func setup(arView: ARView) {
            self.arView = arView

            // Configure image tracking
            let config = ARImageTrackingConfiguration()
            config.trackingImages = manager.makeReferenceImages()
            config.maximumNumberOfTrackedImages = manager.flashcards.count
            arView.session.delegate = self
            arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

            // ── Per-frame update subscription ──
            // This fires every frame on the main thread and polls the
            // current AR frame's anchors – much more reliable than
            // ARSessionDelegate for keeping transforms in sync.
            updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) {
                [weak self] _ in
                self?.onFrameUpdate()
            }
        }

        // MARK: Per-frame tracking update

        private func onFrameUpdate() {
            guard let arView = arView,
                  let currentFrame = arView.session.currentFrame else { return }

            for anchor in currentFrame.anchors {
                guard let imageAnchor = anchor as? ARImageAnchor,
                      let imgName = imageAnchor.referenceImage.name else { continue }

                let anchorName = "fc_\(imgName)"
                if let entity = arView.scene.anchors.first(where: { $0.name == anchorName }) {
                    entity.transform = Transform(matrix: imageAnchor.transform)
                }
            }
        }

        // MARK: Image Detected (via delegate)

        nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            Task { @MainActor in
                await handleDidAdd(anchors: anchors)
            }
        }

        @MainActor
        private func handleDidAdd(anchors: [ARAnchor]) async {
            for anchor in anchors {
                guard let imageAnchor = anchor as? ARImageAnchor,
                      let cardID = UUID(uuidString: imageAnchor.referenceImage.name ?? ""),
                      let card = manager.flashcards.first(where: { $0.id == cardID }),
                      let modelUID = card.modelUID
                else { continue }

                let anchorName = "fc_\(card.id.uuidString)"

                // Don't re-place if already placed
                if arView?.scene.anchors.contains(where: { $0.name == anchorName }) == true { continue }

                placeModel(for: card, modelUID: modelUID, imageAnchor: imageAnchor, anchorName: anchorName)
            }
        }

        // MARK: Place Model

        @MainActor
        func placeModel(for card: FlashCard, modelUID: String, imageAnchor: ARImageAnchor, anchorName: String) {
            guard let arView = arView else { return }

            // ── DEBUG: Place a red sphere first to verify tracking ──
            let sphere = ModelEntity(
                mesh: .generateSphere(radius: 0.03),
                materials: [SimpleMaterial(color: .red, isMetallic: false)]
            )
            let stem = ModelEntity(
                mesh: .generateCylinder(height: 0.08, radius: 0.005),
                materials: [SimpleMaterial(color: .white, isMetallic: false)]
            )
            stem.position.y = 0.04

            let marker = Entity()
            marker.addChild(sphere)
            marker.addChild(stem)

            let anchorEntity = AnchorEntity(world: imageAnchor.transform)
            anchorEntity.name = anchorName
            anchorEntity.addChild(marker)
            arView.scene.addAnchor(anchorEntity)
            print("🔴 DEBUG: Red marker placed at image position")

            // ── Load real model in background ──
            isLoading = true
            Task {
                let entity: Entity?

                if let cached = modelCache[modelUID] {
                    entity = cached
                } else if let cachedURL = manager.cachedModelURL(for: modelUID),
                          let loaded = try? await Entity.load(contentsOf: cachedURL) {
                    modelCache[modelUID] = loaded
                    entity = loaded
                } else {
                    do {
                        let info = try await api.downloadInfo(for: modelUID)
                        guard let usdz = info.usdz, let url = URL(string: usdz.url) else {
                            isLoading = false; return
                        }
                        let (tempURL, _) = try await URLSession.shared.download(from: url)
                        let cachedURL = try manager.cacheModel(from: tempURL, uid: modelUID)
                        let loaded = try await Entity.load(contentsOf: cachedURL)
                        modelCache[modelUID] = loaded
                        entity = loaded
                    } catch {
                        print("Model download failed: \(error)")
                        isLoading = false; return
                    }
                }

                if let entity = entity {
                    let clone = entity.clone(recursive: true)
                    clone.scale *= SIMD3<Float>(repeating: card.modelScale)
                    let rotationRad = card.modelRotationDegrees * .pi / 180
                    clone.transform.rotation *= simd_quatf(angle: rotationRad, axis: [0, 1, 0])
                    clone.position.y += card.modelVerticalOffset
                    let bounds = clone.visualBounds(relativeTo: nil)
                    if bounds.boundingRadius < 0.001 { clone.scale *= 0.5 }

                    marker.removeFromParent()
                    anchorEntity.addChild(clone)
                    print("✅ Swapped to real model")
                }
                isLoading = false
            }
        }
    }
}

// MARK: - ARSessionDelegate conformance

extension ARFlashCardContainer.Coordinator: ARSessionDelegate {
}
