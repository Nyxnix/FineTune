// FineTune/Audio/AudioProcessMonitor.swift
import AppKit
import AudioToolbox
import os

@Observable
@MainActor
final class AudioProcessMonitor {
    private(set) var activeApps: [AudioApp] = []
    var onAppsChanged: (([AudioApp]) -> Void)?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "FineTune", category: "AudioProcessMonitor")

    // Property listeners
    private var processListListenerBlock: AudioObjectPropertyListenerBlock?
    private var processListenerBlocks: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var monitoredProcesses: Set<AudioObjectID> = []

    private var processListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        guard processListListenerBlock == nil else { return }

        logger.debug("Starting audio process monitor")

        // Set up listener first
        processListListenerBlock = { [weak self] numberAddresses, addresses in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }

        let status = AudioObjectAddPropertyListenerBlock(
            .system,
            &processListAddress,
            .main,
            processListListenerBlock!
        )

        if status != noErr {
            logger.error("Failed to add process list listener: \(status)")
        }

        // Initial refresh
        refresh()
    }

    func stop() {
        logger.debug("Stopping audio process monitor")

        // Remove process list listener
        if let block = processListListenerBlock {
            AudioObjectRemovePropertyListenerBlock(.system, &processListAddress, .main, block)
            processListListenerBlock = nil
        }

        // Remove all per-process listeners
        removeAllProcessListeners()
    }

    private func refresh() {
        do {
            let processIDs = try AudioObjectID.readProcessList()
            let runningApps = NSWorkspace.shared.runningApplications
            let myPID = ProcessInfo.processInfo.processIdentifier

            var apps: [AudioApp] = []

            for objectID in processIDs {
                guard objectID.readProcessIsRunning() else { continue }
                guard let pid = try? objectID.readProcessPID(), pid != myPID else { continue }

                let bundleID = objectID.readProcessBundleID()
                let runningApp = runningApps.first { $0.processIdentifier == pid }

                let name = runningApp?.localizedName ?? bundleID?.components(separatedBy: ".").last ?? "Unknown"
                let icon = runningApp?.icon ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage()

                let app = AudioApp(
                    id: pid,
                    objectID: objectID,
                    name: name,
                    icon: icon,
                    bundleID: bundleID
                )
                apps.append(app)
            }

            // Update per-process listeners
            updateProcessListeners(for: processIDs)

            activeApps = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            onAppsChanged?(activeApps)

        } catch {
            logger.error("Failed to refresh process list: \(error.localizedDescription)")
        }
    }

    private func updateProcessListeners(for processIDs: [AudioObjectID]) {
        let currentSet = Set(processIDs)

        // Remove listeners for processes that are gone
        let removed = monitoredProcesses.subtracting(currentSet)
        for objectID in removed {
            removeProcessListener(for: objectID)
        }

        // Add listeners for new processes
        let added = currentSet.subtracting(monitoredProcesses)
        for objectID in added {
            addProcessListener(for: objectID)
        }

        monitoredProcesses = currentSet
    }

    private func addProcessListener(for objectID: AudioObjectID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }

        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, .main, block)

        if status == noErr {
            processListenerBlocks[objectID] = block
        } else {
            logger.warning("Failed to add isRunning listener for \(objectID): \(status)")
        }
    }

    private func removeProcessListener(for objectID: AudioObjectID) {
        guard let block = processListenerBlocks.removeValue(forKey: objectID) else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListenerBlock(objectID, &address, .main, block)
    }

    private func removeAllProcessListeners() {
        for objectID in monitoredProcesses {
            removeProcessListener(for: objectID)
        }
        monitoredProcesses.removeAll()
        processListenerBlocks.removeAll()
    }

    deinit {
        // Note: Can't call stop() here due to MainActor isolation
        // Listeners will be cleaned up when the process exits
    }
}
