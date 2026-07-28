import SwiftUI

/// Main list of flashcards – capture, pair, and launch AR.
struct FlashCardListView: View {
    @StateObject private var manager = FlashCardManager()
    @State private var showCamera = false
    @State private var showCrop = false
    @State private var showPairing = false
    @State private var showAR = false
    @State private var capturedImage: UIImage?
    @State private var selectedCard: FlashCard?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if manager.flashcards.isEmpty {
                    emptyState
                } else {
                    cardList
                }
            }
            .navigationTitle("Flash Cards")
            .toolbar {
                if !manager.flashcards.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Add Flashcard", systemImage: "plus")
                        }
                    }
                }
            }

            // Bottom bar – View in AR
            if !manager.flashcards.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                    Button {
                        showAR = true
                    } label: {
                        Label("View in AR", systemImage: "arkit")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.blue)
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraCaptureView { image in
                capturedImage = image
                showCrop = true
            }
        }
        .fullScreenCover(isPresented: $showCrop) {
            if let image = capturedImage {
                ImageCropView(image: image) { croppedImage in
                    if let card = manager.createFlashCard(image: croppedImage) {
                        selectedCard = card
                        // Show pairing sheet after sheet transition
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showPairing = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showPairing) {
            if let card = selectedCard {
                PairModelView(card: card, manager: manager)
            }
        }
        .fullScreenCover(isPresented: $showAR) {
            ARFlashCardView(manager: manager)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(.blue)

            VStack(spacing: 8) {
                Text("AR Flashcards")
                    .font(.title2.bold())
                Text("Create your first one!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                stepRow(number: "1", icon: "camera.fill",     text: "Take a photo of a picture or object")
                stepRow(number: "2", icon: "crop",            text: "Crop to the area you want tracked")
                stepRow(number: "3", icon: "magnifyingglass", text: "Pick a 3D model from Sketchfab")
                stepRow(number: "4", icon: "arkit",           text: "Point your camera at the photo and watch it come to life!")
            }
            .padding(.horizontal, 32)

            Button {
                showCamera = true
            } label: {
                Label("Take a Photo", systemImage: "camera.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    private func stepRow(number: String, icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.1))
                    .frame(width: 32, height: 32)
                Text(number)
                    .font(.caption.bold())
                    .foregroundColor(.blue)
            }
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 16)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Card List

    private var cardList: some View {
        List {
            ForEach(manager.flashcards) { card in
                FlashCardRow(card: card, manager: manager)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            manager.deleteFlashCard(card.id)
                        }
                    }
                    .contextMenu {
                        if card.modelUID == nil {
                            Button {
                                selectedCard = card
                                showPairing = true
                            } label: {
                                Label("Pair a 3D Model", systemImage: "link")
                            }
                        }
                        Button(role: .destructive) {
                            manager.deleteFlashCard(card.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }
}

// MARK: - Row

struct FlashCardRow: View {
    let card: FlashCard
    @ObservedObject var manager: FlashCardManager

    var body: some View {
        HStack(spacing: 16) {
            // Thumbnail of the captured photo
            if let image = manager.loadImage(named: card.imageFileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.gray.opacity(0.3))
                    .frame(width: 64, height: 64)
                    .overlay(Image(systemName: "photo"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(card.modelName ?? "No model paired")
                    .font(.headline)
                    .foregroundColor(card.modelName != nil ? .primary : .secondary)

                HStack(spacing: 4) {
                    Image(systemName: card.modelUID != nil ? "checkmark.circle.fill" : "link.badge.plus")
                        .foregroundColor(card.modelUID != nil ? .green : .blue)
                        .font(.caption)
                    Text(card.modelUID != nil ? "Paired with 3D model" : "Tap & hold to pair a 3D model")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if card.modelUID == nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
