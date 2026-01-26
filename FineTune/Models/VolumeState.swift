// FineTune/Models/VolumeState.swift
import Foundation

@Observable
@MainActor
final class VolumeState {
    private var volumes: [pid_t: Float] = [:]
    private var mutes: [pid_t: Bool] = [:]
    private var pidToIdentifier: [pid_t: String] = [:]
    private let settingsManager: SettingsManager?

    init(settingsManager: SettingsManager? = nil) {
        self.settingsManager = settingsManager
    }

    func getVolume(for pid: pid_t) -> Float {
        volumes[pid] ?? (settingsManager?.appSettings.defaultNewAppVolume ?? 1.0)
    }

    func setVolume(for pid: pid_t, to volume: Float, identifier: String? = nil) {
        volumes[pid] = volume

        if let identifier = identifier {
            pidToIdentifier[pid] = identifier
        }

        if let id = identifier ?? pidToIdentifier[pid] {
            settingsManager?.setVolume(for: id, to: volume)
        }
    }

    func loadSavedVolume(for pid: pid_t, identifier: String) -> Float? {
        pidToIdentifier[pid] = identifier
        if let saved = settingsManager?.getVolume(for: identifier) {
            volumes[pid] = saved
            return saved
        }
        return nil
    }

    // MARK: - Mute State

    func getMute(for pid: pid_t) -> Bool {
        mutes[pid] ?? false
    }

    func setMute(for pid: pid_t, to muted: Bool, identifier: String? = nil) {
        mutes[pid] = muted

        if let identifier = identifier {
            pidToIdentifier[pid] = identifier
        }

        if let id = identifier ?? pidToIdentifier[pid] {
            settingsManager?.setMute(for: id, to: muted)
        }
    }

    func loadSavedMute(for pid: pid_t, identifier: String) -> Bool? {
        pidToIdentifier[pid] = identifier
        if let saved = settingsManager?.getMute(for: identifier) {
            mutes[pid] = saved
            return saved
        }
        return nil
    }

    func removeVolume(for pid: pid_t) {
        volumes.removeValue(forKey: pid)
        mutes.removeValue(forKey: pid)
        pidToIdentifier.removeValue(forKey: pid)
    }

    func cleanup(keeping pids: Set<pid_t>) {
        volumes = volumes.filter { pids.contains($0.key) }
        mutes = mutes.filter { pids.contains($0.key) }
        pidToIdentifier = pidToIdentifier.filter { pids.contains($0.key) }
    }
}
