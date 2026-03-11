import SwiftUI

struct EditPanel: View {
    @Bindable var pipeline: EditingPipeline

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("EDIT")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.semibold)

            Group {
                LabeledSlider(
                    label: "Exposure",
                    value: $pipeline.exposure,
                    range: -3.0...3.0,
                    format: "%+.1f EV"
                )
                LabeledSlider(
                    label: "Temperature",
                    value: $pipeline.temperature,
                    range: 2000...10000,
                    format: "%.0fK"
                )
                LabeledSlider(
                    label: "Tint",
                    value: $pipeline.tint,
                    range: -150...150,
                    format: "%+.0f"
                )
                LabeledSlider(
                    label: "Contrast",
                    value: $pipeline.contrast,
                    range: 0.0...2.0,
                    format: "%.2f"
                )
                LabeledSlider(
                    label: "Saturation",
                    value: $pipeline.saturation,
                    range: 0.0...2.0,
                    format: "%.2f"
                )
            }
            .disabled(!pipeline.hasImage)

            Divider()

            Text("EXPORT")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.semibold)

            LabeledSlider(
                label: "Quality",
                value: $pipeline.jpegQuality,
                range: 0.0...1.0,
                format: "%.0f%%",
                displayMultiplier: 100
            )
            .disabled(!pipeline.hasImage)

            Spacer()
        }
        .padding()
    }
}

struct LabeledSlider: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let format: String
    var displayMultiplier: Float = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text(String(format: format, value * displayMultiplier))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .controlSize(.small)
        }
    }
}
