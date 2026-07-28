
import SwiftUI

/// Single-screen layout: AR world tracking (Place) + create flashcard button.
struct ContentView: View {
    @StateObject private var flashCardManager = FlashCardManager()
    @State private var showCreateSheet = false
    @State private var showFlashCardAR = false
    @State private var showFlashCardList = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Existing AR place view (always active since it's the only screen)
            PlaceView(isActiveTab: true)
                .edgesIgnoringSafeArea(.all)

            // Bottom-right button panel
            VStack(spacing: 12) {
                // Flash Cards list button (appears when cards exist)
                if !flashCardManager.flashcards.isEmpty {
                    Button {
                        showFlashCardList = true
                    } label: {
                        Label("\(flashCardManager.flashcards.count) Cards", systemImage: "rectangle.stack")
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }

                    Button {
                        showFlashCardAR = true
                    } label: {
                        Label("AR View", systemImage: "arkit")
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }

                // Main create button
                Button {
                    showCreateSheet = true
                } label: {
                    Label("Create Flash Card", systemImage: "camera.fill")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(.blue)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(radius: 4)
                }
            }
            .padding()
        }
        .fullScreenCover(isPresented: $showCreateSheet) {
            CreateFlashCardView(manager: flashCardManager)
        }
        .fullScreenCover(isPresented: $showFlashCardAR) {
            ARFlashCardView(manager: flashCardManager)
        }
        .sheet(isPresented: $showFlashCardList) {
            FlashCardListView(manager: flashCardManager)
        }
    }
}
