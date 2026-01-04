// FineTune/FineTuneApp.swift
import SwiftUI
import UserNotifications

@main
struct FineTuneApp: App {
    @State private var audioEngine: AudioEngine

    var body: some Scene {
        MenuBarExtra("FineTune", systemImage: "slider.horizontal.3") {
            MenuBarPopupView(audioEngine: audioEngine, deviceVolumeMonitor: audioEngine.deviceVolumeMonitor)
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        let settings = SettingsManager()
        let engine = AudioEngine(settingsManager: settings)
        _audioEngine = State(initialValue: engine)

        // DeviceVolumeMonitor is now created and started inside AudioEngine
        // This ensures proper initialization order: deviceMonitor.start() -> deviceVolumeMonitor.start()

        // Request notification authorization (for device disconnect alerts)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, error in
            if let error {
                print("Notification authorization error: \(error.localizedDescription)")
            }
            // If not granted, notifications will silently not appear - acceptable behavior
        }

        // Flush settings on app termination to prevent data loss from debounced saves
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [settings] _ in
            settings.flushSync()
        }
    }
}
