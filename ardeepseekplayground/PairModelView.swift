import SwiftUI

/// Lets the user search Sketchfab and pick a 3D model to pair with a flashcard.
struct PairModelView: View {
    let card: FlashCard
    @ObservedObject var manager: FlashCardManager
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var results: [SketchfabAPI.SearchResult.Model] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let api = SketchfabAPI()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    TextField("Search for a 3D model\u{2026}", text: $searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(search)
                    Button("Search", action: search)
                        .disabled(searchQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
                .background(.ultraThinMaterial)

                if isLoading {
                    Spacer()
                    ProgressView("Searching\u{2026}")
                    Spacer()
                } else if results.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "Search Sketchfab",
                        systemImage: "magnifyingglass",
                        description: Text("Find a 3D model to attach to your flashcard")
                    )
                    Spacer()
                } else {
                    List(results) { model in
                        Button {
                            pairModel(model)
                        } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: URL(string: model.thumbnails.images.first?.url ?? "")) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Color.gray
                                }
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading) {
                                    Text(model.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                }

                                Spacer()

                                Image(systemName: "link.badge.plus")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pair a Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func search() {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                results = try await api.search(query: searchQuery)
            } catch {
                errorMessage = "Search failed: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    private func pairModel(_ model: SketchfabAPI.SearchResult.Model) {
        manager.pairModel(to: card.id, modelUID: model.uid, modelName: model.name)
        dismiss()
    }
}
