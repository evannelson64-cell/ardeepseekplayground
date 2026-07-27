import Foundation

struct SketchfabAPI {
    // Replace with your personal token from https://sketchfab.com/settings/password
    static let downloadToken = "ce59b0bcfc124869abd9929b5d7210d9"
    // Public search – no auth required
    func search(query: String) async throws -> [SearchResult.Model] {
        var components = URLComponents(string: "https://api.sketchfab.com/v3/search")!
        components.queryItems = [
            URLQueryItem(name: "type", value: "models"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: "7"),
            URLQueryItem(name: "downloadable", value: "true")
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let result = try JSONDecoder().decode(SearchResult.self, from: data)
        return result.results
    }

    // Download URL for a model (requires token)
    func downloadInfo(for uid: String) async throws -> DownloadInfo {
        let url = URL(string: "https://api.sketchfab.com/v3/models/\(uid)/download")!
        var request = URLRequest(url: url)
        request.setValue("Token \(Self.downloadToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(DownloadInfo.self, from: data)
    }

    // Nested data models – now they live inside SketchfabAPI
    struct SearchResult: Decodable {
        let results: [Model]
        struct Model: Decodable, Identifiable {
            let uid: String
            let name: String
            let thumbnails: Thumbnails
            var id: String { uid }
            struct Thumbnails: Decodable {
                let images: [ImageInfo]
                struct ImageInfo: Decodable { let url: String }
            }
        }
    }

    struct DownloadInfo: Decodable {
        let gltf: FormatInfo?
        let usdz: FormatInfo?
        struct FormatInfo: Decodable { let url: String }
    }
}
