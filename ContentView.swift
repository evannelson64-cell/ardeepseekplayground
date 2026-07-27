import SwiftUI
import RealityKit
import ARKit

struct ContentView: View {
    @StateObject private var vm = SearchViewModel()
    @State private var placedEntity: ModelEntity?

    var body: some View {
        ZStack(alignment: .top) {
            ARViewContainer(placedEntity: $placedEntity)
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
                ProgressView("Downloading…")
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
        .onChange(of: vm.selectedEntity) { oldValue, newValue in
            if let entity = newValue {
                placedEntity = entity
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @Binding var placedEntity: ModelEntity?

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        arView.session.run(config)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        let parent: ARViewContainer
        init(_ parent: ARViewContainer) { self.parent = parent }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView = recognizer.view as? ARView,
                  let model = parent.placedEntity?.clone(recursive: true) else { return }

            let location = recognizer.location(in: arView)
            let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .horizontal)
            if let firstHit = results.first {
                let anchor = AnchorEntity(world: firstHit.worldTransform)
                model.generateCollisionShapes(recursive: true)
                anchor.addChild(model)
                arView.scene.addAnchor(anchor)
                arView.installGestures([.scale, .translation], for: model)
            }
        }
    }
}
