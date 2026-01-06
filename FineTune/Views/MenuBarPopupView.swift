// FineTune/Views/MenuBarPopupView.swift
import SwiftUI

struct MenuBarPopupView: View {
    @Bindable var audioEngine: AudioEngine
    @Bindable var deviceVolumeMonitor: DeviceVolumeMonitor

    /// Memoized sorted devices - only recomputed when device list or default changes
    @State private var sortedDevices: [AudioDevice] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Output Devices header
            Text("Output Devices")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            // Device rows
            ForEach(sortedDevices) { device in
                DeviceVolumeRowView(
                    device: device,
                    volume: deviceVolumeMonitor.volumes[device.id] ?? 1.0,
                    isDefault: device.id == deviceVolumeMonitor.defaultDeviceID,
                    onVolumeChange: { volume in
                        deviceVolumeMonitor.setVolume(for: device.id, to: volume)
                    },
                    onSetAsDefault: {
                        deviceVolumeMonitor.setDefaultDevice(device.id)
                    }
                )
            }

            Divider()

            if audioEngine.apps.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "speaker.slash")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("No apps playing audio")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
            } else {
                // Apps header
                Text("Apps")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(audioEngine.apps) { app in
                            if let deviceUID = audioEngine.getDeviceUID(for: app) {
                                AppVolumeRowView(
                                    app: app,
                                    volume: audioEngine.getVolume(for: app),
                                    onVolumeChange: { volume in
                                        audioEngine.setVolume(for: app, to: volume)
                                    },
                                    devices: audioEngine.outputDevices,
                                    selectedDeviceUID: deviceUID,
                                    onDeviceSelected: { newDeviceUID in
                                        audioEngine.setDevice(for: app, deviceUID: newDeviceUID)
                                    }
                                )
                            }
                        }
                    }
                }
                .frame(maxHeight: 400)
            }

            Divider()

            Button("Quit FineTune") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
        .padding()
        .frame(width: 520)
        .onAppear {
            updateSortedDevices()
        }
        .onChange(of: audioEngine.outputDevices) { _, _ in
            updateSortedDevices()
        }
        .onChange(of: deviceVolumeMonitor.defaultDeviceID) { _, _ in
            updateSortedDevices()
        }
    }

    /// Recomputes sorted devices - called only when dependencies change
    private func updateSortedDevices() {
        let devices = audioEngine.outputDevices
        let defaultID = deviceVolumeMonitor.defaultDeviceID
        sortedDevices = devices.sorted { lhs, rhs in
            if lhs.id == defaultID { return true }
            if rhs.id == defaultID { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
