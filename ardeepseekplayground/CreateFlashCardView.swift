import SwiftUI
import AVFoundation

/// Full-screen creation flow: take a photo → crop → pair a 3D model.
/// Uses a custom AVFoundation camera view so it works independently of ARKit.
struct CreateFlashCardView: View {
    @ObservedObject var manager: FlashCardManager
    @Environment(\.dismiss) private var dismiss

    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var showCrop = false
    @State private var showPairing = false
    @State private var newCard: FlashCard?

    var body: some View {
        NavigationStack {
            takePhotoView
                .navigationTitle("New Flash Card")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { image in
                capturedImage = image
                showCrop = true
            }
        }
        .fullScreenCover(isPresented: $showCrop) {
            if let image = capturedImage {
                ImageCropView(image: image) { croppedImage in
                    if let card = manager.createFlashCard(image: croppedImage) {
                        newCard = card
                        showPairing = true
                    }
                }
            }
        }
        .sheet(isPresented: $showPairing) {
            if let card = newCard {
                PairModelView(card: card, manager: manager)
            }
        }
        .onChange(of: showPairing) { _, isShowing in
            if !isShowing { dismiss() }
        }
    }

    // MARK: - Take Photo View

    private var takePhotoView: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.1))
                    .frame(width: 100, height: 100)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 44))
                    .foregroundColor(.blue)
            }

            // Instructions
            VStack(spacing: 12) {
                Text("Take a picture of your flashcard")
                    .font(.title3.bold())

                Text("Point your camera at a photo, sticker, or any flat image you want to track in AR.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Tips
            VStack(alignment: .leading, spacing: 8) {
                tipRow(icon: "sparkles", text: "Good lighting helps ARKit detect the image faster")
                tipRow(icon: "rectangle.and.hand.point.up.left", text: "Keep the image flat and well-framed")
                tipRow(icon: "paintpalette", text: "Images with contrast & detail work best")
            }
            .padding()
            .background(.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 32)

            Spacer()

            // Take Photo button
            Button {
                showCamera = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.title3)
                    Text("Open Camera")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 32)
        }
    }

    // MARK: - Helpers

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
