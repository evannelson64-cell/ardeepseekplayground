
import SwiftUI

/// Main tab navigation: Place mode (world tracking) and Flash Cards mode (image tracking).
struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            PlaceView()
                .tabItem {
                    Label("Place", systemImage: "viewfinder")
                }
                .tag(0)

            FlashCardListView()
                .tabItem {
                    Label("Flash Cards", systemImage: "rectangle.on.rectangle")
                }
                .tag(1)
        }
        .tint(.blue)
    }
}
