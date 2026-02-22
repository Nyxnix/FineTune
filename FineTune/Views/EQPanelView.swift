// FineTune/Views/EQPanelView.swift
import SwiftUI

struct EQPanelView: View {
    @Binding var settings: EQSettings
    @Binding var compressorSettings: CompressorSettings
    let onPresetSelected: (EQPreset) -> Void
    let onSettingsChanged: (EQSettings) -> Void
    let onCompressorSettingsChanged: (CompressorSettings) -> Void

    private let frequencyLabels = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    private let compressorSliderTrackWidth: CGFloat = 330

    private var currentPreset: EQPreset? {
        EQPreset.allCases.first { preset in
            preset.settings.bandGains == settings.bandGains
        }
    }

    var body: some View {
        // Entire EQ panel content inside recessed background
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                // Header: Toggle left, Preset right
                HStack {
                    // EQ toggle on left
                    HStack(spacing: 6) {
                        Toggle("", isOn: $settings.isEnabled)
                            .toggleStyle(.switch)
                            .scaleEffect(0.7)
                            .labelsHidden()
                            .onChange(of: settings.isEnabled) { _, _ in
                                onSettingsChanged(settings)
                            }
                        Text("EQ")
                            .font(DesignTokens.Typography.pickerText)
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    // Preset picker on right
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Text("Preset")
                            .font(DesignTokens.Typography.pickerText)
                            .foregroundColor(DesignTokens.Colors.textSecondary)

                        EQPresetPicker(
                            selectedPreset: currentPreset,
                            onPresetSelected: onPresetSelected
                        )
                    }
                }
                .zIndex(1)  // Ensure dropdown renders above sliders

                // 10-band sliders
                HStack(spacing: 22) {
                    ForEach(0..<10, id: \.self) { index in
                        EQSliderView(
                            frequency: frequencyLabels[index],
                            gain: Binding(
                                get: { settings.bandGains[index] },
                                set: { newValue in
                                    settings.bandGains[index] = newValue
                                    onSettingsChanged(settings)
                                }
                            )
                        )
                        .frame(width: 26, height: 100)
                    }
                }
            }
            .padding(.bottom, 4)

            Divider()
                .overlay(DesignTokens.Colors.glassBorder)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Toggle("", isOn: $compressorSettings.isEnabled)
                            .toggleStyle(.switch)
                            .scaleEffect(0.7)
                            .labelsHidden()
                            .onChange(of: compressorSettings.isEnabled) { _, _ in
                                onCompressorSettingsChanged(compressorSettings)
                            }
                        Text("Compressor")
                            .font(DesignTokens.Typography.pickerText)
                            .foregroundColor(.primary)
                    }

                    Spacer()
                }

                compressorSlider(
                    label: "Threshold",
                    value: Binding(
                        get: { Double(compressorSettings.thresholdDB) },
                        set: { newValue in
                            compressorSettings.thresholdDB = Float(newValue.rounded())
                            onCompressorSettingsChanged(compressorSettings)
                        }
                    ),
                    range: Double(CompressorSettings.minThresholdDB)...Double(CompressorSettings.maxThresholdDB),
                    valueSuffix: " dB",
                    markerInterval: 3.0,
                    allowsNumericInput: true
                )

                compressorSlider(
                    label: "Ratio",
                    value: Binding(
                        get: { Double(compressorSettings.ratio) },
                        set: { newValue in
                            compressorSettings.ratio = Float(newValue.rounded())
                            onCompressorSettingsChanged(compressorSettings)
                        }
                    ),
                    range: Double(CompressorSettings.minRatio)...Double(CompressorSettings.maxRatio),
                    valueSuffix: ":1",
                    allowsNumericInput: true
                )

                compressorSlider(
                    label: "Attack",
                    value: Binding(
                        get: { Double(compressorSettings.clampedAttackMs) },
                        set: { newValue in
                            compressorSettings.attackMs = Float(newValue.rounded())
                            onCompressorSettingsChanged(compressorSettings)
                        }
                    ),
                    range: Double(CompressorSettings.minAttackMs)...Double(CompressorSettings.maxAttackMs),
                    valueSuffix: " ms",
                    valueFormat: "%.0f",
                    markerInterval: 10.0,
                    allowsNumericInput: true
                )

                compressorSlider(
                    label: "Release",
                    value: Binding(
                        get: { Double(compressorSettings.releaseMs) },
                        set: { newValue in
                            compressorSettings.releaseMs = Float(newValue.rounded())
                            onCompressorSettingsChanged(compressorSettings)
                        }
                    ),
                    range: Double(CompressorSettings.minReleaseMs)...Double(CompressorSettings.maxReleaseMs),
                    valueSuffix: " ms",
                    valueFormat: "%.0f",
                    markerInterval: 50.0,
                    allowsNumericInput: true
                )

                compressorSlider(
                    label: "Makeup",
                    value: Binding(
                        get: { Double(compressorSettings.makeupGainDB) },
                        set: { newValue in
                            compressorSettings.makeupGainDB = Float(newValue.rounded())
                            onCompressorSettingsChanged(compressorSettings)
                        }
                    ),
                    range: Double(CompressorSettings.minMakeupGainDB)...Double(CompressorSettings.maxMakeupGainDB),
                    valueSuffix: " dB",
                    valueFormat: "%.0f",
                    markerInterval: 3.0,
                    allowsNumericInput: true
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(DesignTokens.Colors.recessedBackground)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        // No outer background - parent ExpandableGlassRow provides the glass container
    }

    @ViewBuilder
    private func compressorSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueSuffix: String,
        valueFormat: String = "%.1f",
        markerInterval: Double? = nil,
        allowsNumericInput: Bool = false
    ) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Text(label)
                .font(DesignTokens.Typography.caption)
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .frame(width: 72, alignment: .leading)

            VStack(spacing: 4) {
                Slider(value: value, in: range)
                    .controlSize(.small)
                    .frame(width: compressorSliderTrackWidth)
                    .layoutPriority(1)

                if let markerInterval {
                    CompressorSliderMarkers(range: range, markerInterval: markerInterval)
                        .frame(width: compressorSliderTrackWidth, height: 4)
                }
            }

            if allowsNumericInput {
                CompressorNumericInput(
                    value: Binding(
                        get: { Int(value.wrappedValue.rounded()) },
                        set: { newValue in
                            value.wrappedValue = Double(newValue)
                        }
                    ),
                    range: Int(range.lowerBound.rounded())...Int(range.upperBound.rounded()),
                    suffix: valueSuffix.trimmingCharacters(in: .whitespaces)
                )
                .frame(width: 78, alignment: .trailing)
            } else {
                Text("\(value.wrappedValue, specifier: valueFormat)\(valueSuffix)")
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .monospacedDigit()
                    .frame(width: 78, alignment: .trailing)
            }
        }
    }
}

private struct CompressorSliderMarkers: View {
    let range: ClosedRange<Double>
    let markerInterval: Double

    private var markerValues: [Double] {
        guard markerInterval > 0, range.upperBound > range.lowerBound else { return [] }

        var values: [Double] = []
        let epsilon = markerInterval * 0.0001
        var marker = ceil(range.lowerBound / markerInterval) * markerInterval
        while marker <= range.upperBound + epsilon {
            values.append(marker)
            marker += markerInterval
        }
        return values
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(markerValues.enumerated()), id: \.offset) { _, marker in
                    Circle()
                        .fill(DesignTokens.Colors.textTertiary.opacity(0.55))
                        .frame(width: 3, height: 3)
                        .position(x: xPosition(for: marker, width: geo.size.width), y: geo.size.height / 2)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func xPosition(for marker: Double, width: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        let normalized = (marker - range.lowerBound) / span
        return CGFloat(normalized) * width
    }
}

private struct CompressorNumericInput: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let suffix: String

    @State private var inputText: String
    @FocusState private var isFocused: Bool

    init(value: Binding<Int>, range: ClosedRange<Int>, suffix: String) {
        self._value = value
        self.range = range
        self.suffix = suffix
        self._inputText = State(initialValue: "\(value.wrappedValue)")
    }

    var body: some View {
        HStack(spacing: 2) {
            TextField("", text: $inputText)
                .textFieldStyle(.plain)
                .font(DesignTokens.Typography.caption.monospacedDigit())
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .frame(width: 42)
                .onSubmit { commit(resignFocus: true) }
                .onExitCommand { cancel() }

            Text(suffix)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(DesignTokens.Colors.pickerBackground)
        }
        .onChange(of: value) { _, newValue in
            if !isFocused {
                inputText = "\(newValue)"
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                commit()
            }
        }
    }

    private func commit(resignFocus: Bool = false) {
        let cleaned = inputText.trimmingCharacters(in: .whitespaces)
        guard let parsed = Int(cleaned) else {
            inputText = "\(value)"
            if resignFocus {
                isFocused = false
            }
            return
        }
        let clamped = min(max(parsed, range.lowerBound), range.upperBound)
        value = clamped
        inputText = "\(clamped)"
        if resignFocus {
            isFocused = false
        }
    }

    private func cancel() {
        inputText = "\(value)"
        isFocused = false
    }
}

#Preview {
    // Simulating how it appears inside ExpandableGlassRow
    VStack {
        EQPanelView(
            settings: .constant(EQSettings()),
            compressorSettings: .constant(CompressorSettings()),
            onPresetSelected: { _ in },
            onSettingsChanged: { _ in },
            onCompressorSettingsChanged: { _ in }
        )
    }
    .padding(.horizontal, DesignTokens.Spacing.sm)
    .padding(.vertical, DesignTokens.Spacing.xs)
    .background {
        RoundedRectangle(cornerRadius: DesignTokens.Dimensions.rowRadius)
            .fill(DesignTokens.Colors.recessedBackground)
    }
    .frame(width: 550)
    .padding()
    .background(Color.black)
}
