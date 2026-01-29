// FineTune/Models/VolumeState.swift
import Foundation

/// Consolidated state for a single app's audio settings
struct AppAudioState {
    var volume: Float
    var muted: Bool
    var persistenceIdentifier: String
}

@Observable
@MainActor
final class VolumeState {
    /// Single source of truth for per-app audio state
    private var states: [pid_t: AppAudioState] = [:]
    private let settingsManager: SettingsManager?

    init(settingsManager: SettingsManager? = nil) {
        self.settingsManager = settingsManager
    }

    // MARK: - Volume

    func getVolume(for pid: pid_t) -> Float {
        states[pid]?.volume ?? (settingsManager?.appSettings.defaultNewAppVolume ?? 1.0)
    }

    func setVolume(for pid: pid_t, to volume: Float, identifier: String? = nil) {
        if var state = states[pid] {
            state.volume = volume
            if let identifier = identifier {
                state.persistenceIdentifier = identifier
            }
            states[pid] = state
            settingsManager?.setVolume(for: state.persistenceIdentifier, to: volume)
        } else if let identifier = identifier {
            states[pid] = AppAudioState(volume: volume, muted: false, persistenceIdentifier: identifier)
            settingsManager?.setVolume(for: identifier, to: volume)
        }
        // If no identifier provided and no existing state, volume is not persisted
    }

    func loadSavedVolume(for pid: pid_t, identifier: String) -> Float? {
        ensureState(for: pid, identifier: identifier)
        if let saved = settingsManager?.getVolume(for: identifier) {
            states[pid]?.volume = saved
            return saved
        }
        return nil
    }

    // MARK: - Mute State

    func getMute(for pid: pid_t) -> Bool {
        states[pid]?.muted ?? false
    }

    func setMute(for pid: pid_t, to muted: Bool, identifier: String? = nil) {
        if var state = states[pid] {
            state.muted = muted
            if let identifier = identifier {
                state.persistenceIdentifier = identifier
            }
            states[pid] = state
            settingsManager?.setMute(for: state.persistenceIdentifier, to: muted)
        } else if let identifier = identifier {
            let defaultVolume = settingsManager?.appSettings.defaultNewAppVolume ?? 1.0
            states[pid] = AppAudioState(volume: defaultVolume, muted: muted, persistenceIdentifier: identifier)
            settingsManager?.setMute(for: identifier, to: muted)
        }
        // If no identifier provided and no existing state, mute is not persisted
    }

    func loadSavedMute(for pid: pid_t, identifier: String) -> Bool? {
        ensureState(for: pid, identifier: identifier)
        if let saved = settingsManager?.getMute(for: identifier) {
            states[pid]?.muted = saved
            return saved
        }
        return nil
    }

    // MARK: - Cleanup

    func removeVolume(for pid: pid_t) {
        states.removeValue(forKey: pid)
    }

    func cleanup(keeping pids: Set<pid_t>) {
        states = states.filter { pids.contains($0.key) }
    }

    // MARK: - Private

    private func ensureState(for pid: pid_t, identifier: String) {
        if states[pid] == nil {
            let defaultVolume = settingsManager?.appSettings.defaultNewAppVolume ?? 1.0
            states[pid] = AppAudioState(volume: defaultVolume, muted: false, persistenceIdentifier: identifier)
        } else if states[pid]?.persistenceIdentifier != identifier {
            states[pid]?.persistenceIdentifier = identifier
        }
    }
}
