import SwiftUI

/// Adjust scale, rotation, and vertical offset of a model relative to its tracked image.
struct ModelAdjustView: View {
    let card: FlashCard
    @ObservedObject var manager: FlashCardManager
    @Environment(\.dismiss) private var dismiss

    @State private var scale: Float
    @State private var rotation: Float
    @State private var verticalOffset: Float

    init(card: FlashCard, manager: FlashCardManager) {
        self.card = card
        self.manager = manager
        _scale       = State(initialValue: card.modelScale)
        _rotation    = State(initialValue: card.modelRotationDegrees)
        _verticalOffset = State(initialValue: card.modelVerticalOffset)
    }

    var body: some View {
        NavigationStack {
            List {
                // Preview section
                Section {
                    VStack(spacing: 16) {
                        previewIcon
                            .frame(height: 120)

                        if let name = card.modelName {
                            Text(name)
                                .font(.headline)
                        }

                        // Real-time preview of combined transform
                        HStack(spacing: 16) {
                            labelValue(icon: "arrow.up.arrow.down", value: String(format: "%.1f×", scale))
                            labelValue(icon: "arrow.trianglehead.rotate", value: String(format: "%.0f°", rotation))
                            labelValue(icon: "arrow.up.and.down", value: String(format: "%.2fm", verticalOffset))
                        }
                        .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                }

                // Scale
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text("Scale")
                            Spacer()
                            Text(String(format: "%.1f×", scale))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $scale, in: 0.1...5.0, step: 0.1)
                            .tint(.blue)
                        Text("How big the model appears on the flashcard")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Rotation
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "arrow.trianglehead.rotate")
                            Text("Rotation")
                            Spacer()
                            Text(String(format: "%.0f°", rotation))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $rotation, in: 0...360, step: 1)
                            .tint(.blue)
                        Text("Spin the model around its vertical axis")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Vertical offset
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "arrow.up.and.down")
                            Text("Height")
                            Spacer()
                            Text(String(format: "%.2fm", verticalOffset))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $verticalOffset, in: -0.3...0.5, step: 0.01)
                            .tint(.blue)
                        Text("Raise or lower the model above the tracked image")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Adjust Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        manager.updateAdjustments(
                            for: card.id,
                            scale: scale,
                            rotationDegrees: rotation,
                            verticalOffset: verticalOffset
                        )
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Preview Icon

    private var previewIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.blue.opacity(0.08))
            VStack(spacing: 4) {
                Image(systemName: "arkit")
                    .font(.title)
                    .foregroundColor(.blue)
                Text("AR Preview")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func labelValue(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(value)
                .monospacedDigit()
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.gray.opacity(0.1))
        .clipShape(Capsule())
    }
}
