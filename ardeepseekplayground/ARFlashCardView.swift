import SwiftUI
import RealityKit
import ARKit
import Combine

// MARK: - SwiftUI Wrapper

struct ARFlashCardView: View {
    @ObservedObject var manager: FlashCardManager
    @Environment(\.dismiss) private var dismiss
    @State private var isLoadingModel = false
    @State private var errorMessage: String?
    @State private var triggerSave = false
    @State private var autoSaveDone = false
    let isAdjustmentMode: Bool  // true when shown from creation flow

    init(manager: FlashCardManager, isAdjustmentMode: Bool = false) {
        self.manager = manager
        self.isAdjustmentMode = isAdjustmentMode
    }

    var body: some View {
        ZStack {
            ARFlashCardContainer(manager: manager, isLoading: $isLoadingModel, errorMessage: $errorMessage,
                                 triggerSave: $triggerSave)
                .edgesIgnoringSafeArea(.all)

            VStack {
                HStack {
                    Button {
                        // Auto-save gesture positions on exit
                        triggerSave = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            autoSaveDone = true
                        }
                    } label: {
                        Label("Close", systemImage: "xmark.circle.fill")
                            .font(.title2)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                    .padding()
                    Spacer()

                    // Save button – only in adjustment mode (creation flow)
                    if isAdjustmentMode {
                        Button("Done Saving") {
                            triggerSave = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                autoSaveDone = true
                            }
                        }
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.green)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(.trailing)
                    }
                }
                .onChange(of: autoSaveDone) { _, done in
                    if done { dismiss() }
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
        .alert("Model Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

// MARK: - UIViewRepresentable AR View

struct ARFlashCardContainer: UIViewRepresentable {
    @ObservedObject var manager: FlashCardManager
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    @Binding var triggerSave: Bool

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.setup(arView: arView)
        return arView
    }

    func updateUIView(_: ARView, context: Context) {
        if triggerSave {
            // Defer to next run loop — saveAllPositions publishes to @Published
            // which can't happen during a SwiftUI view update cycle.
            DispatchQueue.main.async {
                context.coordinator.saveAllPositions(manager: manager)
                triggerSave = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(manager: manager, isLoading: $isLoading, errorMessage: $errorMessage)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        let manager: FlashCardManager
        @Binding var isLoading: Bool
        @Binding var errorMessage: String?
        var modelCache: [String: Entity] = [:]
        weak var arView: ARView?

        /// Maps image anchor name → content entity whose transform is updated every frame.
        private var contentEntities: [String: Entity] = [:]
        /// Maps image anchor name → model entity (clone) for gesture extraction on save.
        private var modelEntities: [String: Entity] = [:]
        private var updateSubscription: (any Cancellable)?
        private let api = SketchfabAPI()

        init(manager: FlashCardManager, isLoading: Binding<Bool>, errorMessage: Binding<String?>) {
            self.manager = manager
            _isLoading = isLoading
            _errorMessage = errorMessage
        }

        @MainActor
        func setup(arView: ARView) {
            self.arView = arView

            // ── Pure image tracking (no world tracking) ──
            // Gives the tightest possible lock to the tracked image — the model
            // feels like it's glued to the print in your hand. Tradeoff: when the
            // image goes out of view, tracking drops instantly.
            let config = ARImageTrackingConfiguration()
            config.trackingImages = manager.makeReferenceImages()
            config.maximumNumberOfTrackedImages = manager.flashcards.count

            arView.session.delegate = self
            arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

            // ── Per-frame update subscription ──
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

                // Look up content entity by dictionary, fall back to scene search
                if let content = contentEntities[imgName] {
                    content.transform = Transform(matrix: imageAnchor.transform)
                } else if let root = arView.scene.anchors.first(where: { $0.name == anchorName }),
                          let found = root.findEntity(named: "content") {
                    contentEntities[imgName] = found
                    found.transform = Transform(matrix: imageAnchor.transform)
                }
            }
        }

        // MARK: Image Detected (via delegate)

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            // ARKit calls this on a background thread, but models/managers are @MainActor.
            // Gather the raw anchor data on this thread, then dispatch to main actor for processing.
            var rawAnchors: [(ARImageAnchor, String)] = []
            for anchor in anchors {
                guard let imageAnchor = anchor as? ARImageAnchor,
                      let name = imageAnchor.referenceImage.name else { continue }
                rawAnchors.append((imageAnchor, name))
            }

            Task { @MainActor in
                for (imageAnchor, imgName) in rawAnchors {
                    guard let cardID = UUID(uuidString: imgName),
                          let card = manager.flashcards.first(where: { $0.id == cardID }),
                          let modelUID = card.modelUID
                    else { continue }

                    let anchorName = "fc_\(card.id.uuidString)"

                    // Check if we already have a hidden content entity for this image
                    // (hidden by didRemove when tracking was lost).
                    if let existing = contentEntities[imgName] {
                        // Re-enable it and snap to the current image transform
                        existing.isEnabled = true
                        existing.transform = Transform(matrix: imageAnchor.transform)
                    } else {
                        placeModel(for: card, modelUID: modelUID, imageAnchor: imageAnchor,
                                   anchorName: anchorName, imgName: imgName)
                    }
                }
            }
        }

        /// Capture all gesture-modified model positions and persist them.
        @MainActor
        func saveAllPositions(manager: FlashCardManager) {
            for (imgName, modelEnt) in modelEntities {
                guard let cardID = UUID(uuidString: imgName),
                      manager.flashcards.contains(where: { $0.id == cardID })
                else { continue }

                let avgScale = (modelEnt.scale.x + modelEnt.scale.y + modelEnt.scale.z) / 3
                let q = modelEnt.transform.rotation
                let yaw = atan2(2 * (q.vector.w * q.vector.y + q.vector.z * q.vector.x),
                                1 - 2 * (q.vector.y * q.vector.y + q.vector.x * q.vector.x))
                let degrees = yaw * 180 / .pi

                manager.updateAdjustments(
                    for: cardID,
                    scale: avgScale,
                    rotationDegrees: degrees,
                    verticalOffset: modelEnt.position.y,
                    horizontalOffset: SIMD2<Float>(modelEnt.position.x, modelEnt.position.z)
                )
                print("💾 Saved position for \(cardID.uuidString.prefix(8))")
            }
        }

        /// Recursively install gestures on all ModelEntity descendants.
        private func installGestures(on entity: Entity, arView: ARView) {
            if let me = entity as? ModelEntity {
                arView.installGestures([.scale, .rotation, .translation], for: me)
            }
            for child in entity.children {
                installGestures(on: child, arView: arView)
            }
        }

        // MARK: Place Model

        @MainActor
        func placeModel(for card: FlashCard, modelUID: String,
                        imageAnchor: ARImageAnchor, anchorName: String, imgName: String) {
            guard let arView = arView else { return }

            // ── Root anchor at world origin ──
            // We keep this fixed and update a *child* entity's transform every frame,
            // avoiding the coordinate-system conflicts that happen when you set
            // .transform directly on an AnchorEntity.
            let rootAnchor = AnchorEntity(world: matrix_identity_float4x4)
            rootAnchor.name = anchorName
            arView.scene.addAnchor(rootAnchor)

            // ── Content entity – positioned at the image anchor's current world pose ──
            // This is the entity whose transform we update per frame in onFrameUpdate.
            let contentEntity = Entity()
            contentEntity.name = "content"
            contentEntity.transform = Transform(matrix: imageAnchor.transform)
            rootAnchor.addChild(contentEntity)
            contentEntities[imgName] = contentEntity

            // ── Load real model in background ──
            isLoading = true
            Task { [weak self] in
                guard let self = self else { return }
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
                            errorMessage = "No USDZ format available for this model"
                            isLoading = false; return
                        }
                        let (tempURL, _) = try await URLSession.shared.download(from: url)
                        let cachedURL = try manager.cacheModel(from: tempURL, uid: modelUID)
                        let loaded = try await Entity.load(contentsOf: cachedURL)
                        modelCache[modelUID] = loaded
                        entity = loaded
                    } catch {
                        errorMessage = "Failed to load model: \(error.localizedDescription)"
                        isLoading = false; return
                    }
                }

                if let entity = entity {
                    let clone = entity.clone(recursive: true)
                    clone.scale *= SIMD3<Float>(repeating: card.modelScale)

                    // Apply the user-adjustable Y-axis rotation
                    let userRotationRad = card.modelRotationDegrees * .pi / 180
                    clone.transform.rotation *= simd_quatf(angle: userRotationRad, axis: [0, 1, 0])

                    // Apply vertical offset
                    clone.position.y += card.modelVerticalOffset

                    // Auto-scale tiny models
                    let bounds = clone.visualBounds(relativeTo: nil)
                    if bounds.boundingRadius < 0.001 { clone.scale *= 0.5 }

                    // Apply any saved horizontal offset
                    clone.position.x = card.modelHorizontalOffset.x
                    clone.position.z = card.modelHorizontalOffset.y

                    contentEntity.addChild(clone)
                    modelEntities[imgName] = clone

                    // Enable live gestures on every ModelEntity in the hierarchy.
                    // USDZ files typically load with an Entity root and ModelEntity children,
                    // so casting the root alone would fail.
                    clone.generateCollisionShapes(recursive: true)
                    installGestures(on: clone, arView: arView)

                    print("✅ Model placed with gestures")
                }
                isLoading = false
            }
        }
    }
}

// MARK: - ARSessionDelegate conformance

extension ARFlashCardContainer.Coordinator: ARSessionDelegate {
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        // ARKit removed an anchor (image out of view for too long).
        // Hide the content entity instead of destroying it — the model stays
        // loaded in memory, and if the image is re-detected we skip the
        // expensive re-download and just show it again at the new position.
        for anchor in anchors {
            guard let imageAnchor = anchor as? ARImageAnchor,
                  let imgName = imageAnchor.referenceImage.name,
                  let content = contentEntities[imgName]
            else { continue }

            // Mark as removed so didAdd knows to re-attach rather than skip
            content.isEnabled = false
        }
    }
}
