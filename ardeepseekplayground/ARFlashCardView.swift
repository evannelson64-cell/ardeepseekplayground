import SwiftUI
import RealityKit
import ARKit

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
                    Button {
                        dismiss()
                    } label: {
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
                        Text("Loading 3D model…")
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
        context.coordinator.arView = arView
        arView.session.delegate = context.coordinator

        let config = ARImageTrackingConfiguration()
        config.trackingImages = manager.makeReferenceImages()
        config.maximumNumberOfTrackedImages = manager.flashcards.count
        arView.session.run(config)

        return arView
    }

    func updateUIView(_: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(manager: manager, isLoading: $isLoading)
    }

    // MARK: - Coordinator (ARSessionDelegate)

    class Coordinator: NSObject, ARSessionDelegate {
        let manager: FlashCardManager
        @Binding var isLoading: Bool
        var modelCache: [String: Entity] = [:]
        weak var arView: ARView?

        private let api = SketchfabAPI()

        init(manager: FlashCardManager, isLoading: Binding<Bool>) {
            self.manager = manager
            _isLoading = isLoading
        }

        // MARK: - Track placed anchors for manual transform updates

        /// Maps ARImageAnchor name → AnchorEntity so we can update transforms in didUpdate.
        private var trackedAnchors: [String: AnchorEntity] = [:]

        // MARK: Image Detected

        @MainActor
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            for anchor in anchors {
                guard let imageAnchor = anchor as? ARImageAnchor,
                      let cardID = UUID(uuidString: imageAnchor.referenceImage.name ?? ""),
                      let card = manager.flashcards.first(where: { $0.id == cardID }),
                      let modelUID = card.modelUID
                else { continue }

                let anchorKey = card.id.uuidString

                // Don't re-place if we already placed for this anchor
                if trackedAnchors[anchorKey] != nil { continue }

                placeModel(for: card, modelUID: modelUID, imageAnchor: imageAnchor, anchorKey: anchorKey)
            }
        }

        // MARK: Image Tracking Updates (6-DOF)

        @MainActor
        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            for anchor in anchors {
                guard let imageAnchor = anchor as? ARImageAnchor,
                      let name = imageAnchor.referenceImage.name,
                      let anchorEntity = trackedAnchors[name] else { continue }
                // Update the anchor's transform to match the detected image's
                // current position & orientation – this gives us full 6-DOF tracking.
                anchorEntity.setTransformMatrix(imageAnchor.transform, relativeTo: nil)
            }
        }

        // MARK: Place Model on Image Anchor

        @MainActor
        func placeModel(for card: FlashCard, modelUID: String, imageAnchor: ARImageAnchor, anchorKey: String) {
            guard let arView = arView else { return }

            isLoading = true

            Task {
                let entity: Entity

                // 1. Check in-memory cache
                if let cached = modelCache[modelUID] {
                    entity = cached
                }
                // 2. Check on-disk cache
                else if let cachedURL = manager.cachedModelURL(for: modelUID),
                        let loaded = try? await Entity.load(contentsOf: cachedURL) {
                    modelCache[modelUID] = loaded
                    entity = loaded
                }
                // 3. Download from Sketchfab
                else {
                    do {
                        let info = try await api.downloadInfo(for: modelUID)
                        guard let usdz = info.usdz,
                              let url = URL(string: usdz.url)
                        else {
                            isLoading = false
                            return
                        }

                        let (tempURL, _) = try await URLSession.shared.download(from: url)
                        let cachedURL = try manager.cacheModel(from: tempURL, uid: modelUID)
                        let loaded = try await Entity.load(contentsOf: cachedURL)
                        modelCache[modelUID] = loaded
                        entity = loaded
                    } catch {
                        print("Failed to load model for flashcard: \(error)")
                        isLoading = false
                        return
                    }
                }

                // Place the entity at the image anchor's initial world transform.
                // We manually update the transform in session(_:didUpdate:) to
                // follow the image's position and rotation in real time.
                let anchorEntity = AnchorEntity(world: imageAnchor.transform)
                anchorEntity.name = "fc_\(card.id.uuidString)"

                let clone = entity.clone(recursive: true)

                // Auto-scale very tiny models
                let bounds = clone.visualBounds(relativeTo: nil)
                if bounds.boundingRadius < 0.01 {
                    clone.scale = SIMD3<Float>(repeating: 0.5)
                }

                anchorEntity.addChild(clone)
                arView.scene.addAnchor(anchorEntity)
                trackedAnchors[anchorKey] = anchorEntity

                isLoading = false
            }
        }
    }
}
