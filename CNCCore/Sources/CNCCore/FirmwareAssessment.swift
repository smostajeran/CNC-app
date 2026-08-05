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
        let extracted = extractVersion(from: blob)
        let version = extracted ?? "unknown"
        var notes: [String] = []

        if blob.isEmpty && settings.isEmpty {
            return FirmwareAssessment(
                verdict: .unknown,
                versionLabel: "unknown",
                summary: "No GRBL banner or $I yet — connect and Check machine.",
                notes: ["Plug USB + 12V, then Check machine."]
            )
        }

        let lower = blob.lowercased()
        let isGrbl = lower.contains("grbl") || lower.contains("[ver:") || looksLikeGRBL11Settings(settings)
        let has11String = version.hasPrefix("1.1") || lower.contains("1.1")
        let settingsSuggest11 = looksLikeGRBL11Settings(settings)
        let is11 = has11String || (isGrbl && settingsSuggest11)
        let isVendorZ = version.lowercased().contains("1.1z") || lower.contains("1.1z")

        if let laser = settings["$32"], laser >= 1 {
            notes.append("$32 (laser mode) is on — turn off for pen plotting unless using a laser module.")
        }
        notes.append(contentsOf: travelNotes(settings: settings))

        if isVendorZ {
            notes.append("Vendor GRBL 1.1z reported — third-party $J= jog may fail; prefer OEM nano_328p_ta4 or stock 1.1f/g.")
            return FirmwareAssessment(
                verdict: .caution,
                versionLabel: version,
                summary: "GRBL 1.1z (vendor) — test a 10 mm jog in Move before streaming jobs.",
                notes: notes
            )
        }

        if isGrbl && is11 {
            if !has11String, settingsSuggest11 {
                notes.append("Version string missing from $I/banner — settings look like GRBL 1.1 (OK for Quill).")
            } else {
                notes.append("Looks like GRBL 1.1 — suitable for Quill streaming and $J= jog.")
            }
            let label = has11String ? version : (settingsSuggest11 ? "1.1 (from settings)" : version)
            return FirmwareAssessment(
                verdict: notes.contains(where: { $0.contains("laser mode") }) ? .caution : .compatible,
                versionLabel: label,
                summary: "GRBL 1.1 detected — OK to proceed after a test jog.",
                notes: notes
            )
        }

        if isGrbl {
            notes.append("GRBL detected but not clearly 1.1.x — use a 10 mm jog in Move before plotting.")
            return FirmwareAssessment(
                verdict: .caution,
                versionLabel: version,
                summary: "GRBL present; version unclear — verify with a 10 mm jog in Move.",
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

    /// GRBL 1.1 reports axis steps, rates, and soft-limit travel via $$.
    public static func looksLikeGRBL11Settings(_ settings: [String: Double]) -> Bool {
        let keys = ["$100", "$101", "$110", "$111", "$130", "$131"]
        let hit = keys.filter { settings[$0] != nil }.count
        return hit >= 4
    }

    public static func travelNotes(settings: [String: Double]) -> [String] {
        guard let xTravel = settings["$130"], let yTravel = settings["$131"] else { return [] }
        let x = Int(xTravel.rounded())
        let y = Int(yTravel.rounded())
        // Common Quill / Bachin TA-4 beds
        if abs(xTravel - 390) < 2, abs(yTravel - 200) < 2 {
            return ["Travel $130/$131 = \(x)×\(y) mm — full TA-4 bed."]
        }
        if abs(xTravel - 297) < 2, abs(yTravel - 200) < 2 {
            return ["Travel $130/$131 = \(x)×\(y) mm — A4 landscape (from Calibrate or soft limits)."]
        }
        if abs(xTravel - 210) < 2, abs(yTravel - 148) < 2 {
            return ["Travel $130/$131 = \(x)×\(y) mm — A5 soft limits."]
        }
        if xTravel < 100 || yTravel < 80 || xTravel > 500 || yTravel > 400 {
            return [String(
                format: "Travel $130/$131 = %.0f×%.0f mm — unusual for TA-4 (~390×200); verify soft limits.",
                xTravel, yTravel
            )]
        }
        return [String(format: "Travel $130/$131 = %.0f×%.0f mm.", xTravel, yTravel)]
    }

    public static func extractVersion(from text: String) -> String? {
        // Case-insensitive; allow multi-letter suffixes (1.1f, 1.1hf).
        let pattern = #"1\.1[a-zA-Z]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let r = Range(match.range, in: text) else { return nil }
        return String(text[r]).lowercased()
    }
}
