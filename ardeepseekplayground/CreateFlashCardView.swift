import SwiftUI

/// Full-screen creation flow: take a photo → crop → pair a 3D model.
/// Crop is shown inline (not a separate presented view) to avoid presentation issues.
struct CreateFlashCardView: View {
    @ObservedObject var manager: FlashCardManager
    @Environment(\.dismiss) private var dismiss

    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var croppedPreviewImage: UIImage?
    @State private var showPairing = false
    @State private var showAdjust = false
    @State private var showGlueView = false
    @State private var newCard: FlashCard?

    /// We show either the instruction page, crop page, or glue page.
    enum Step { case instructions, crop, preview, glue }
    @State private var step: Step = .instructions

    var body: some View {
        NavigationStack {
            ZStack {
                switch step {
                case .instructions:
                    instructionsView
                        .transition(.opacity)
                case .crop:
                    if let image = capturedImage {
                        inlineCropView(image: image)
                            .transition(.opacity)
                    }
                case .preview:
                    if let image = croppedPreviewImage {
                        cropPreviewView(image: image)
                            .transition(.opacity)
                    }
                case .glue:
                    // Refresh card from manager — PairModelView updated it in-place
                    if let cardID = newCard?.id,
                       let refreshed = manager.flashcards.first(where: { $0.id == cardID }),
                       let img = capturedImage, let uid = refreshed.modelUID {
                        GlueView(image: img, modelUID: uid, card: refreshed, manager: manager)
                            .transition(.opacity)
                    }
                }
            }
            .animation(.default, value: step)
            .navigationTitle(step == .instructions ? "New Flash Card" : step == .crop ? "Crop Tracking Area" : step == .preview ? "Preview" : "Position Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if step == .crop {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use Photo") {
                            confirmCrop()
                        }
                        .fontWeight(.semibold)
                    }
                }
                if step == .preview {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Looks Good!") {
                            proceedFromPreview()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { image in
                capturedImage = image
                showCamera = false
                // Switch to the inline crop view
                step = .crop
            }
        }
        .sheet(isPresented: $showPairing) {
            if let card = newCard {
                PairModelView(card: card, manager: manager)
            }
        }
        .sheet(isPresented: $showAdjust) {
            if let card = newCard {
                ModelAdjustView(card: card, manager: manager)
            }
        }
        .onChange(of: showPairing) { _, isShowing in
            if !isShowing, newCard != nil {
                withAnimation { step = .glue }
            }
        }
    }

    // MARK: - Instructions

    private var instructionsView: some View {
        VStack(spacing: 32) {
            Spacer()
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.1))
                    .frame(width: 100, height: 100)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 44))
                    .foregroundColor(.blue)
            }
            VStack(spacing: 12) {
                Text("Take a picture of your flashcard")
                    .font(.title3.bold())
                Text("Point your camera at a photo, sticker, or any flat image you want to track in AR.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
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

    // MARK: - Inline Crop

    @State private var cropRect: CGRect = .init(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    @State private var displaySize: CGSize = .zero
    /// Snapshot of cropRect when a drag begins – prevents cumulative translation jumps.
    @State private var dragAnchor: CGRect? = nil

    private func inlineCropView(image: UIImage) -> some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                let displayW = geo.size.width
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: displayW)
                    .overlay(alignment: .topLeading) {
                        GeometryReader { imgGeo in
                            Color.clear.onAppear {
                                displaySize = imgGeo.size
                            }
                        }
                    }
                    .overlay {
                        if displaySize != .zero {
                            cropOverlay(canvasSize: displaySize)
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Crop Overlay

    private func cropOverlay(canvasSize: CGSize) -> some View {
        let rect = CGRect(
            x: cropRect.origin.x * canvasSize.width,
            y: cropRect.origin.y * canvasSize.height,
            width: cropRect.size.width * canvasSize.width,
            height: cropRect.size.height * canvasSize.height
        )

        return ZStack {
            // Semi-transparent mask
            Color.black.opacity(0.5)
                .overlay(
                    Rectangle()
                        .blendMode(.destinationOut)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                )
                .compositingGroup()

            // Border
            RoundedRectangle(cornerRadius: 4)
                .stroke(.white, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            // Corner handles
            cornerHandle(at: CGPoint(x: rect.minX, y: rect.minY), corner: .topLeft, canvasSize: canvasSize)
            cornerHandle(at: CGPoint(x: rect.maxX, y: rect.minY), corner: .topRight, canvasSize: canvasSize)
            cornerHandle(at: CGPoint(x: rect.minX, y: rect.maxY), corner: .bottomLeft, canvasSize: canvasSize)
            cornerHandle(at: CGPoint(x: rect.maxX, y: rect.maxY), corner: .bottomRight, canvasSize: canvasSize)

            // Drag area in center to move the whole crop
            Color.clear
                .contentShape(Rectangle())
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .gesture(dragCropGesture(canvasSize: canvasSize))
        }
    }

    // MARK: - Drag Gesture Helpers

    /// Dragging the center moves the entire crop rect.
    private func dragCropGesture(canvasSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { val in
                let start = dragAnchor ?? cropRect
                dragAnchor = start
                let dx = val.translation.width / canvasSize.width
                let dy = val.translation.height / canvasSize.height
                var new = start
                new.origin.x = max(0, min(1 - new.width, start.origin.x + dx))
                new.origin.y = max(0, min(1 - new.height, start.origin.y + dy))
                cropRect = new
            }
            .onEnded { _ in dragAnchor = nil }
    }

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    /// Dragging a corner resizes the crop rect from that corner.
    private func cornerHandle(at pos: CGPoint, corner: Corner, canvasSize: CGSize) -> some View {
        Circle()
            .fill(.white)
            .frame(width: 28, height: 28)
            .overlay(Circle().stroke(Color.blue, lineWidth: 2))
            .position(pos)
            .gesture(cornerDragGesture(corner: corner, canvasSize: canvasSize))
    }

    private func cornerDragGesture(corner: Corner, canvasSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { val in
                let start = dragAnchor ?? cropRect
                dragAnchor = start
                let dx = val.translation.width / canvasSize.width
                let dy = val.translation.height / canvasSize.height
                var new = start

                switch corner {
                case .topLeft:
                    new.origin.x = max(0, min(start.maxX - 0.05, start.origin.x + dx))
                    new.origin.y = max(0, min(start.maxY - 0.05, start.origin.y + dy))
                    new.size.width  = start.maxX - new.origin.x
                    new.size.height = start.maxY - new.origin.y
                case .topRight:
                    new.origin.y = max(0, min(start.maxY - 0.05, start.origin.y + dy))
                    new.size.width  = max(0.05, min(1 - new.origin.x, start.size.width + dx))
                    new.size.height = start.maxY - new.origin.y
                case .bottomLeft:
                    new.origin.x = max(0, min(start.maxX - 0.05, start.origin.x + dx))
                    new.size.width  = start.maxX - new.origin.x
                    new.size.height = max(0.05, min(1 - start.origin.y, start.size.height + dy))
                case .bottomRight:
                    new.size.width  = max(0.05, min(1 - start.origin.x, start.size.width + dx))
                    new.size.height = max(0.05, min(1 - start.origin.y, start.size.height + dy))
                }

                cropRect = new
            }
            .onEnded { _ in dragAnchor = nil }
    }

    // MARK: - Confirm Crop

    private func confirmCrop() {
        guard let image = capturedImage else { return }
        let imgSize = image.size
        guard displaySize.width > 0, displaySize.height > 0 else { return }

        // cropRect is normalized (0-1) relative to displaySize.
        // The image fills the entire Image view via scaledToFit(),
        // so displaySize maps directly to image pixels.
        let cropInPixels = CGRect(
            x: cropRect.origin.x * imgSize.width,
            y: cropRect.origin.y * imgSize.height,
            width: cropRect.size.width * imgSize.width,
            height: cropRect.size.height * imgSize.height
        )

        // Camera images have orientation metadata — cgImage.cropping(to:)
        // uses the un-oriented CGImage coordinate system, giving wrong results.
        // UIGraphicsImageRenderer respects UIImage orientation.
        let renderer = UIGraphicsImageRenderer(size: cropInPixels.size)
        let croppedImage = renderer.image { ctx in
            image.draw(at: CGPoint(x: -cropInPixels.origin.x, y: -cropInPixels.origin.y))
        }

        croppedPreviewImage = croppedImage
        withAnimation { step = .preview }
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

    // MARK: - Crop Preview

    private func cropPreviewView(image: UIImage) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 4)
                .padding(.horizontal, 40)

            Text("This will be the tracked image.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Make sure only the flashcard is visible — no background.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 24) {
                Button {
                    withAnimation { step = .crop }
                } label: {
                    Label("Retake", systemImage: "arrow.trianglehead.counterclockwise")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(Capsule())
                }

                Button {
                    proceedFromPreview()
                } label: {
                    Label("Looks Good!", systemImage: "hand.thumbsup.fill")
                        .font(.headline.bold())
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            }

            Spacer()
        }
    }

    private func proceedFromPreview() {
        guard let croppedImage = croppedPreviewImage else { return }
        if let card = manager.createFlashCard(image: croppedImage) {
            newCard = card
            showPairing = true
        }
    }
}
