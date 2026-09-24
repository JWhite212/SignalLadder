// Sources/NotificationCore/Loudness.swift
import Foundation

/// How loud to play a sound, so that "gain 0" means the same thing for every
/// sound (§5.16).
///
/// Measured: the system sounds' peaks run from −15 dBFS (Frog) to −5 dBFS
/// (Hero), a 10 dB spread — by the spec's own note, roughly a perceived
/// doubling. Without this, "100%" on Frog would be quieter than Hero at 100%,
/// and an alert whose one job is to be heard would depend on which sound
/// someone happened to pick. Peak normalisation is not loudness normalisation
/// — perceived loudness also depends on a sound's energy over time — but it
/// removes the largest, measured source of inconsistency.
public enum Loudness {
    /// Where every sound's peak lands at a rule gain of 0 dB. One decibel of
    /// headroom; the peak limiter handles anything a positive gain adds.
    public static let targetPeakDBFS: Double = -1

    /// Below this a file is treated as silent. Playing it and reporting
    /// "Played" would claim an alert happened when nothing could be heard.
    public static let silenceFloorDBFS: Double = -60

    /// The most normalisation will ever boost a quiet file. A recording
    /// peaking at −45 dBFS would otherwise take +44 dB and mostly amplify its
    /// own hiss; capped, it simply stays quieter than the others.
    public static let maximumBoostDB: Double = 24

    /// A linear peak amplitude in decibels full scale, or nil for silence or a
    /// value that is not a real measurement.
    public static func peakDBFS(_ peak: Float) -> Double? {
        guard peak.isFinite, peak > 0 else { return nil }
        return 20 * log10(Double(peak))
    }

    /// Whether a sound with this peak can be heard at all.
    public static func isAudible(peak: Float) -> Bool {
        guard let dB = peakDBFS(peak) else { return false }
        return dB > silenceFloorDBFS
    }

    /// The gain to apply to a sound with this measured peak, for a rule asking
    /// for `ruleGainDB`. nil when the sound is too quiet to play honestly — the
    /// caller must report that as a failure, never as a sound played.
    public static func appliedGainDB(forPeak peak: Float, ruleGainDB: Double) -> Double? {
        guard isAudible(peak: peak), let peakDB = peakDBFS(peak) else { return nil }
        let normalisation = min(targetPeakDBFS - peakDB, maximumBoostDB)
        return normalisation + ruleGainDB
    }
}
