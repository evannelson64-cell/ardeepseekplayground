
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

    // MARK: - Search

    func search() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let results = try await api.search(query: query)
                let filtered = await filterModelsWithUSDZ(results)
                self.models = filtered
            } catch {
                self.errorMessage = "Search failed: \(error.localizedDescription)"
            }
            self.isLoading = false
        }
    }

    private func filterModelsWithUSDZ(_ models: [SketchfabAPI.SearchResult.Model]) async -> [SketchfabAPI.SearchResult.Model] {
        var filtered: [SketchfabAPI.SearchResult.Model] = []
        await withTaskGroup(of: (SketchfabAPI.SearchResult.Model, Bool)?.self) { group in
            for model in models {
                group.addTask {
                    do {
                        let info = try await self.api.downloadInfo(for: model.uid)
                        return (model, info.usdz != nil)
                    } catch {
                        return nil
                    }
                }
            }
            for await result in group {
                if let (model, hasUSDZ) = result, hasUSDZ {
                    filtered.append(model)
                }
            }
        }
        return filtered
    }

    // MARK: - Download & Load

    func selectModel(_ model: SketchfabAPI.SearchResult.Model) {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let info = try await api.downloadInfo(for: model.uid)
                guard let usdz = info.usdz else {
                    throw NSError(domain: "No USDZ format available", code: 0)
                }

                guard let downloadURL = URL(string: usdz.url) else {
                    throw NSError(domain: "Invalid download URL", code: 0)
                }

                // Download the file
                let (tempURL, response) = try await URLSession.shared.download(from: downloadURL)

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    let body = try? String(contentsOf: tempURL, encoding: .utf8)
                    throw NSError(domain: "Download failed with status \(httpResponse.statusCode): \(body ?? "")", code: httpResponse.statusCode)
                }

                // Rename to .usdz so RealityKit can recognise it
                let usdzURL = tempURL.appendingPathExtension("usdz")
                try? FileManager.default.removeItem(at: usdzURL)
                try FileManager.default.moveItem(at: tempURL, to: usdzURL)

                // Optional: verify file size (for debugging)
                if FileManager.default.fileExists(atPath: usdzURL.path) {
                    let attrs = try FileManager.default.attributesOfItem(atPath: usdzURL.path)
                    print("✅ USDZ file size: \(attrs[.size] ?? 0) bytes")
                } else {
                    throw NSError(domain: "File missing after rename", code: 0)
                }

                // Load as a generic Entity first – no force cast
                let entity = try await Entity.load(contentsOf: usdzURL)

                // Depending on the actual type, we may need to wrap it
                if let modelEntity = entity as? ModelEntity {
                    self.selectedEntity = modelEntity
                } else {
                    // If the root is not a ModelEntity (e.g. an AnchorEntity), wrap it
                    let wrapper = ModelEntity()
                    wrapper.addChild(entity)
                    entity.position = .zero
                    self.selectedEntity = wrapper
                }

                // Clean up the temporary .usdz file
                try? FileManager.default.removeItem(at: usdzURL)
            } catch {
                print("❌ Download/load error: \(error)")
                self.errorMessage = "Download failed: \(error.localizedDescription)"
            }
            self.isLoading = false
        }
    }
}
