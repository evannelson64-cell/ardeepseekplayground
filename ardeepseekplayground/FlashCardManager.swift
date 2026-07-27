import UIKit
import ARKit
import RealityKit

// MARK: - FlashCard Model

struct FlashCard: Codable, Identifiable {
    var id = UUID()
    let imageFileName: String
    let imagePhysicalWidth: Float         // metres – ARKit needs the real-world width
    var modelUID: String?
    var modelName: String?
    let createdAt: Date

    init(imageFileName: String, imagePhysicalWidth: Float = 0.15) {
        self.id = UUID()
        self.imageFileName = imageFileName
        self.imagePhysicalWidth = imagePhysicalWidth
        self.createdAt = Date()
    }
}

// MARK: - Manager

@MainActor
class FlashCardManager: ObservableObject {
    @Published var flashcards: [FlashCard] = []

    private let fileManager = FileManager.default
    private let documentsDir: URL

    private var imagesDir: URL {
        documentsDir.appendingPathComponent("flashcard_images", isDirectory: true)
    }

    private var modelsDir: URL {
        documentsDir.appendingPathComponent("flashcard_models", isDirectory: true)
    }

    private var metadataURL: URL {
        documentsDir.appendingPathComponent("flashcards.json")
    }

    init() {
        documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        try? fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Image I/O

    func saveFlashCardImage(_ image: UIImage) -> String? {
        let fileName = "fc_\(UUID().uuidString).png"
        let url = imagesDir.appendingPathComponent(fileName)
        guard let data = image.pngData() else { return nil }
        do {
            try data.write(to: url)
            return fileName
        } catch {
            print("Failed to save image: \(error)")
            return nil
        }
    }

    func loadImage(named fileName: String) -> UIImage? {
        let url = imagesDir.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - CRUD

    func createFlashCard(image: UIImage, physicalWidth: Float = 0.15) -> FlashCard? {
        guard let fileName = saveFlashCardImage(image) else { return nil }
        let card = FlashCard(imageFileName: fileName, imagePhysicalWidth: physicalWidth)
        flashcards.append(card)
        save()
        return card
    }

    func pairModel(to cardID: UUID, modelUID: String, modelName: String) {
        guard let idx = flashcards.firstIndex(where: { $0.id == cardID }) else { return }
        flashcards[idx].modelUID = modelUID
        flashcards[idx].modelName = modelName
        save()
    }

    func deleteFlashCard(_ id: UUID) {
        guard let card = flashcards.first(where: { $0.id == id }) else { return }
        // Remove the image file
        let imageURL = imagesDir.appendingPathComponent(card.imageFileName)
        try? fileManager.removeItem(at: imageURL)
        // Remove any cached model file
        if let uid = card.modelUID {
            let modelURL = modelsDir.appendingPathComponent("\(uid).usdz")
            try? fileManager.removeItem(at: modelURL)
        }
        flashcards.removeAll { $0.id == id }
        save()
    }

    // MARK: - ARKit Reference Images

    /// Build a set of ARReferenceImage objects from all saved flashcards.
    /// Each reference image gets its name set to the flashcard's UUID string
    /// so we can look it up when ARKit detects it.
    func makeReferenceImages() -> Set<ARReferenceImage> {
        var refImages = Set<ARReferenceImage>()
        for card in flashcards {
            guard let uiImage = loadImage(named: card.imageFileName),
                  let cgImage = uiImage.cgImage else { continue }
            let refImage = ARReferenceImage(cgImage, orientation: .up, physicalWidth: card.imagePhysicalWidth)
            refImage.name = card.id.uuidString
            refImages.insert(refImage)
        }
        return refImages
    }

    // MARK: - Model Cache

    func cachedModelURL(for uid: String) -> URL? {
        let url = modelsDir.appendingPathComponent("\(uid).usdz")
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func cacheModel(from tempURL: URL, uid: String) throws -> URL {
        let dest = modelsDir.appendingPathComponent("\(uid).usdz")
        try? fileManager.removeItem(at: dest)
        try fileManager.moveItem(at: tempURL, to: dest)
        return dest
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([FlashCard].self, from: data)
        else { return }
        flashcards = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(flashcards) else { return }
        try? data.write(to: metadataURL)
    }
}
