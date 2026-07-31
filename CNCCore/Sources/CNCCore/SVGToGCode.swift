import Foundation

public enum SVGToGCodeError: Error, LocalizedError, Equatable {
    case invalidSVG
    case noPaths

    public var errorDescription: String? {
        switch self {
        case .invalidSVG: return "Could not parse SVG"
        case .noPaths: return "SVG contained no drawable paths"
        }
    }
}

/// Minimal SVG path importer: `path d=` and `rect` / `line` / `polyline` / `polygon`.
public enum SVGToGCode {
    public static func plotJob(
        from svg: String,
        profile: MachineProfile = .ta4,
        fitToWorkspace: Bool = true
    ) throws -> PlotJob {
        let commands = try extractCommands(from: svg)
        guard !commands.isEmpty else { throw SVGToGCodeError.noPaths }

        var job = PlotJob(commands: commands)
        if fitToWorkspace {
            job = fit(job, into: profile)
        } else {
            job = clip(job, to: profile)
        }
        return job
    }

    public static func gcode(
        from svg: String,
        profile: MachineProfile = .ta4,
        fitToWorkspace: Bool = true
    ) throws -> String {
        let job = try plotJob(from: svg, profile: profile, fitToWorkspace: fitToWorkspace)
        return gcode(from: job, profile: profile)
    }

    public static func gcode(from job: PlotJob, profile: MachineProfile) -> String {
        var lines: [String] = [
            "; TA4Host SVG job",
            "G21",
            "G90",
            "G0 Z\(fmt(profile.penUpZ))",
        ]

        var penDown = false
        for cmd in job.commands {
            switch cmd {
            case .move(let p):
                if penDown {
                    lines.append("G0 Z\(fmt(profile.penUpZ))")
                    penDown = false
                }
                lines.append("G0 X\(fmt(p.x)) Y\(fmt(p.y))")
            case .line(let p):
                if !penDown {
                    lines.append("G1 Z\(fmt(profile.penDownZ)) F\(fmt(profile.drawFeed))")
                    penDown = true
                }
                lines.append("G1 X\(fmt(p.x)) Y\(fmt(p.y)) F\(fmt(profile.drawFeed))")
            }
        }

        if penDown {
            lines.append("G0 Z\(fmt(profile.penUpZ))")
        }
        lines.append("G0 X0 Y0")
        lines.append("M2")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Parse

    static func extractCommands(from svg: String) throws -> [PlotCommand] {
        var commands: [PlotCommand] = []

        for match in matches(svg, pattern: #"<path[^>]*\sd=["']([^"']+)["']"#) {
            commands.append(contentsOf: parsePathD(match))
        }
        for match in matches(svg, pattern: #"<polyline[^>]*\spoints=["']([^"']+)["']"#) {
            commands.append(contentsOf: polylineCommands(match, closed: false))
        }
        for match in matches(svg, pattern: #"<polygon[^>]*\spoints=["']([^"']+)["']"#) {
            commands.append(contentsOf: polylineCommands(match, closed: true))
        }
        for match in matches(svg, pattern: #"<line[^>]*>"#) {
            if let lineCmds = parseLineElement(match) {
                commands.append(contentsOf: lineCmds)
            }
        }
        for match in matches(svg, pattern: #"<rect[^>]*>"#) {
            if let rectCmds = parseRectElement(match) {
                commands.append(contentsOf: rectCmds)
            }
        }

        if commands.isEmpty { throw SVGToGCodeError.noPaths }
        return commands
    }

    private static func matches(_ text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { result in
            guard result.numberOfRanges > 1,
                  let r = Range(result.range(at: 1), in: text) else {
                if result.numberOfRanges == 1, let r = Range(result.range(at: 0), in: text) {
                    return String(text[r])
                }
                return nil
            }
            return String(text[r])
        }
    }

    private static func attr(_ element: String, _ name: String) -> Double? {
        let pattern = #"\#(name)=["']([-+0-9.eE]+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(element.startIndex..., in: element)
        guard let match = regex.firstMatch(in: element, options: [], range: range),
              let r = Range(match.range(at: 1), in: element) else { return nil }
        return Double(element[r])
    }

    private static func parseLineElement(_ element: String) -> [PlotCommand]? {
        guard let x1 = attr(element, "x1"),
              let y1 = attr(element, "y1"),
              let x2 = attr(element, "x2"),
              let y2 = attr(element, "y2") else { return nil }
        return [
            .move(PlotPoint(x: x1, y: y1)),
            .line(PlotPoint(x: x2, y: y2)),
        ]
    }

    private static func parseRectElement(_ element: String) -> [PlotCommand]? {
        guard let x = attr(element, "x") ?? Optional(0),
              let y = attr(element, "y") ?? Optional(0),
              let w = attr(element, "width"),
              let h = attr(element, "height"),
              w > 0, h > 0 else { return nil }
        let p1 = PlotPoint(x: x, y: y)
        let p2 = PlotPoint(x: x + w, y: y)
        let p3 = PlotPoint(x: x + w, y: y + h)
        let p4 = PlotPoint(x: x, y: y + h)
        return [.move(p1), .line(p2), .line(p3), .line(p4), .line(p1)]
    }

    private static func polylineCommands(_ points: String, closed: Bool) -> [PlotCommand] {
        let nums = points
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap { Double($0) }
        guard nums.count >= 4 else { return [] }
        var pts: [PlotPoint] = []
        var i = 0
        while i + 1 < nums.count {
            pts.append(PlotPoint(x: nums[i], y: nums[i + 1]))
            i += 2
        }
        guard let first = pts.first else { return [] }
        var cmds: [PlotCommand] = [.move(first)]
        for p in pts.dropFirst() {
            cmds.append(.line(p))
        }
        if closed {
            cmds.append(.line(first))
        }
        return cmds
    }

    /// Subset of SVG path `d` — M/m L/l H/h V/v Z/z and implied lineto after moveto.
    public static func parsePathD(_ d: String) -> [PlotCommand] {
        let tokens = tokenizePath(d)
        var commands: [PlotCommand] = []
        var i = 0
        var cx = 0.0
        var cy = 0.0
        var startX = 0.0
        var startY = 0.0
        var penIsDown = false

        func takeNumber() -> Double? {
            guard i < tokens.count, let v = Double(tokens[i]) else { return nil }
            i += 1
            return v
        }

        while i < tokens.count {
            let t = tokens[i]
            if let _ = Double(t) {
                // Implied lineto after previous command — treat as L absolute if last was absolute-ish.
                // Prefer relative/absolute from last command letter; default L.
                if let x = takeNumber(), let y = takeNumber() {
                    cx = x; cy = y
                    commands.append(.line(PlotPoint(x: cx, y: cy)))
                    penIsDown = true
                } else {
                    break
                }
                continue
            }

            let cmd = t
            i += 1
            switch cmd {
            case "M":
                guard let x = takeNumber(), let y = takeNumber() else { continue }
                cx = x; cy = y
                startX = cx; startY = cy
                commands.append(.move(PlotPoint(x: cx, y: cy)))
                penIsDown = false
                while let x2 = takeNumber(), let y2 = takeNumber() {
                    cx = x2; cy = y2
                    commands.append(.line(PlotPoint(x: cx, y: cy)))
                    penIsDown = true
                }
            case "m":
                guard let x = takeNumber(), let y = takeNumber() else { continue }
                cx += x; cy += y
                startX = cx; startY = cy
                commands.append(.move(PlotPoint(x: cx, y: cy)))
                penIsDown = false
                while let x2 = takeNumber(), let y2 = takeNumber() {
                    cx += x2; cy += y2
                    commands.append(.line(PlotPoint(x: cx, y: cy)))
                    penIsDown = true
                }
            case "L":
                while let x = takeNumber(), let y = takeNumber() {
                    cx = x; cy = y
                    commands.append(.line(PlotPoint(x: cx, y: cy)))
                    penIsDown = true
                }
            case "l":
                while let x = takeNumber(), let y = takeNumber() {
                    cx += x; cy += y
                    commands.append(.line(PlotPoint(x: cx, y: cy)))
                    penIsDown = true
                }
            case "H":
                while let x = takeNumber() {
                    cx = x
                    commands.append(.line(PlotPoint(x: cx, y: cy)))
                    penIsDown = true
                }
            case "h":
                while let x = takeNumber() {
                    cx += x
                    commands.append(.line(PlotPoint(x: cx, y: cy)))
                    penIsDown = true
                }
            case "V":
                while let y = takeNumber() {
                    cy = y
                    commands.append(.line(PlotPoint(x: cx, y: cy)))
                    penIsDown = true
                }
            case "v":
                while let y = takeNumber() {
                    cy += y
                    commands.append(.line(PlotPoint(x: cx, y: cy)))
                    penIsDown = true
                }
            case "Z", "z":
                if penIsDown || !commands.isEmpty {
                    commands.append(.line(PlotPoint(x: startX, y: startY)))
                    cx = startX; cy = startY
                }
            default:
                // Skip unsupported curve commands' numeric args until next letter.
                while i < tokens.count, Double(tokens[i]) != nil {
                    i += 1
                }
            }
        }
        return commands
    }

    private static func tokenizePath(_ d: String) -> [String] {
        var tokens: [String] = []
        var number = ""
        func flushNumber() {
            if !number.isEmpty {
                tokens.append(number)
                number = ""
            }
        }
        for ch in d {
            if ch.isLetter {
                flushNumber()
                tokens.append(String(ch))
            } else if ch == "-" || ch == "+" {
                if number.last == "e" || number.last == "E" {
                    number.append(ch)
                } else {
                    flushNumber()
                    number.append(ch)
                }
            } else if ch.isNumber || ch == "." || ch == "e" || ch == "E" {
                number.append(ch)
            } else {
                flushNumber()
            }
        }
        flushNumber()
        return tokens
    }

    // MARK: - Fit / clip

    static func fit(_ job: PlotJob, into profile: MachineProfile, margin: Double = 5) -> PlotJob {
        let b = job.bounds
        let usableW = max(profile.travelX - margin * 2, 1)
        let usableH = max(profile.travelY - margin * 2, 1)
        let bw = max(b.width, 0.001)
        let bh = max(b.height, 0.001)
        let scale = min(usableW / bw, usableH / bh)

        // SVG Y grows down; machine Y grows up — flip Y into workspace.
        let commands = job.commands.map { cmd -> PlotCommand in
            switch cmd {
            case .move(let p):
                return .move(transform(p, bounds: b, scale: scale, margin: margin, profile: profile))
            case .line(let p):
                return .line(transform(p, bounds: b, scale: scale, margin: margin, profile: profile))
            }
        }
        return PlotJob(commands: commands)
    }

    private static func transform(
        _ p: PlotPoint,
        bounds b: PlotBounds,
        scale: Double,
        margin: Double,
        profile: MachineProfile
    ) -> PlotPoint {
        let x = (p.x - b.minX) * scale + margin
        let yFromTop = (p.y - b.minY) * scale
        let y = profile.travelY - margin - yFromTop
        return PlotPoint(x: x, y: y)
    }

    static func clip(_ job: PlotJob, to profile: MachineProfile) -> PlotJob {
        let commands = job.commands.map { cmd -> PlotCommand in
            switch cmd {
            case .move(let p):
                return .move(PlotPoint(x: clamp(p.x, 0, profile.travelX), y: clamp(p.y, 0, profile.travelY)))
            case .line(let p):
                return .line(PlotPoint(x: clamp(p.x, 0, profile.travelX), y: clamp(p.y, 0, profile.travelY)))
            }
        }
        return PlotJob(commands: commands)
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }

    private static func fmt(_ v: Double) -> String {
        String(format: "%.3f", v)
    }
}
