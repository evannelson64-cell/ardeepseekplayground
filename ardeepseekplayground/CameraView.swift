import SwiftUI
import AVFoundation

/// A custom camera view built with AVFoundation.
/// Shows a live preview with a capture button and instructional overlay.
struct CameraView: View {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    // Held by the view so it stays alive for the whole capture lifecycle.
    @State private var cameraController = CameraController()

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreview(session: cameraController.session)
                .ignoresSafeArea()

            // Overlay UI
            VStack {
                HStack {
                    Button {
                        cameraController.stop()
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

                Text("Frame your image and tap the button below")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.5))
                    .clipShape(Capsule())

                Button {
                    cameraController.capturePhoto { image in
                        // Just pass the image back – parent handles dismissal
                        onCapture(image)
                    }
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
        .onAppear { cameraController.start() }
        .onDisappear { cameraController.stop() }
    }
}

// MARK: - Camera Controller

/// Holds the AVCaptureSession + output and handles the photo capture delegate.
class CameraController: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var continuation: CheckedContinuation<UIImage, Error>?

    func start() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard session.canAddInput(input) else { return }
        session.addInput(input)

        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        session.commitConfiguration()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stop() {
        session.stopRunning()
    }

    func capturePhoto(completion: @escaping (UIImage) -> Void) {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto

        // Use a simple delegate that fires the completion
        let delegate = PhotoCaptureDelegate(completion: completion)
        // Keep the delegate alive by associating it with the output
        objc_setAssociatedObject(output, Unmanaged.passUnretained(output).toOpaque(),
                                 delegate, .OBJC_ASSOCIATION_RETAIN)
        output.capturePhoto(with: settings, delegate: delegate)
    }
}

// MARK: - Photo Capture Delegate

private class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    let completion: (UIImage) -> Void

    init(completion: @escaping (UIImage) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            print("Camera error: \(error?.localizedDescription ?? "unknown")")
            return
        }
        DispatchQueue.main.async { [completion] in
            completion(image)
        }

        // Clean up the associated object (safe to do from any queue)
        objc_setAssociatedObject(output, Unmanaged.passUnretained(output).toOpaque(),
                                 nil, .OBJC_ASSOCIATION_RETAIN)
    }
}

// MARK: - UIViewRepresentable Camera Preview

/// UIView whose layer IS an AVCaptureVideoPreviewLayer (no separate sublayer needed).
class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // The view's layer IS the preview layer – just cast it.
        layer as! AVCaptureVideoPreviewLayer
    }
}

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
