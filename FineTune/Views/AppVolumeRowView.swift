// FineTune/Views/AppVolumeRowView.swift
import SwiftUI

struct AppVolumeRowView: View {
    let app: AudioApp
    let volume: Float
    let onVolumeChange: (Float) -> Void

    @State private var sliderValue: Double

    init(app: AudioApp, volume: Float, onVolumeChange: @escaping (Float) -> Void) {
        self.app = app
        self.volume = volume
        self.onVolumeChange = onVolumeChange
        self._sliderValue = State(initialValue: Double(volume))
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)

            Text(app.name)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)

            Slider(value: $sliderValue, in: 0...1)
                .frame(minWidth: 100)
                .onChange(of: sliderValue) { _, newValue in
                    onVolumeChange(Float(newValue))
                }

            Text("\(Int(sliderValue * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 35, alignment: .trailing)
        }
        .onChange(of: volume) { _, newValue in
            sliderValue = Double(newValue)
        }
    }
}
