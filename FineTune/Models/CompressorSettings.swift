import Foundation

struct CompressorSettings: Codable, Equatable {
    static let minThresholdDB: Float = -60.0
    static let maxThresholdDB: Float = 0.0
    static let minRatio: Float = 1.0
    static let maxRatio: Float = 20.0
    static let minAttackMs: Float = 1.0
    static let maxAttackMs: Float = 100.0
    static let minReleaseMs: Float = 10.0
    static let maxReleaseMs: Float = 500.0
    static let minMakeupGainDB: Float = -12.0
    static let maxMakeupGainDB: Float = 12.0

    /// Whether compressor processing is enabled.
    /// Default is disabled to preserve existing app behavior.
    var isEnabled: Bool

    /// Threshold in dBFS.
    var thresholdDB: Float

    /// Compression ratio.
    var ratio: Float

    /// Attack time in milliseconds.
    var attackMs: Float

    /// Release time in milliseconds.
    var releaseMs: Float

    /// Makeup gain in dB.
    var makeupGainDB: Float

    init(
        isEnabled: Bool = false,
        thresholdDB: Float = -18.0,
        ratio: Float = 3.0,
        attackMs: Float = 10.0,
        releaseMs: Float = 100.0,
        makeupGainDB: Float = 0.0
    ) {
        self.isEnabled = isEnabled
        self.thresholdDB = thresholdDB
        self.ratio = ratio
        self.attackMs = attackMs
        self.releaseMs = releaseMs
        self.makeupGainDB = makeupGainDB
    }

    var clampedThresholdDB: Float {
        max(Self.minThresholdDB, min(Self.maxThresholdDB, thresholdDB))
    }

    var clampedRatio: Float {
        max(Self.minRatio, min(Self.maxRatio, ratio))
    }

    var clampedAttackMs: Float {
        max(Self.minAttackMs, min(Self.maxAttackMs, attackMs.rounded()))
    }

    var clampedReleaseMs: Float {
        max(Self.minReleaseMs, min(Self.maxReleaseMs, releaseMs))
    }

    var clampedMakeupGainDB: Float {
        max(Self.minMakeupGainDB, min(Self.maxMakeupGainDB, makeupGainDB))
    }

    /// Returns settings normalized to valid persisted values.
    func normalized() -> CompressorSettings {
        CompressorSettings(
            isEnabled: isEnabled,
            thresholdDB: clampedThresholdDB,
            ratio: clampedRatio,
            attackMs: clampedAttackMs,
            releaseMs: clampedReleaseMs,
            makeupGainDB: clampedMakeupGainDB
        )
    }

    static let `default` = CompressorSettings()
}
