import SwiftUI

/// List of flashcards – view, pair/unpair, and manage.
struct FlashCardListView: View {
    @ObservedObject var manager: FlashCardManager
    @Environment(\.dismiss) private var dismiss
    @State private var showPairingSheet = false
    @State private var selectedCard: FlashCard?

    var body: some View {
        NavigationStack {
            cardList
                .navigationTitle("My Flash Cards")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .sheet(isPresented: $showPairingSheet) {
            if let card = selectedCard {
                PairModelView(card: card, manager: manager)
            }
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
                                showPairingSheet = true
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
