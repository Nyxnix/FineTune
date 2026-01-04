// FineTune/Audio/AudioEngine.swift
import Foundation
import os
import UserNotifications

@Observable
@MainActor
final class AudioEngine {
    let processMonitor = AudioProcessMonitor()
    let deviceMonitor = AudioDeviceMonitor()
    let deviceVolumeMonitor: DeviceVolumeMonitor
    let volumeState: VolumeState
    let settingsManager: SettingsManager

    private var taps: [pid_t: ProcessTapController] = [:]
    private var appliedPIDs: Set<pid_t> = []
    private var appDeviceRouting: [pid_t: String?] = [:]  // pid → deviceUID (nil = system default)
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "FineTune", category: "AudioEngine")

    var outputDevices: [AudioDevice] {
        deviceMonitor.outputDevices
    }

    init(settingsManager: SettingsManager? = nil) {
        let manager = settingsManager ?? SettingsManager()
        self.settingsManager = manager
        self.volumeState = VolumeState(settingsManager: manager)
        self.deviceVolumeMonitor = DeviceVolumeMonitor(deviceMonitor: deviceMonitor)

        Task { @MainActor in
            processMonitor.start()
            deviceMonitor.start()

            // Start device volume monitor AFTER deviceMonitor.start() populates devices
            // This fixes the race condition where volumes were read before devices existed
            deviceVolumeMonitor.start()

            processMonitor.onAppsChanged = { [weak self] _ in
                self?.cleanupStaleTaps()
                self?.applyPersistedSettings()
            }

            deviceMonitor.onDeviceDisconnected = { [weak self] deviceUID in
                self?.fallbackAppsFromDevice(deviceUID)
            }

            applyPersistedSettings()
        }
    }

    var apps: [AudioApp] {
        processMonitor.activeApps
    }

    func start() {
        // Monitors have internal guards against double-starting
        processMonitor.start()
        deviceMonitor.start()
        applyPersistedSettings()
        logger.info("AudioEngine started")
    }

    func stop() {
        processMonitor.stop()
        deviceMonitor.stop()
        for tap in taps.values {
            tap.invalidate()
        }
        taps.removeAll()
        logger.info("AudioEngine stopped")
    }

    func setVolume(for app: AudioApp, to volume: Float) {
        volumeState.setVolume(for: app.id, to: volume, identifier: app.persistenceIdentifier)
        ensureTapExists(for: app)
        taps[app.id]?.volume = volume
    }

    func getVolume(for app: AudioApp) -> Float {
        volumeState.getVolume(for: app.id)
    }

    func setDevice(for app: AudioApp, deviceUID: String?) {
        appDeviceRouting[app.id] = deviceUID
        settingsManager.setDeviceRouting(for: app.persistenceIdentifier, deviceUID: deviceUID)

        if let tap = taps[app.id] {
            Task {
                do {
                    try await tap.switchDevice(to: deviceUID)
                    logger.debug("Switched \(app.name) to device: \(deviceUID ?? "system default")")
                } catch {
                    logger.error("Failed to switch device for \(app.name): \(error.localizedDescription)")
                }
            }
        } else {
            ensureTapExists(for: app)
        }
    }

    func getDeviceUID(for app: AudioApp) -> String? {
        appDeviceRouting[app.id].flatMap { $0 }
    }

    func applyPersistedSettings() {
        for app in apps {
            guard !appliedPIDs.contains(app.id) else { continue }

            // Load saved device routing
            let savedDeviceUID = settingsManager.getDeviceRouting(for: app.persistenceIdentifier)
            appDeviceRouting[app.id] = savedDeviceUID

            // Load saved volume
            let savedVolume = volumeState.loadSavedVolume(for: app.id, identifier: app.persistenceIdentifier)

            // Always create tap for audio apps (always-on strategy)
            ensureTapExists(for: app, deviceUID: savedDeviceUID)

            // Only mark as applied if tap was successfully created
            // This allows retry on next applyPersistedSettings() call if tap failed
            guard taps[app.id] != nil else { continue }
            appliedPIDs.insert(app.id)

            if let volume = savedVolume {
                let displayPercent = Int(VolumeMapping.gainToSlider(volume) * 200)
                logger.debug("Applying saved volume \(displayPercent)% to \(app.name)")
                taps[app.id]?.volume = volume
            }

            if let deviceUID = savedDeviceUID {
                logger.debug("Applying saved device routing to \(app.name): \(deviceUID)")
            }
        }
    }

    private func ensureTapExists(for app: AudioApp, deviceUID: String? = nil) {
        guard taps[app.id] == nil else { return }

        let targetDevice = deviceUID ?? appDeviceRouting[app.id].flatMap { $0 }
        let tap = ProcessTapController(app: app, targetDeviceUID: targetDevice)
        tap.volume = volumeState.getVolume(for: app.id)

        do {
            try tap.activate()
            taps[app.id] = tap
            logger.debug("Created tap for \(app.name)")
        } catch {
            logger.error("Failed to create tap for \(app.name): \(error.localizedDescription)")
        }
    }

    func fallbackAppsFromDevice(_ deviceUID: String) {
        var affectedApps: [AudioApp] = []
        var tapsToSwitch: [ProcessTapController] = []

        for app in apps {
            if appDeviceRouting[app.id] == deviceUID {
                affectedApps.append(app)
                appDeviceRouting[app.id] = nil
                settingsManager.setDeviceRouting(for: app.persistenceIdentifier, deviceUID: nil)

                if let tap = taps[app.id] {
                    tapsToSwitch.append(tap)
                }
            }
        }

        if !tapsToSwitch.isEmpty {
            Task {
                for tap in tapsToSwitch {
                    do {
                        try await tap.switchDevice(to: nil)
                    } catch {
                        logger.error("Failed to fallback device for \(tap.app.name): \(error.localizedDescription)")
                    }
                }
            }
        }

        if !affectedApps.isEmpty {
            showDisconnectNotification(deviceUID: deviceUID, affectedApps: affectedApps)
        }
    }

    private func showDisconnectNotification(deviceUID: String, affectedApps: [AudioApp]) {
        let deviceName = deviceUID.components(separatedBy: ":").last ?? deviceUID

        let content = UNMutableNotificationContent()
        content.title = "Audio Device Disconnected"
        content.body = "\"\(deviceName)\" disconnected. \(affectedApps.count) app(s) switched to default output"
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "device-disconnect-\(deviceUID)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                self?.logger.error("Failed to show notification: \(error.localizedDescription)")
            }
        }

        logger.info("Device '\(deviceName)' disconnected, \(affectedApps.count) app(s) switched to default")
    }

    func cleanupStaleTaps() {
        let activePIDs = Set(apps.map { $0.id })
        let stalePIDs = Set(taps.keys).subtracting(activePIDs)

        for pid in stalePIDs {
            if let tap = taps.removeValue(forKey: pid) {
                tap.invalidate()
                logger.debug("Cleaned up stale tap for PID \(pid)")
            }
            appDeviceRouting.removeValue(forKey: pid)
        }

        appliedPIDs = appliedPIDs.intersection(activePIDs)
        volumeState.cleanup(keeping: activePIDs)
    }
}
