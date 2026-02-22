import Foundation
import Darwin

/// RT-safe feed-forward dynamics compressor for per-app processing.
final class CompressorProcessor: @unchecked Sendable {
    private var sampleRate: Double
    private var _currentSettings: CompressorSettings = .default

    // Lock-free state for audio callback access.
    private nonisolated(unsafe) var _isEnabled: Bool = false
    private nonisolated(unsafe) var _thresholdDB: Float = -18.0
    private nonisolated(unsafe) var _invRatio: Float = 1.0 / 3.0
    private nonisolated(unsafe) var _attackCoeff: Float = 0.9979
    private nonisolated(unsafe) var _releaseCoeff: Float = 0.9998
    private nonisolated(unsafe) var _makeupGainLinear: Float = 1.0

    // Detector / gain smoothing state.
    private nonisolated(unsafe) var _envelope: Float = 0.0
    private nonisolated(unsafe) var _smoothedGain: Float = 1.0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        updateSettings(.default)
    }

    func updateSettings(_ settings: CompressorSettings) {
        _currentSettings = settings

        _isEnabled = settings.isEnabled
        _thresholdDB = settings.clampedThresholdDB
        _invRatio = 1.0 / max(CompressorSettings.minRatio, settings.clampedRatio)
        _makeupGainLinear = Self.dbToLinear(settings.clampedMakeupGainDB)

        updateTimeCoefficients(
            attackMs: settings.clampedAttackMs,
            releaseMs: settings.clampedReleaseMs
        )
    }

    func updateSampleRate(_ newRate: Double) {
        guard newRate != sampleRate else { return }
        sampleRate = newRate

        let settings = _currentSettings
        updateTimeCoefficients(
            attackMs: settings.clampedAttackMs,
            releaseMs: settings.clampedReleaseMs
        )

        // Reset detector state when sample rate changes to avoid stale gain envelopes.
        _envelope = 0.0
        _smoothedGain = 1.0
    }

    /// Process interleaved audio in place.
    func process(buffer: UnsafeMutablePointer<Float>, frameCount: Int, channels: Int) {
        guard _isEnabled, frameCount > 0, channels > 0 else { return }

        let thresholdDB = _thresholdDB
        let invRatio = _invRatio
        let attackCoeff = _attackCoeff
        let releaseCoeff = _releaseCoeff
        let makeupGain = _makeupGainLinear

        var envelope = _envelope
        var smoothedGain = _smoothedGain

        for frame in 0..<frameCount {
            let frameBase = frame * channels

            var detector: Float = 0
            for channel in 0..<channels {
                let sample = abs(buffer[frameBase + channel])
                if sample > detector {
                    detector = sample
                }
            }

            let envCoeff = detector > envelope ? attackCoeff : releaseCoeff
            envelope = (envCoeff * envelope) + ((1 - envCoeff) * detector)

            let inputDB = Self.linearToDB(envelope)
            var targetGain = makeupGain
            if inputDB > thresholdDB {
                let compressedDB = thresholdDB + ((inputDB - thresholdDB) * invRatio)
                let gainReductionDB = compressedDB - inputDB
                targetGain *= Self.dbToLinear(gainReductionDB)
            }

            let gainCoeff = targetGain < smoothedGain ? attackCoeff : releaseCoeff
            smoothedGain = (gainCoeff * smoothedGain) + ((1 - gainCoeff) * targetGain)

            for channel in 0..<channels {
                buffer[frameBase + channel] *= smoothedGain
            }
        }

        _envelope = envelope
        _smoothedGain = smoothedGain
    }

    private func updateTimeCoefficients(attackMs: Float, releaseMs: Float) {
        let attackSeconds = max(CompressorSettings.minAttackMs, attackMs) / 1000.0
        let releaseSeconds = max(CompressorSettings.minReleaseMs, releaseMs) / 1000.0
        let sr = Float(max(sampleRate, 1.0))

        _attackCoeff = expf(-1.0 / (sr * attackSeconds))
        _releaseCoeff = expf(-1.0 / (sr * releaseSeconds))
    }

    @inline(__always)
    private static func dbToLinear(_ db: Float) -> Float {
        powf(10.0, db / 20.0)
    }

    @inline(__always)
    private static func linearToDB(_ linear: Float) -> Float {
        20.0 * log10f(max(linear, 1.0e-8))
    }
}
