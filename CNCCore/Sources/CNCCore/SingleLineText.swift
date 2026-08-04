import Foundation

/// Single-line (stick) font for writing-machine text jobs.
///
/// Coordinate system: unit em, baseline at `y = 0`, caps/ascenders up to `y ≈ 1`,
/// x-height ≈ `0.7`, descenders down to `y ≈ -0.28`.
public enum SingleLineText {
    public static func plotJob(
        text: String,
        heightMm: Double = 12,
        origin: PlotPoint = PlotPoint(x: 10, y: 100),
        letterSpacing: Double = 0.2
    ) -> PlotJob {
        let scale = heightMm / 1.0
        var commands: [PlotCommand] = []
        var cursorX = origin.x
        let baseline = origin.y

        for ch in text {
            if ch == "\n" {
                cursorX = origin.x
                // Callers stack lines; this helper advances X only.
                continue
            }
            if ch == " " {
                cursorX += scale * (0.5 + letterSpacing)
                continue
            }
            let upper = ch.uppercased().first ?? ch
            guard let glyph = glyphs[ch] ?? glyphs[upper] else {
                cursorX += scale * (0.5 + letterSpacing)
                continue
            }
            for stroke in glyph.strokes {
                guard let first = stroke.first else { continue }
                let start = PlotPoint(x: cursorX + first.x * scale, y: baseline + first.y * scale)
                commands.append(.move(start))
                for p in stroke.dropFirst() {
                    commands.append(.line(PlotPoint(x: cursorX + p.x * scale, y: baseline + p.y * scale)))
                }
            }
            cursorX += scale * (glyph.width + letterSpacing)
        }
        return PlotJob(commands: commands)
    }

    public static func gcode(
        text: String,
        profile: MachineProfile,
        heightMm: Double = 12,
        origin: PlotPoint = PlotPoint(x: 10, y: 100)
    ) -> String {
        let job = plotJob(text: text, heightMm: heightMm, origin: origin)
        return SVGToGCode.gcode(from: job, profile: profile)
    }

    /// Em-unit advance width for a character (space ≈ 0.5). Missing glyphs return `nil`.
    public static func glyphAdvance(for character: Character) -> Double? {
        if character == " " { return 0.5 }
        if character == "\n" || character == "\t" { return 0 }
        let upper = character.uppercased().first ?? character
        if let g = glyphs[character] ?? glyphs[upper] { return g.width }
        return nil
    }

    public static func hasGlyph(for character: Character) -> Bool {
        if character == " " || character == "\n" || character == "\t" { return true }
        let upper = character.uppercased().first ?? character
        return glyphs[character] != nil || glyphs[upper] != nil
    }

    /// Characters that have an explicit stick-font outline (excludes whitespace).
    public static var definedGlyphCharacters: Set<Character> {
        Set(glyphs.keys)
    }

    /// Width in mm of a single line (no wrapping).
    public static func measureWidthMm(
        _ text: String,
        heightMm: Double,
        letterSpacing: Double = 0.2,
        wordSpacingExtraEm: Double = 0
    ) -> Double {
        let scale = heightMm / 1.0
        var width = 0.0
        for ch in text {
            if ch == " " {
                width += scale * (0.5 + letterSpacing + wordSpacingExtraEm)
                continue
            }
            let advance = glyphAdvance(for: ch) ?? 0.5
            width += scale * (advance + letterSpacing)
        }
        return width
    }

    /// True when every non-whitespace character in `text` has a drawable glyph.
    public static func canDrawAllCharacters(in text: String) -> Bool {
        for ch in text where !ch.isWhitespace {
            if !hasGlyph(for: ch) { return false }
        }
        return true
    }

    private struct Glyph {
        var width: Double
        var strokes: [[PlotPoint]]
    }

    private static let glyphs: [Character: Glyph] = makeGlyphs()

    private static func makeGlyphs() -> [Character: Glyph] {
        func p(_ x: Double, _ y: Double) -> PlotPoint { PlotPoint(x: x, y: y) }
        var g: [Character: Glyph] = [:]

        // MARK: Uppercase
        g["A"] = Glyph(width: 0.7, strokes: [[p(0, 0), p(0.35, 1), p(0.7, 0)], [p(0.15, 0.4), p(0.55, 0.4)]])
        g["B"] = Glyph(width: 0.6, strokes: [[p(0, 0), p(0, 1), p(0.4, 1), p(0.55, 0.85), p(0.55, 0.6), p(0.4, 0.5), p(0, 0.5)], [p(0.4, 0.5), p(0.6, 0.35), p(0.6, 0.15), p(0.4, 0), p(0, 0)]])
        g["C"] = Glyph(width: 0.65, strokes: [[p(0.6, 0.85), p(0.35, 1), p(0.1, 0.85), p(0, 0.5), p(0.1, 0.15), p(0.35, 0), p(0.6, 0.15)]])
        g["D"] = Glyph(width: 0.65, strokes: [[p(0, 0), p(0, 1), p(0.35, 1), p(0.6, 0.75), p(0.6, 0.25), p(0.35, 0), p(0, 0)]])
        g["E"] = Glyph(width: 0.55, strokes: [[p(0.55, 1), p(0, 1), p(0, 0), p(0.55, 0)], [p(0, 0.5), p(0.4, 0.5)]])
        g["F"] = Glyph(width: 0.55, strokes: [[p(0, 0), p(0, 1), p(0.55, 1)], [p(0, 0.5), p(0.4, 0.5)]])
        g["G"] = Glyph(width: 0.7, strokes: [[p(0.65, 0.85), p(0.35, 1), p(0.1, 0.85), p(0, 0.5), p(0.1, 0.15), p(0.35, 0), p(0.65, 0.15), p(0.65, 0.45), p(0.4, 0.45)]])
        g["H"] = Glyph(width: 0.65, strokes: [[p(0, 0), p(0, 1)], [p(0.65, 0), p(0.65, 1)], [p(0, 0.5), p(0.65, 0.5)]])
        g["I"] = Glyph(width: 0.25, strokes: [[p(0.12, 0), p(0.12, 1)]])
        g["J"] = Glyph(width: 0.5, strokes: [[p(0.45, 1), p(0.45, 0.25), p(0.3, 0), p(0.1, 0), p(0, 0.2)]])
        g["K"] = Glyph(width: 0.6, strokes: [[p(0, 0), p(0, 1)], [p(0.55, 1), p(0, 0.5), p(0.6, 0)]])
        g["L"] = Glyph(width: 0.55, strokes: [[p(0, 1), p(0, 0), p(0.55, 0)]])
        g["M"] = Glyph(width: 0.8, strokes: [[p(0, 0), p(0, 1), p(0.4, 0.45), p(0.8, 1), p(0.8, 0)]])
        g["N"] = Glyph(width: 0.65, strokes: [[p(0, 0), p(0, 1), p(0.65, 0), p(0.65, 1)]])
        g["O"] = Glyph(width: 0.7, strokes: [[p(0.35, 0), p(0.1, 0.15), p(0, 0.5), p(0.1, 0.85), p(0.35, 1), p(0.6, 0.85), p(0.7, 0.5), p(0.6, 0.15), p(0.35, 0)]])
        g["P"] = Glyph(width: 0.55, strokes: [[p(0, 0), p(0, 1), p(0.4, 1), p(0.55, 0.85), p(0.55, 0.6), p(0.4, 0.45), p(0, 0.45)]])
        g["Q"] = Glyph(width: 0.7, strokes: [[p(0.35, 0), p(0.1, 0.15), p(0, 0.5), p(0.1, 0.85), p(0.35, 1), p(0.6, 0.85), p(0.7, 0.5), p(0.6, 0.15), p(0.35, 0)], [p(0.4, 0.3), p(0.7, 0)]])
        g["R"] = Glyph(width: 0.6, strokes: [[p(0, 0), p(0, 1), p(0.4, 1), p(0.55, 0.85), p(0.55, 0.6), p(0.4, 0.45), p(0, 0.45)], [p(0.3, 0.45), p(0.6, 0)]])
        g["S"] = Glyph(width: 0.55, strokes: [[p(0.5, 0.85), p(0.3, 1), p(0.1, 0.9), p(0.1, 0.7), p(0.45, 0.45), p(0.5, 0.25), p(0.35, 0), p(0.1, 0.1)]])
        g["T"] = Glyph(width: 0.65, strokes: [[p(0, 1), p(0.65, 1)], [p(0.325, 1), p(0.325, 0)]])
        g["U"] = Glyph(width: 0.65, strokes: [[p(0, 1), p(0, 0.25), p(0.15, 0), p(0.5, 0), p(0.65, 0.25), p(0.65, 1)]])
        g["V"] = Glyph(width: 0.7, strokes: [[p(0, 1), p(0.35, 0), p(0.7, 1)]])
        g["W"] = Glyph(width: 0.9, strokes: [[p(0, 1), p(0.2, 0), p(0.45, 0.7), p(0.7, 0), p(0.9, 1)]])
        g["X"] = Glyph(width: 0.65, strokes: [[p(0, 1), p(0.65, 0)], [p(0.65, 1), p(0, 0)]])
        g["Y"] = Glyph(width: 0.65, strokes: [[p(0, 1), p(0.325, 0.5), p(0.65, 1)], [p(0.325, 0.5), p(0.325, 0)]])
        g["Z"] = Glyph(width: 0.6, strokes: [[p(0, 1), p(0.6, 1), p(0, 0), p(0.6, 0)]])

        // MARK: Proper lowercase (x-height ≈ 0.7; not scaled caps)
        g["a"] = Glyph(width: 0.55, strokes: [
            [p(0.5, 0.55), p(0.35, 0.7), p(0.15, 0.7), p(0.05, 0.55), p(0.05, 0.2), p(0.15, 0), p(0.35, 0), p(0.5, 0.15), p(0.5, 0.7)],
        ])
        g["b"] = Glyph(width: 0.55, strokes: [
            [p(0.05, 1), p(0.05, 0)],
            [p(0.05, 0.55), p(0.25, 0.7), p(0.4, 0.7), p(0.5, 0.55), p(0.5, 0.15), p(0.4, 0), p(0.25, 0), p(0.05, 0.15)],
        ])
        g["c"] = Glyph(width: 0.5, strokes: [
            [p(0.45, 0.6), p(0.3, 0.7), p(0.15, 0.65), p(0.05, 0.45), p(0.05, 0.25), p(0.15, 0.05), p(0.3, 0), p(0.45, 0.1)],
        ])
        g["d"] = Glyph(width: 0.55, strokes: [
            [p(0.5, 1), p(0.5, 0)],
            [p(0.5, 0.55), p(0.3, 0.7), p(0.15, 0.7), p(0.05, 0.55), p(0.05, 0.15), p(0.15, 0), p(0.3, 0), p(0.5, 0.15)],
        ])
        g["e"] = Glyph(width: 0.55, strokes: [
            [p(0.05, 0.35), p(0.5, 0.35), p(0.45, 0.55), p(0.3, 0.7), p(0.15, 0.65), p(0.05, 0.45), p(0.05, 0.2), p(0.15, 0), p(0.35, 0), p(0.5, 0.1)],
        ])
        g["f"] = Glyph(width: 0.4, strokes: [
            [p(0.35, 1), p(0.2, 1), p(0.15, 0.85), p(0.15, 0)],
            [p(0.05, 0.7), p(0.35, 0.7)],
        ])
        g["g"] = Glyph(width: 0.55, strokes: [
            [p(0.5, 0.7), p(0.5, -0.05), p(0.35, -0.25), p(0.15, -0.25), p(0.05, -0.1)],
            [p(0.5, 0.5), p(0.35, 0.7), p(0.15, 0.7), p(0.05, 0.55), p(0.05, 0.2), p(0.15, 0), p(0.35, 0), p(0.5, 0.15)],
        ])
        g["h"] = Glyph(width: 0.55, strokes: [
            [p(0.05, 1), p(0.05, 0)],
            [p(0.05, 0.45), p(0.2, 0.7), p(0.35, 0.7), p(0.5, 0.5), p(0.5, 0)],
        ])
        g["i"] = Glyph(width: 0.22, strokes: [
            [p(0.1, 0.7), p(0.1, 0)],
            [p(0.1, 0.95), p(0.1, 0.85)],
        ])
        g["j"] = Glyph(width: 0.3, strokes: [
            [p(0.18, 0.7), p(0.18, -0.05), p(0.08, -0.25), p(0.0, -0.2)],
            [p(0.18, 0.95), p(0.18, 0.85)],
        ])
        g["k"] = Glyph(width: 0.5, strokes: [
            [p(0.05, 1), p(0.05, 0)],
            [p(0.45, 0.7), p(0.05, 0.3), p(0.5, 0)],
        ])
        g["l"] = Glyph(width: 0.22, strokes: [
            [p(0.1, 1), p(0.1, 0)],
        ])
        g["m"] = Glyph(width: 0.8, strokes: [
            [p(0.05, 0), p(0.05, 0.7)],
            [p(0.05, 0.45), p(0.2, 0.7), p(0.35, 0.7), p(0.4, 0.5), p(0.4, 0)],
            [p(0.4, 0.45), p(0.55, 0.7), p(0.7, 0.7), p(0.75, 0.5), p(0.75, 0)],
        ])
        g["n"] = Glyph(width: 0.55, strokes: [
            [p(0.05, 0), p(0.05, 0.7)],
            [p(0.05, 0.45), p(0.2, 0.7), p(0.35, 0.7), p(0.5, 0.5), p(0.5, 0)],
        ])
        g["o"] = Glyph(width: 0.55, strokes: [
            [p(0.275, 0), p(0.1, 0.1), p(0.05, 0.35), p(0.1, 0.6), p(0.275, 0.7), p(0.45, 0.6), p(0.5, 0.35), p(0.45, 0.1), p(0.275, 0)],
        ])
        g["p"] = Glyph(width: 0.55, strokes: [
            [p(0.05, 0.7), p(0.05, -0.28)],
            [p(0.05, 0.55), p(0.25, 0.7), p(0.4, 0.7), p(0.5, 0.55), p(0.5, 0.2), p(0.4, 0), p(0.25, 0), p(0.05, 0.15)],
        ])
        g["q"] = Glyph(width: 0.55, strokes: [
            [p(0.5, 0.7), p(0.5, -0.28)],
            [p(0.5, 0.55), p(0.3, 0.7), p(0.15, 0.7), p(0.05, 0.55), p(0.05, 0.2), p(0.15, 0), p(0.3, 0), p(0.5, 0.15)],
        ])
        g["r"] = Glyph(width: 0.4, strokes: [
            [p(0.05, 0), p(0.05, 0.7)],
            [p(0.05, 0.45), p(0.2, 0.7), p(0.35, 0.7)],
        ])
        g["s"] = Glyph(width: 0.45, strokes: [
            [p(0.4, 0.6), p(0.25, 0.7), p(0.1, 0.65), p(0.1, 0.5), p(0.35, 0.35), p(0.4, 0.2), p(0.3, 0), p(0.1, 0.05)],
        ])
        g["t"] = Glyph(width: 0.4, strokes: [
            [p(0.15, 1), p(0.15, 0.15), p(0.25, 0), p(0.35, 0.05)],
            [p(0.05, 0.7), p(0.35, 0.7)],
        ])
        g["u"] = Glyph(width: 0.55, strokes: [
            [p(0.05, 0.7), p(0.05, 0.2), p(0.15, 0), p(0.35, 0), p(0.5, 0.2), p(0.5, 0.7)],
            [p(0.5, 0.7), p(0.5, 0)],
        ])
        g["v"] = Glyph(width: 0.55, strokes: [
            [p(0.05, 0.7), p(0.275, 0), p(0.5, 0.7)],
        ])
        g["w"] = Glyph(width: 0.8, strokes: [
            [p(0.05, 0.7), p(0.2, 0), p(0.4, 0.55), p(0.6, 0), p(0.75, 0.7)],
        ])
        g["x"] = Glyph(width: 0.5, strokes: [
            [p(0.05, 0.7), p(0.45, 0)],
            [p(0.45, 0.7), p(0.05, 0)],
        ])
        g["y"] = Glyph(width: 0.55, strokes: [
            [p(0.05, 0.7), p(0.275, 0.15)],
            [p(0.5, 0.7), p(0.275, 0.15), p(0.15, -0.25)],
        ])
        g["z"] = Glyph(width: 0.5, strokes: [
            [p(0.05, 0.7), p(0.45, 0.7), p(0.05, 0), p(0.45, 0)],
        ])

        // MARK: Digits
        g["0"] = Glyph(width: 0.6, strokes: [[p(0.3, 0), p(0.05, 0.2), p(0.05, 0.8), p(0.3, 1), p(0.55, 0.8), p(0.55, 0.2), p(0.3, 0)]])
        g["1"] = Glyph(width: 0.35, strokes: [[p(0.05, 0.8), p(0.2, 1), p(0.2, 0)]])
        g["2"] = Glyph(width: 0.55, strokes: [[p(0.05, 0.8), p(0.25, 1), p(0.5, 0.8), p(0.5, 0.6), p(0.05, 0), p(0.55, 0)]])
        g["3"] = Glyph(width: 0.55, strokes: [[p(0.05, 1), p(0.5, 1), p(0.25, 0.55), p(0.5, 0.35), p(0.5, 0.15), p(0.25, 0), p(0.05, 0.15)]])
        g["4"] = Glyph(width: 0.6, strokes: [[p(0.45, 0), p(0.45, 1), p(0.05, 0.4), p(0.55, 0.4)]])
        g["5"] = Glyph(width: 0.55, strokes: [[p(0.5, 1), p(0.1, 1), p(0.05, 0.55), p(0.4, 0.55), p(0.55, 0.35), p(0.5, 0.1), p(0.25, 0), p(0.05, 0.15)]])
        g["6"] = Glyph(width: 0.55, strokes: [[p(0.45, 1), p(0.15, 0.85), p(0.05, 0.4), p(0.2, 0), p(0.45, 0.1), p(0.5, 0.35), p(0.35, 0.55), p(0.1, 0.45)]])
        g["7"] = Glyph(width: 0.55, strokes: [[p(0.05, 1), p(0.55, 1), p(0.2, 0)]])
        g["8"] = Glyph(width: 0.55, strokes: [[p(0.275, 0.55), p(0.05, 0.7), p(0.05, 0.9), p(0.275, 1), p(0.5, 0.9), p(0.5, 0.7), p(0.275, 0.55), p(0.05, 0.35), p(0.05, 0.1), p(0.275, 0), p(0.5, 0.1), p(0.5, 0.35), p(0.275, 0.55)]])
        g["9"] = Glyph(width: 0.55, strokes: [[p(0.1, 0), p(0.4, 0.15), p(0.5, 0.6), p(0.35, 1), p(0.1, 0.9), p(0.05, 0.65), p(0.2, 0.45), p(0.45, 0.55)]])

        // MARK: Punctuation — letters, addresses, light markup
        g["."] = Glyph(width: 0.25, strokes: [[p(0.1, 0), p(0.15, 0.05), p(0.1, 0.1), p(0.05, 0.05), p(0.1, 0)]])
        g[","] = Glyph(width: 0.25, strokes: [[p(0.15, 0.1), p(0.1, 0), p(0.05, -0.15)]])
        g[";"] = Glyph(width: 0.25, strokes: [
            [p(0.1, 0.7), p(0.1, 0.6)],
            [p(0.15, 0.1), p(0.1, 0), p(0.05, -0.15)],
        ])
        g[":"] = Glyph(width: 0.2, strokes: [[p(0.1, 0.7), p(0.1, 0.6)], [p(0.1, 0.2), p(0.1, 0.1)]])
        g["!"] = Glyph(width: 0.2, strokes: [[p(0.1, 1), p(0.1, 0.3)], [p(0.1, 0.1), p(0.1, 0)]])
        g["?"] = Glyph(width: 0.5, strokes: [[p(0.05, 0.8), p(0.2, 1), p(0.4, 0.85), p(0.25, 0.55)], [p(0.25, 0.15), p(0.25, 0.05)]])
        g["'"] = Glyph(width: 0.2, strokes: [[p(0.1, 1), p(0.1, 0.75)]])
        g["\""] = Glyph(width: 0.35, strokes: [
            [p(0.08, 1), p(0.08, 0.75)],
            [p(0.25, 1), p(0.25, 0.75)],
        ])
        g["-"] = Glyph(width: 0.45, strokes: [[p(0.05, 0.5), p(0.4, 0.5)]])
        g["_"] = Glyph(width: 0.55, strokes: [[p(0.0, 0), p(0.5, 0)]])
        g["/"] = Glyph(width: 0.45, strokes: [[p(0.4, 1), p(0.05, 0)]])
        g["\\"] = Glyph(width: 0.45, strokes: [[p(0.05, 1), p(0.4, 0)]])
        g["("] = Glyph(width: 0.35, strokes: [[p(0.3, 1), p(0.1, 0.75), p(0.05, 0.5), p(0.1, 0.25), p(0.3, 0)]])
        g[")"] = Glyph(width: 0.35, strokes: [[p(0.05, 1), p(0.25, 0.75), p(0.3, 0.5), p(0.25, 0.25), p(0.05, 0)]])
        g["["] = Glyph(width: 0.35, strokes: [[p(0.3, 1), p(0.05, 1), p(0.05, 0), p(0.3, 0)]])
        g["]"] = Glyph(width: 0.35, strokes: [[p(0.05, 1), p(0.3, 1), p(0.3, 0), p(0.05, 0)]])
        g["{"] = Glyph(width: 0.4, strokes: [[p(0.3, 1), p(0.15, 1), p(0.1, 0.85), p(0.1, 0.6), p(0.0, 0.5), p(0.1, 0.4), p(0.1, 0.15), p(0.15, 0), p(0.3, 0)]])
        g["}"] = Glyph(width: 0.4, strokes: [[p(0.1, 1), p(0.25, 1), p(0.3, 0.85), p(0.3, 0.6), p(0.4, 0.5), p(0.3, 0.4), p(0.3, 0.15), p(0.25, 0), p(0.1, 0)]])
        g["@"] = Glyph(width: 0.85, strokes: [
            [p(0.55, 0.35), p(0.55, 0.55), p(0.4, 0.7), p(0.25, 0.55), p(0.25, 0.3), p(0.4, 0.15), p(0.55, 0.3), p(0.55, 0.55)],
            [p(0.7, 0.45), p(0.7, 0.7), p(0.45, 0.95), p(0.15, 0.75), p(0.05, 0.4), p(0.15, 0.1), p(0.45, -0.05), p(0.7, 0.15)],
        ])
        g["#"] = Glyph(width: 0.65, strokes: [
            [p(0.2, 0), p(0.3, 1)],
            [p(0.4, 0), p(0.5, 1)],
            [p(0.05, 0.65), p(0.6, 0.65)],
            [p(0.05, 0.35), p(0.6, 0.35)],
        ])
        g["&"] = Glyph(width: 0.7, strokes: [
            [p(0.65, 0.3), p(0.35, 0), p(0.1, 0.15), p(0.1, 0.35), p(0.55, 0.7), p(0.35, 1), p(0.15, 0.85), p(0.2, 0.6), p(0.65, 0)],
        ])
        g["+"] = Glyph(width: 0.5, strokes: [
            [p(0.05, 0.5), p(0.45, 0.5)],
            [p(0.25, 0.75), p(0.25, 0.25)],
        ])
        g["="] = Glyph(width: 0.5, strokes: [
            [p(0.05, 0.6), p(0.45, 0.6)],
            [p(0.05, 0.35), p(0.45, 0.35)],
        ])
        g["%"] = Glyph(width: 0.7, strokes: [
            [p(0.1, 0.85), p(0.2, 1), p(0.3, 0.85), p(0.2, 0.7), p(0.1, 0.85)],
            [p(0.4, 0.15), p(0.5, 0.3), p(0.6, 0.15), p(0.5, 0), p(0.4, 0.15)],
            [p(0.55, 1), p(0.15, 0)],
        ])
        g["$"] = Glyph(width: 0.55, strokes: [
            [p(0.5, 0.85), p(0.3, 1), p(0.1, 0.9), p(0.1, 0.7), p(0.45, 0.45), p(0.5, 0.25), p(0.35, 0), p(0.1, 0.1)],
            [p(0.275, 1.05), p(0.275, -0.05)],
        ])
        g["*"] = Glyph(width: 0.45, strokes: [
            [p(0.2, 0.85), p(0.2, 0.35)],
            [p(0.05, 0.75), p(0.35, 0.45)],
            [p(0.35, 0.75), p(0.05, 0.45)],
        ])
        g["<"] = Glyph(width: 0.5, strokes: [[p(0.45, 0.85), p(0.05, 0.5), p(0.45, 0.15)]])
        g[">"] = Glyph(width: 0.5, strokes: [[p(0.05, 0.85), p(0.45, 0.5), p(0.05, 0.15)]])
        g["~"] = Glyph(width: 0.55, strokes: [[p(0.05, 0.45), p(0.2, 0.6), p(0.35, 0.4), p(0.5, 0.55)]])
        g["`"] = Glyph(width: 0.25, strokes: [[p(0.05, 1), p(0.2, 0.8)]])
        g["|"] = Glyph(width: 0.2, strokes: [[p(0.1, 1), p(0.1, 0)]])
        g["^"] = Glyph(width: 0.5, strokes: [[p(0.05, 0.7), p(0.25, 1), p(0.45, 0.7)]])

        return g
    }
}
