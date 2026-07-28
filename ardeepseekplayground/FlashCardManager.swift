import UIKit
import ARKit
import RealityKit

// MARK: - FlashCard Model

struct FlashCard: Identifiable {
    var id = UUID()
    let imageFileName: String
    let imagePhysicalWidth: Float         // metres – ARKit needs the real-world width
    var modelUID: String?
    var modelName: String?
    var modelScale: Float = 1.0           // relative to original size
    var modelRotationDegrees: Float = 0   // around Y axis
    var modelVerticalOffset: Float = 0    // metres above the tracked image
    var modelHorizontalOffset: SIMD2<Float> = .zero  // x,z offset from image center
    let createdAt: Date

    init(imageFileName: String, imagePhysicalWidth: Float = 0.15,
         modelScale: Float = 1.0, modelRotationDegrees: Float = 0,
         modelVerticalOffset: Float = 0,
         modelHorizontalOffset: SIMD2<Float> = .zero) {
        self.id = UUID()
        self.imageFileName = imageFileName
        self.imagePhysicalWidth = imagePhysicalWidth
        self.modelScale = modelScale
        self.modelRotationDegrees = modelRotationDegrees
        self.modelVerticalOffset = modelVerticalOffset
        self.modelHorizontalOffset = modelHorizontalOffset
        self.createdAt = Date()
    }
}

// MARK: - Codable (backward-compatible with cards saved before modelHorizontalOffset)

extension FlashCard: Codable {
    enum CodingKeys: String, CodingKey {
        case id, imageFileName, imagePhysicalWidth, modelUID, modelName
        case modelScale, modelRotationDegrees, modelVerticalOffset
        case modelHorizontalOffset, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        imageFileName = try c.decode(String.self, forKey: .imageFileName)
        imagePhysicalWidth = try c.decodeIfPresent(Float.self, forKey: .imagePhysicalWidth) ?? 0.15
        modelUID = try c.decodeIfPresent(String.self, forKey: .modelUID)
        modelName = try c.decodeIfPresent(String.self, forKey: .modelName)
        modelScale = try c.decodeIfPresent(Float.self, forKey: .modelScale) ?? 1.0
        modelRotationDegrees = try c.decodeIfPresent(Float.self, forKey: .modelRotationDegrees) ?? 0
        modelVerticalOffset = try c.decodeIfPresent(Float.self, forKey: .modelVerticalOffset) ?? 0
        modelHorizontalOffset = try c.decodeIfPresent(SIMD2<Float>.self, forKey: .modelHorizontalOffset) ?? .zero
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(imageFileName, forKey: .imageFileName)
        try c.encode(imagePhysicalWidth, forKey: .imagePhysicalWidth)
        try c.encodeIfPresent(modelUID, forKey: .modelUID)
        try c.encodeIfPresent(modelName, forKey: .modelName)
        try c.encode(modelScale, forKey: .modelScale)
        try c.encode(modelRotationDegrees, forKey: .modelRotationDegrees)
        try c.encode(modelVerticalOffset, forKey: .modelVerticalOffset)
        try c.encode(modelHorizontalOffset, forKey: .modelHorizontalOffset)
        try c.encode(createdAt, forKey: .createdAt)
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

    func updateAdjustments(for cardID: UUID, scale: Float, rotationDegrees: Float, verticalOffset: Float, horizontalOffset: SIMD2<Float> = .zero) {
        guard let idx = flashcards.firstIndex(where: { $0.id == cardID }) else { return }
        flashcards[idx].modelScale = scale
        flashcards[idx].modelRotationDegrees = rotationDegrees
        flashcards[idx].modelVerticalOffset = verticalOffset
        flashcards[idx].modelHorizontalOffset = horizontalOffset
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
            let refImage = ARReferenceImage(cgImage, orientation: .up, physicalWidth: CGFloat(card.imagePhysicalWidth))
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

    // MARK: - Export

    /// Creates a temporary directory containing the JSON metadata + all images + all cached models,
    /// then zips it so the user can share/backup the deck.
    func exportDeck() -> URL? {
        let exportDir = fileManager.temporaryDirectory.appendingPathComponent("FlashCardExport_\(UUID().uuidString)")
        try? fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)

        // Copy metadata
        let metaDest = exportDir.appendingPathComponent("flashcards.json")
        try? fileManager.copyItem(at: metadataURL, to: metaDest)

        // Copy images
        let imgDest = exportDir.appendingPathComponent("images")
        try? fileManager.createDirectory(at: imgDest, withIntermediateDirectories: true)
        for card in flashcards {
            let src = imagesDir.appendingPathComponent(card.imageFileName)
            let dst = imgDest.appendingPathComponent(card.imageFileName)
            try? fileManager.copyItem(at: src, to: dst)
        }

        // Copy cached models
        let modelDest = exportDir.appendingPathComponent("models")
        try? fileManager.createDirectory(at: modelDest, withIntermediateDirectories: true)
        for card in flashcards {
            guard let uid = card.modelUID,
                  let src = cachedModelURL(for: uid) else { continue }
            let dst = modelDest.appendingPathComponent("\(uid).usdz")
            try? fileManager.copyItem(at: src, to: dst)
        }

        // Zip it
        let zipURL = fileManager.temporaryDirectory.appendingPathComponent("FlashCardDeck_\(UUID().uuidString).zip")
        let coordinator = NSFileCoordinator()
        var error: NSError?
        var success = false
        coordinator.coordinate(readingItemAt: exportDir, options: [.forUploading], error: &error) { zipSrc in
            try? fileManager.moveItem(at: zipSrc, to: zipURL)
            success = true
        }
        // Clean up export dir
        try? fileManager.removeItem(at: exportDir)

        return success ? zipURL : nil
    }
}
