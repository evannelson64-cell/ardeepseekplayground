import SwiftUI
import CoreImage

/// Lets the user crop a photo to the exact region they want ARKit to track.
struct ImageCropView: View {
    let image: UIImage
    let onCrop: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    // The crop rectangle is defined as a ratio of the displayed image size.
    @State private var cropRect: CGRect = .init(x: 0.1, y: 0.1, width: 0.8, height: 0.8)

    // Image display size (computed once)
    @State private var displaySize: CGSize = .zero

    // Drag state
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var activeCorner: Corner? = nil
    @State private var cornerDragStart: (rect: CGRect, location: CGPoint)? = nil

    private enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight

        var cursor: String {
            switch self {
            case .topLeft, .bottomRight: return "arrow.up.left.and.down.right.arrow"
            case .topRight, .bottomLeft: return "arrow.up.right.and.down.left.arrow"
            }
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color.black.ignoresSafeArea()

                    // The image filling the width
                    let imageSize = image.size
                    let displayW = geo.size.width
                    let displayH = displayW * (imageSize.height / imageSize.width)
                    let imgDisplaySize = CGSize(width: displayW, height: displayH)

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: displayW)
                        .overlay(alignment: .topLeading) {
                            GeometryReader { imgGeo in
                                let actualSize = imgGeo.size
                                Color.clear.onAppear { displaySize = actualSize }
                            }
                        }

                    // Crop overlay
                    if displaySize != .zero {
                        cropOverlay(canvasSize: displaySize)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Crop Tracking Area")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Photo") {
                        if let cropped = performCrop() {
                            onCrop(cropped)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Crop Overlay

    private func cropOverlay(canvasSize: CGSize) -> some View {
        let rect = normalizedToPixel(cropRect, canvasSize: canvasSize)

        return ZStack {
            // Dark mask with hole
            Canvas { ctx, size in
                // Fill the whole canvas with dark
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.5)))

                // Cut out the crop rectangle
                let hole = Path(roundedRect: rect, cornerRadius: 4)
                ctx.blendMode = .destinationOut
                ctx.fill(hole, with: .color(.white))
            }

            // Crop rectangle border
            RoundedRectangle(cornerRadius: 4)
                .stroke(.white, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            // Corner handles
            ForEach(Corner.allCases, id: \.self) { corner in
                cornerHandle(corner: corner, rect: rect)
            }

            // Center drag area
            Color.clear
                .contentShape(Rectangle())
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .gesture(
                    DragGesture()
                        .onChanged { val in
                            let dx = val.translation.width / canvasSize.width
                            let dy = val.translation.height / canvasSize.height
                            var new = cropRect
                            new.origin.x = max(0, min(1 - new.width, cropRect.origin.x + dx))
                            new.origin.y = max(0, min(1 - new.height, cropRect.origin.y + dy))
                            cropRect = new
                        }
                )
        }
    }

    private func cornerHandle(corner: Corner, rect: CGRect) -> some View {
        let size: CGFloat = 28
        let pos: CGPoint = {
            switch corner {
            case .topLeft:     return CGPoint(x: rect.minX, y: rect.minY)
            case .topRight:    return CGPoint(x: rect.maxX, y: rect.minY)
            case .bottomLeft:  return CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
            }
        }()

        return Circle()
            .fill(.white)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color.blue, lineWidth: 2))
            .position(pos)
            .gesture(
                DragGesture()
                    .onChanged { val in
                        let canvasSize = displaySize
                        let dx = val.translation.width / canvasSize.width
                        let dy = val.translation.height / canvasSize.height
                        var new = cropRect

                        switch corner {
                        case .topLeft:
                            new.origin.x = max(0, min(cropRect.maxX - 0.05, cropRect.origin.x + dx))
                            new.origin.y = max(0, min(cropRect.maxY - 0.05, cropRect.origin.y + dy))
                            new.size.width = cropRect.maxX - new.origin.x
                            new.size.height = cropRect.maxY - new.origin.y
                        case .topRight:
                            new.origin.y = max(0, min(cropRect.maxY - 0.05, cropRect.origin.y + dy))
                            new.size.width = max(0.05, min(1 - new.origin.x, cropRect.size.width + dx))
                            new.size.height = cropRect.maxY - new.origin.y
                        case .bottomLeft:
                            new.origin.x = max(0, min(cropRect.maxX - 0.05, cropRect.origin.x + dx))
                            new.size.width = cropRect.maxX - new.origin.x
                            new.size.height = max(0.05, min(1 - new.origin.y, cropRect.size.height + dy))
                        case .bottomRight:
                            new.size.width = max(0.05, min(1 - cropRect.origin.x, cropRect.size.width + dx))
                            new.size.height = max(0.05, min(1 - cropRect.origin.y, cropRect.size.height + dy))
                        }

                        cropRect = new
                    }
            )
    }

    // MARK: - Crop Logic

    private func normalizedToPixel(_ norm: CGRect, canvasSize: CGSize) -> CGRect {
        CGRect(x: norm.origin.x * canvasSize.width,
               y: norm.origin.y * canvasSize.height,
               width: norm.size.width * canvasSize.width,
               height: norm.size.height * canvasSize.height)
    }

    private func performCrop() -> UIImage? {
        let imgSize = image.size
        let cropNorm = CGRect(x: cropRect.origin.x * imgSize.width,
                              y: cropRect.origin.y * imgSize.height,
                              width: cropRect.size.width * imgSize.width,
                              height: cropRect.size.height * imgSize.height)

        guard let cgImage = image.cgImage,
              let cropped = cgImage.cropping(to: cropNorm)
        else { return nil }

        return UIImage(cgImage: cropped)
    }
}
