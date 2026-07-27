import SwiftUI

/// Main list of flashcards – capture, pair, and launch AR.
struct FlashCardListView: View {
    @StateObject private var manager = FlashCardManager()
    @State private var showCamera = false
    @State private var showPairing = false
    @State private var showAR = false
    @State private var selectedCard: FlashCard?
    @State private var justCreatedCard: FlashCard?

    var body: some View {
        NavigationStack {
            Group {
                if manager.flashcards.isEmpty {
                    ContentUnavailableView(
                        "No Flash Cards",
                        systemImage: "camera.viewfinder",
                        description: Text("Capture a photo to create a trackable flashcard")
                    )
                } else {
                    List {
                        ForEach(manager.flashcards) { card in
                            FlashCardRow(card: card, manager: manager)
                                .swipeActions(edge: .trailing) {
                                    Button("Delete", role: .destructive) {
                                        manager.deleteFlashCard(card.id)
                                    }
                                }
                                .contextMenu {
                                    Button {
                                        selectedCard = card
                                        showPairing = true
                                    } label: {
                                        Label("Pair a 3D Model", systemImage: "link")
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
            .navigationTitle("Flash Cards")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCamera = true
                    } label: {
                        Image(systemName: "plus")
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
                if let card = manager.createFlashCard(image: image) {
                    justCreatedCard = card
                    selectedCard = card
                    // Show pairing sheet after a tiny delay so the sheet transition completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showPairing = true
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
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.gray.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay(Image(systemName: "photo"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(card.modelName ?? "No model paired")
                    .font(.headline)
                    .foregroundColor(card.modelName != nil ? .primary : .secondary)

                Text("\(Int(card.imagePhysicalWidth * 100)) cm wide")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(card.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if card.modelUID == nil {
                Image(systemName: "link.badge.plus")
                    .foregroundColor(.blue)
                    .font(.title3)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
    }
}
