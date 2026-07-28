import SwiftUI
import AVFoundation

/// Full-screen creation flow: take a photo → crop → pair a 3D model.
/// Shows clear instructions at each step so the user always knows what to do.
struct CreateFlashCardView: View {
    @ObservedObject var manager: FlashCardManager
    @Environment(\.dismiss) private var dismiss

    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var showCrop = false
    @State private var showPairing = false
    @State private var newCard: FlashCard?
    @State private var cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)
    @State private var cameraAuthorized = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !cameraAvailable {
                    // No camera available (simulator)
                    noCameraView
                } else if capturedImage == nil {
                    // Step 1: Take a photo
                    takePhotoView
                }
            }
            .navigationTitle("New Flash Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                checkCameraAuthorization()
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
                // When pairing sheet is dismissed, we're done
                if !isShowing {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Camera Authorization

    private func checkCameraAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAuthorized = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraAuthorized = granted
                }
            }
        case .denied, .restricted:
            cameraAuthorized = false
        @unknown default:
            cameraAuthorized = false
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
                if cameraAuthorized {
                    showCamera = true
                } else {
                    checkCameraAuthorization()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.title3)
                    Text(cameraAuthorized ? "Take Photo" : "Allow Camera Access")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(cameraAuthorized ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)

            if !cameraAuthorized {
                Text("Camera access is needed to photograph your flashcard. You can enable it in Settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer().frame(height: 16)
        }
    }

    // MARK: - No Camera View (simulator)

    private var noCameraView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Camera Not Available")
                .font(.title3.bold())

            Text("This device doesn't have a camera. Run on a physical iPhone to create flashcards.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
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
