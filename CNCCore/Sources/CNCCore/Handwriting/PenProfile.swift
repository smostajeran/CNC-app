import Foundation

/// Writing instrument categories for pressure / speed behaviour.
public enum WritingInstrument: String, Codable, Sendable, CaseIterable, Identifiable {
    case ballpoint
    case fountain
    case rollerball
    case gel
    case pencil
    case marker

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ballpoint: return "Ballpoint"
        case .fountain: return "Fountain pen"
        case .rollerball: return "Rollerball"
        case .gel: return "Gel pen"
        case .pencil: return "Pencil"
        case .marker: return "Marker"
        }
    }
}

/// Base pressure band and dynamics for one instrument.
public struct PenProfile: Equatable, Sendable, Codable {
    public var instrument: WritingInstrument
    /// Nominal mid-stroke pressure.
    public var basePressure: Double
    public var minPressure: Double
    public var maxPressure: Double
    /// Hard safety clamp (never exceed) — protects nibs / paper.
    public var maxPressureSafety: Double
    /// Max |Δp| per millimetre of path (rate limit before filter).
    public var maxPressureDeltaPerMm: Double
    /// Low-pass time constant proxy (mm of travel for ~63% settle).
    public var filterLengthMm: Double
    /// Typical draw feed (mm/min) used as velocity planner centre.
    public var nominalFeedMmMin: Double
    /// Amplitude of low-frequency human variation (fraction of full scale).
    public var humanVariationAmplitude: Double
    /// Distance between LF pressure targets (mm).
    public var humanVariationWavelengthMm: ClosedRange<Double>
    public var attackLengthFraction: Double
    public var releaseLengthFraction: Double

    public init(
        instrument: WritingInstrument,
        basePressure: Double,
        minPressure: Double,
        maxPressure: Double,
        maxPressureSafety: Double,
        maxPressureDeltaPerMm: Double,
        filterLengthMm: Double,
        nominalFeedMmMin: Double,
        humanVariationAmplitude: Double,
        humanVariationWavelengthMm: ClosedRange<Double>,
        attackLengthFraction: Double,
        releaseLengthFraction: Double
    ) {
        self.instrument = instrument
        self.basePressure = HandwritingMath.clamp(basePressure, 0, 1)
        self.minPressure = HandwritingMath.clamp(minPressure, 0, 1)
        self.maxPressure = HandwritingMath.clamp(maxPressure, 0, 1)
        self.maxPressureSafety = HandwritingMath.clamp(maxPressureSafety, 0, 1)
        self.maxPressureDeltaPerMm = max(0.001, maxPressureDeltaPerMm)
        self.filterLengthMm = max(0.5, filterLengthMm)
        self.nominalFeedMmMin = max(100, nominalFeedMmMin)
        self.humanVariationAmplitude = HandwritingMath.clamp(humanVariationAmplitude, 0, 0.1)
        self.humanVariationWavelengthMm = humanVariationWavelengthMm
        self.attackLengthFraction = HandwritingMath.clamp(attackLengthFraction, 0.02, 0.4)
        self.releaseLengthFraction = HandwritingMath.clamp(releaseLengthFraction, 0.02, 0.45)
    }

    public static func profile(for instrument: WritingInstrument) -> PenProfile {
        switch instrument {
        case .fountain:
            return PenProfile(
                instrument: .fountain,
                basePressure: 0.22,
                minPressure: 0.15,
                maxPressure: 0.30,
                maxPressureSafety: 0.35,
                maxPressureDeltaPerMm: 0.04,
                filterLengthMm: 4.0,
                nominalFeedMmMin: 900,
                humanVariationAmplitude: 0.02,
                humanVariationWavelengthMm: 12...28,
                attackLengthFraction: 0.18,
                releaseLengthFraction: 0.28
            )
        case .rollerball:
            return PenProfile(
                instrument: .rollerball,
                basePressure: 0.35,
                minPressure: 0.25,
                maxPressure: 0.45,
                maxPressureSafety: 0.55,
                maxPressureDeltaPerMm: 0.05,
                filterLengthMm: 3.0,
                nominalFeedMmMin: 1_200,
                humanVariationAmplitude: 0.025,
                humanVariationWavelengthMm: 12...26,
                attackLengthFraction: 0.14,
                releaseLengthFraction: 0.22
            )
        case .gel:
            return PenProfile(
                instrument: .gel,
                basePressure: 0.38,
                minPressure: 0.25,
                maxPressure: 0.50,
                maxPressureSafety: 0.60,
                maxPressureDeltaPerMm: 0.055,
                filterLengthMm: 2.8,
                nominalFeedMmMin: 1_300,
                humanVariationAmplitude: 0.025,
                humanVariationWavelengthMm: 10...24,
                attackLengthFraction: 0.12,
                releaseLengthFraction: 0.20
            )
        case .ballpoint:
            return PenProfile(
                instrument: .ballpoint,
                basePressure: 0.55,
                minPressure: 0.45,
                maxPressure: 0.70,
                maxPressureSafety: 0.80,
                maxPressureDeltaPerMm: 0.07,
                filterLengthMm: 2.2,
                nominalFeedMmMin: 1_500,
                humanVariationAmplitude: 0.03,
                humanVariationWavelengthMm: 10...22,
                attackLengthFraction: 0.12,
                releaseLengthFraction: 0.18
            )
        case .pencil:
            return PenProfile(
                instrument: .pencil,
                basePressure: 0.50,
                minPressure: 0.30,
                maxPressure: 0.80,
                maxPressureSafety: 0.85,
                maxPressureDeltaPerMm: 0.08,
                filterLengthMm: 2.0,
                nominalFeedMmMin: 1_400,
                humanVariationAmplitude: 0.035,
                humanVariationWavelengthMm: 8...20,
                attackLengthFraction: 0.10,
                releaseLengthFraction: 0.16
            )
        case .marker:
            return PenProfile(
                instrument: .marker,
                basePressure: 0.20,
                minPressure: 0.10,
                maxPressure: 0.30,
                maxPressureSafety: 0.40,
                maxPressureDeltaPerMm: 0.035,
                filterLengthMm: 5.0,
                nominalFeedMmMin: 1_100,
                humanVariationAmplitude: 0.015,
                humanVariationWavelengthMm: 14...30,
                attackLengthFraction: 0.20,
                releaseLengthFraction: 0.25
            )
        }
    }
}
