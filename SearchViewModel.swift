import SwiftUI
import RealityKit

@MainActor
class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var models: [SketchfabAPI.SearchResult.Model] = []
    @Published var selectedEntity: ModelEntity?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = SketchfabAPI()

    func search() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            do {
                let results = try await api.search(query: query)
                self.models = results
            } catch {
                self.errorMessage = "Search failed: \(error.localizedDescription)"
            }
        }
    }

    func selectModel(_ model: SketchfabAPI.SearchResult.Model) {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let info = try await api.downloadInfo(for: model.uid)
                guard let format = info.usdz ?? info.gltf else {
                    throw URLError(.badServerResponse)
                }
                let downloadURL = URL(string: format.url)!
                let (tempURL, _) = try await URLSession.shared.download(from: downloadURL)

                let entity: ModelEntity
                if tempURL.pathExtension.lowercased() == "usdz" {
                    entity = try await ModelEntity.load(contentsOf: tempURL) as! ModelEntity
                } else {
                    throw NSError(domain: "Only USDZ models supported in this demo", code: 0)
                }
                self.selectedEntity = entity
            } catch {
                self.errorMessage = "Download failed: \(error.localizedDescription)"
            }
            self.isLoading = false
        }
    }
}
