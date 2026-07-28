import SwiftUI
import RealityKit
import ARKit

/// The original "Search Sketchfab & place on detected planes" view,
/// extracted so ContentView can use a TabView.
struct PlaceView: View {
    let isActiveTab: Bool
    @StateObject private var vm = SearchViewModel()
    @State private var placedEntity: ModelEntity?

    var body: some View {
        ZStack(alignment: .top) {
            PlaceARViewContainer(placedEntity: $placedEntity, isActive: isActiveTab)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                HStack {
                    TextField("Search Sketchfab...", text: $vm.query)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit { vm.search() }
                    Button("Search") { vm.search() }
                        .padding(.horizontal, 4)
                }
                .padding()
                .background(.ultraThinMaterial)

                if !vm.models.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(vm.models) { model in
                                Button {
                                    vm.selectModel(model)
                                } label: {
                                    VStack {
                                        AsyncImage(url: URL(string: model.thumbnails.images.first?.url ?? "")) { image in
                                            image.resizable().scaledToFill()
                                        } placeholder: {
                                            Color.gray
                                        }
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                        Text(model.name)
                                            .font(.caption)
                                            .lineLimit(2)
                                            .frame(width: 80)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .background(.ultraThinMaterial)
                }

                Spacer()
            }

            if vm.isLoading {
                ProgressView("Downloading\u{2026}")
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Error", isPresented: .constant(vm.errorMessage != nil)) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .onChange(of: vm.selectedEntity) { _, newValue in
            if let entity = newValue {
                placedEntity = entity
                print("✅ placedEntity updated with new model")
            }
        }
    }
}

// MARK: - AR View (World Tracking)

struct PlaceARViewContainer: UIViewRepresentable {
    @Binding var placedEntity: ModelEntity?
    let isActive: Bool

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        arView.session.run(config)

        // Coaching overlay to help the user find a plane
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coachingOverlay.session = arView.session
        coachingOverlay.goal = .horizontalPlane
        arView.addSubview(coachingOverlay)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        if isActive {
            // Resume if paused – we track state via the coordinator
            if context.coordinator.isPaused {
                let config = ARWorldTrackingConfiguration()
                config.planeDetection = [.horizontal]
                uiView.session.run(config, options: .resetTracking)
                context.coordinator.isPaused = false
            }
        } else {
            uiView.session.pause()
            context.coordinator.isPaused = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        let parent: PlaceARViewContainer
        var isPaused = false
        init(_ parent: PlaceARViewContainer) { self.parent = parent }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView = recognizer.view as? ARView else {
                print("❌ Tap not in ARView")
                return
            }

            guard let model = parent.placedEntity else {
                print("❌ No placedEntity available \u{2013} download a model first")
                return
            }

            let location = recognizer.location(in: arView)
            let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .horizontal)

            guard let firstHit = results.first else {
                print("❌ Raycast missed \u{2013} move the device to detect a horizontal surface")
                return
            }

            let clone = model.clone(recursive: true)
            clone.generateCollisionShapes(recursive: true)

            // If the model is extremely tiny, scale it up so it's visible
            if clone.visualBounds(relativeTo: nil).boundingRadius < 0.01 {
                clone.scale = SIMD3<Float>(0.5, 0.5, 0.5)
                print("ℹ️ Model was tiny \u{2013} scaled up to 0.5")
            }

            let anchor = AnchorEntity(world: firstHit.worldTransform)
            anchor.addChild(clone)
            arView.scene.addAnchor(anchor)

            // Enable pinch-to-resize, pan-to-move, and two-finger rotation
            arView.installGestures([.scale, .translation, .rotation], for: clone)

            print("✅ Model placed with full gestures (scale, translate, rotate)")
        }
    }
}
