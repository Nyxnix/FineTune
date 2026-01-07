// FineTune/Audio/AudioEngine.swift
import AudioToolbox
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
    private var appDeviceRouting: [pid_t: String] = [:]  // pid → deviceUID (always explicit)
    private var pendingCleanup: [pid_t: Task<Void, Never>] = [:]  // Grace period for stale tap cleanup
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

            deviceMonitor.onDeviceDisconnected = { [weak self] deviceUID, deviceName in
                self?.handleDeviceDisconnected(deviceUID, name: deviceName)
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
        if let deviceUID = appDeviceRouting[app.id] {
            ensureTapExists(for: app, deviceUID: deviceUID)
        }
        taps[app.id]?.volume = volume
    }

    func getVolume(for app: AudioApp) -> Float {
        volumeState.getVolume(for: app.id)
    }

    func setDevice(for app: AudioApp, deviceUID: String) {
        guard appDeviceRouting[app.id] != deviceUID else { return }
        appDeviceRouting[app.id] = deviceUID
        settingsManager.setDeviceRouting(for: app.persistenceIdentifier, deviceUID: deviceUID)

        if let tap = taps[app.id] {
            Task {
                do {
                    try await tap.switchDevice(to: deviceUID)
                    logger.debug("Switched \(app.name) to device: \(deviceUID)")
                } catch {
                    logger.error("Failed to switch device for \(app.name): \(error.localizedDescription)")
                }
            }
        } else {
            ensureTapExists(for: app, deviceUID: deviceUID)
        }
    }

    func getDeviceUID(for app: AudioApp) -> String? {
        appDeviceRouting[app.id]
    }

    func applyPersistedSettings() {
        for app in apps {
            guard !appliedPIDs.contains(app.id) else { continue }

            // Load saved device routing, or assign to current macOS default
            let deviceUID: String
            if let savedDeviceUID = settingsManager.getDeviceRouting(for: app.persistenceIdentifier),
               deviceMonitor.device(for: savedDeviceUID) != nil {
                // Saved device exists, use it
                deviceUID = savedDeviceUID
                logger.debug("Applying saved device routing to \(app.name): \(deviceUID)")
            } else {
                // New app or saved device no longer exists: assign to current macOS default
                do {
                    deviceUID = try AudioDeviceID.readDefaultSystemOutputDeviceUID()
                    settingsManager.setDeviceRouting(for: app.persistenceIdentifier, deviceUID: deviceUID)
                    logger.debug("App \(app.name) assigned to default device: \(deviceUID)")
                } catch {
                    logger.error("Failed to get default device for \(app.name): \(error.localizedDescription)")
                    continue
                }
            }
            appDeviceRouting[app.id] = deviceUID

            // Load saved volume
            let savedVolume = volumeState.loadSavedVolume(for: app.id, identifier: app.persistenceIdentifier)

            // Always create tap for audio apps (always-on strategy)
            ensureTapExists(for: app, deviceUID: deviceUID)

            // Only mark as applied if tap was successfully created
            // This allows retry on next applyPersistedSettings() call if tap failed
            guard taps[app.id] != nil else { continue }
            appliedPIDs.insert(app.id)

            if let volume = savedVolume {
                let displayPercent = Int(VolumeMapping.gainToSlider(volume) * 200)
                logger.debug("Applying saved volume \(displayPercent)% to \(app.name)")
                taps[app.id]?.volume = volume
            }
        }
    }

    private func ensureTapExists(for app: AudioApp, deviceUID: String) {
        guard taps[app.id] == nil else { return }

        let tap = ProcessTapController(app: app, targetDeviceUID: deviceUID, deviceMonitor: deviceMonitor)
        tap.volume = volumeState.getVolume(for: app.id)

        do {
            try tap.activate()
            taps[app.id] = tap
            logger.debug("Created tap for \(app.name)")
        } catch {
            logger.error("Failed to create tap for \(app.name): \(error.localizedDescription)")
        }
    }

    /// Called when device disappears - updates routing and switches taps immediately
    private func handleDeviceDisconnected(_ deviceUID: String, name deviceName: String) {
        // Get fallback device: macOS default, or first available device
        let fallbackDevice: (uid: String, name: String)
        do {
            let uid = try AudioDeviceID.readDefaultSystemOutputDeviceUID()
            let name = deviceMonitor.device(for: uid)?.name ?? "Default Output"
            fallbackDevice = (uid: uid, name: name)
        } catch {
            guard let firstDevice = deviceMonitor.outputDevices.first else {
                logger.error("No fallback device available")
                return
            }
            fallbackDevice = (uid: firstDevice.uid, name: firstDevice.name)
        }

        var affectedApps: [AudioApp] = []
        var tapsToSwitch: [ProcessTapController] = []

        for app in apps {
            if appDeviceRouting[app.id] == deviceUID {
                affectedApps.append(app)
                appDeviceRouting[app.id] = fallbackDevice.uid
                settingsManager.setDeviceRouting(for: app.persistenceIdentifier, deviceUID: fallbackDevice.uid)

                if let tap = taps[app.id] {
                    tapsToSwitch.append(tap)
                }
            }
        }

        if !tapsToSwitch.isEmpty {
            Task {
                for tap in tapsToSwitch {
                    do {
                        try await tap.switchDevice(to: fallbackDevice.uid)
                    } catch {
                        logger.error("Failed to switch device for \(tap.app.name): \(error.localizedDescription)")
                    }
                }
            }
        }

        if !affectedApps.isEmpty {
            logger.info("\(deviceName) disconnected, \(affectedApps.count) app(s) switched to \(fallbackDevice.name)")
            showDisconnectNotification(deviceName: deviceName, fallbackName: fallbackDevice.name, affectedApps: affectedApps)
        }
    }

    private func showDisconnectNotification(deviceName: String, fallbackName: String, affectedApps: [AudioApp]) {
        let content = UNMutableNotificationContent()
        content.title = "Audio Device Disconnected"
        content.body = "\"\(deviceName)\" disconnected. \(affectedApps.count) app(s) switched to \(fallbackName)"
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "device-disconnect-\(deviceName)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                self?.logger.error("Failed to show notification: \(error.localizedDescription)")
            }
        }
    }

    func cleanupStaleTaps() {
        let activePIDs = Set(apps.map { $0.id })
        let stalePIDs = Set(taps.keys).subtracting(activePIDs)

        // Cancel cleanup for PIDs that reappeared
        for pid in activePIDs {
            if let task = pendingCleanup.removeValue(forKey: pid) {
                task.cancel()
                logger.debug("Cancelled pending cleanup for PID \(pid) - app reappeared")
            }
        }

        // Schedule cleanup for newly stale PIDs (with grace period)
        for pid in stalePIDs {
            guard pendingCleanup[pid] == nil else { continue }  // Already pending

            pendingCleanup[pid] = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                // Double-check still stale
                let currentPIDs = Set(self.apps.map { $0.id })
                guard !currentPIDs.contains(pid) else {
                    self.pendingCleanup.removeValue(forKey: pid)
                    return
                }

                // Now safe to cleanup
                if let tap = self.taps.removeValue(forKey: pid) {
                    tap.invalidate()
                    self.logger.debug("Cleaned up stale tap for PID \(pid)")
                }
                self.appDeviceRouting.removeValue(forKey: pid)
                self.pendingCleanup.removeValue(forKey: pid)
            }
        }

        // Include pending PIDs in cleanup exclusion to avoid premature state cleanup
        let pidsToKeep = activePIDs.union(Set(pendingCleanup.keys))
        appliedPIDs = appliedPIDs.intersection(pidsToKeep)
        volumeState.cleanup(keeping: pidsToKeep)
    }
}
