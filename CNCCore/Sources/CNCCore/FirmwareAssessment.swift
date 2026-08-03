import Foundation

public enum FirmwareVerdict: String, Equatable, Sendable {
    case unknown
    case compatible
    case caution
    case incompatibleHint
}

/// Interprets GRBL `$I` / banner / key `$` settings for TA-4 host readiness.
public struct FirmwareAssessment: Equatable, Sendable {
    public var verdict: FirmwareVerdict
    public var versionLabel: String
    public var summary: String
    public var notes: [String]

    public init(
        verdict: FirmwareVerdict,
        versionLabel: String,
        summary: String,
        notes: [String] = []
    ) {
        self.verdict = verdict
        self.versionLabel = versionLabel
        self.summary = summary
        self.notes = notes
    }

    public static func assess(
        buildInfo: String,
        banner: String = "",
        settings: [String: Double] = [:]
    ) -> FirmwareAssessment {
        let blob = (buildInfo + "\n" + banner).trimmingCharacters(in: .whitespacesAndNewlines)
        let version = extractVersion(from: blob) ?? "unknown"
        var notes: [String] = []

        if blob.isEmpty {
            return FirmwareAssessment(
                verdict: .unknown,
                versionLabel: "unknown",
                summary: "No GRBL banner or $I yet — connect and Probe.",
                notes: ["Plug USB + 12V, then Probe $$/$I."]
            )
        }

        let lower = blob.lowercased()
        let isGrbl = lower.contains("grbl") || lower.contains("[ver:")
        let is11 = version.hasPrefix("1.1") || lower.contains("1.1")
        let isVendorZ = version.lowercased().contains("1.1z") || lower.contains("1.1z")

        if let laser = settings["$32"], laser >= 1 {
            notes.append("$32 (laser mode) is on — turn off for pen plotting unless using a laser module.")
        }
        if let xTravel = settings["$130"], let yTravel = settings["$131"] {
            if xTravel < 100 || yTravel < 80 || xTravel > 500 || yTravel > 400 {
                notes.append(String(
                    format: "Travel $130/$131 = %.0f×%.0f mm — unusual for TA-4 (~390×200); verify soft limits.",
                    xTravel, yTravel
                ))
            } else {
                notes.append(String(format: "Travel $130/$131 = %.0f×%.0f mm.", xTravel, yTravel))
            }
        }

        if isVendorZ {
            notes.append("Vendor GRBL 1.1z reported — third-party $J= jog may fail; prefer OEM nano_328p_ta4 or stock 1.1f/g.")
            return FirmwareAssessment(
                verdict: .caution,
                versionLabel: version,
                summary: "GRBL 1.1z (vendor) — probe jog before streaming jobs.",
                notes: notes
            )
        }

        if isGrbl && is11 {
            notes.append("Looks like GRBL 1.1 — suitable for Quill streaming and $J= jog.")
            return FirmwareAssessment(
                verdict: notes.contains(where: { $0.contains("laser mode") }) ? .caution : .compatible,
                versionLabel: version,
                summary: "GRBL 1.1 detected — OK to proceed after a test jog.",
                notes: notes
            )
        }

        if isGrbl {
            notes.append("GRBL detected but not clearly 1.1.x — test jog carefully.")
            return FirmwareAssessment(
                verdict: .caution,
                versionLabel: version,
                summary: "GRBL present; version unclear — verify with a 10 mm jog.",
                notes: notes
            )
        }

        return FirmwareAssessment(
            verdict: .incompatibleHint,
            versionLabel: version,
            summary: "Response did not look like GRBL — check port/baud/firmware.",
            notes: notes + ["Expected banner like: Grbl 1.1f ['$' for help]"]
        )
    }

    public static func extractVersion(from text: String) -> String? {
        let pattern = #"1\.1[a-zA-Z]?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let r = Range(match.range, in: text) else { return nil }
        return String(text[r])
    }
}
