import SwiftUI
import AVFoundation

/// A custom camera view built with AVFoundation.
/// Shows a live preview with a capture button and instructional overlay.
struct CameraView: View {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var session = AVCaptureSession()
    @State private var isSessionRunning = false
    @State private var capturedImage: UIImage?

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreview(session: session)
                .ignoresSafeArea()

            // Overlay UI
            VStack {
                // Top bar
                HStack {
                    Button {
                        session.stopRunning()
                        dismiss()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                            .font(.headline)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
                .padding()

                Spacer()

                // Instruction text
                Text("Frame your image and tap the button below")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.5))
                    .clipShape(Capsule())

                // Capture button
                Button {
                    capturePhoto()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 72, height: 72)
                        Circle()
                            .fill(.white)
                            .frame(width: 60, height: 60)
                    }
                }
                .padding(.bottom, 40)
                .padding(.top, 20)
            }
        }
        .onAppear {
            startCamera()
        }
        .onDisappear {
            session.stopRunning()
        }
    }

    private func startCamera() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        session.commitConfiguration()

        // Store output for capture
        let context = CameraContext(output: output, onCapture: onCapture, dismiss: { dismiss() })
        objc_setAssociatedObject(self, &AssocKeys.context, context, .OBJC_ASSOCIATION_RETAIN)

        DispatchQueue.global(qos: .userInitiated).async { [weak session] in
            session?.startRunning()
        }
    }

    private func capturePhoto() {
        guard let context = objc_getAssociatedObject(self, &AssocKeys.context) as? CameraContext else { return }
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        context.output.capturePhoto(with: settings, delegate: context)
    }
}

// MARK: - Associated Object Key

private struct AssocKeys {
    static var context = 0
}

// MARK: - Camera Context

private class CameraContext: NSObject, AVCapturePhotoCaptureDelegate {
    let output: AVCapturePhotoOutput
    let onCapture: (UIImage) -> Void
    let dismiss: () -> Void

    init(output: AVCapturePhotoOutput, onCapture: @escaping (UIImage) -> Void, dismiss: @escaping () -> Void) {
        self.output = output
        self.onCapture = onCapture
        self.dismiss = dismiss
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            print("Camera error: \(error?.localizedDescription ?? "unknown")")
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onCapture(image)
            self?.dismiss()
        }
    }
}

// MARK: - UIViewRepresentable Camera Preview

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView(frame: .zero)
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

/// UIView that hosts an AVCaptureVideoPreviewLayer and keeps it sized correctly.
class PreviewView: UIView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        if let layer = layer as? AVCaptureVideoPreviewLayer {
            layer.videoGravity = .resizeAspectFill
        }
    }

    required init?(coder: NSCoder) { nil }
}
