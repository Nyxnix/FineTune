// FineTune/Audio/AudioEngine.swift
import Foundation
import os

@Observable
@MainActor
final class AudioEngine {
    let monitor = AudioProcessMonitor()
    let volumeState: VolumeState
    let settingsManager: SettingsManager

    private var taps: [pid_t: ProcessTapController] = [:]
    private var appliedPIDs: Set<pid_t> = []
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "FineTune", category: "AudioEngine")

    init(settingsManager: SettingsManager? = nil) {
        let manager = settingsManager ?? SettingsManager()
        self.settingsManager = manager
        self.volumeState = VolumeState(settingsManager: manager)

        Task { @MainActor in
            monitor.start()
            monitor.onAppsChanged = { [weak self] _ in
                self?.cleanupStaleTaps()
                self?.applyPersistedVolumes()
            }
            applyPersistedVolumes()
        }
    }

    var apps: [AudioApp] {
        monitor.activeApps
    }

    func start() {
        monitor.start()
        applyPersistedVolumes()
        logger.info("AudioEngine started")
    }

    func stop() {
        monitor.stop()
        for tap in taps.values {
            tap.invalidate()
        }
        taps.removeAll()
        logger.info("AudioEngine stopped")
    }

    func setVolume(for app: AudioApp, to volume: Float) {
        volumeState.setVolume(for: app.id, to: volume, identifier: app.persistenceIdentifier)
        applyVolumeToTap(for: app, volume: volume)
    }

    func getVolume(for app: AudioApp) -> Float {
        volumeState.getVolume(for: app.id)
    }

    func applyPersistedVolumes() {
        for app in apps {
            guard !appliedPIDs.contains(app.id) else { continue }
            appliedPIDs.insert(app.id)

            if let savedVolume = volumeState.loadSavedVolume(for: app.id, identifier: app.persistenceIdentifier) {
                logger.debug("Applying saved volume \(Int(savedVolume * 100))% to \(app.name)")
                applyVolumeToTap(for: app, volume: savedVolume)
            }
        }
    }

    private func applyVolumeToTap(for app: AudioApp, volume: Float) {
        let isUnityGain = abs(volume - 1.0) < 0.001

        if let existingTap = taps[app.id] {
            if isUnityGain {
                // Destroy tap when returning to unity (no processing needed)
                existingTap.invalidate()
                taps.removeValue(forKey: app.id)
                logger.debug("Removed tap for \(app.name) (unity gain)")
            } else {
                existingTap.volume = volume
            }
        } else if !isUnityGain {
            // Only create tap if NOT at unity gain
            let tap = ProcessTapController(app: app)
            tap.volume = volume
            do {
                try tap.activate()
                taps[app.id] = tap
                logger.debug("Created tap for \(app.name) at \(Int(volume * 100))%")
            } catch {
                logger.error("Failed to create tap for \(app.name): \(error.localizedDescription)")
            }
        }
        // If isUnityGain and no existing tap: do nothing (no tap needed)
    }

    func cleanupStaleTaps() {
        let activePIDs = Set(apps.map { $0.id })
        let stalePIDs = Set(taps.keys).subtracting(activePIDs)

        for pid in stalePIDs {
            if let tap = taps.removeValue(forKey: pid) {
                tap.invalidate()
                logger.debug("Cleaned up stale tap for PID \(pid)")
            }
        }

        appliedPIDs = appliedPIDs.intersection(activePIDs)
        volumeState.cleanup(keeping: activePIDs)
    }
}
