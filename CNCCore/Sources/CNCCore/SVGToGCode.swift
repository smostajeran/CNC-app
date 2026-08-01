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

/// SVG path importer: path `d`, rect/line/polyline/polygon/circle/ellipse, with curve tessellation.
public enum SVGToGCode {
    public static func plotJob(
        from svg: String,
        profile: MachineProfile = .ta4,
        fitToWorkspace: Bool = true
    ) throws -> PlotJob {
        var commands = try extractCommands(from: svg)
        guard !commands.isEmpty else { throw SVGToGCodeError.noPaths }

        // Honor root viewBox origin (Inkscape often uses non-zero minX/minY).
        if let vb = parseViewBox(svg), (vb.minX != 0 || vb.minY != 0) {
            let shift = Affine2D.translate(tx: -vb.minX, ty: -vb.minY)
            commands = applyAffine(commands, shift)
        }

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
            case .penChange(let label):
                if penDown {
                    lines.append("G0 Z\(fmt(profile.penUpZ))")
                    penDown = false
                }
                lines.append("; >>> PEN CHANGE: \(label) — click Resume when ready")
                lines.append("M0")
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
        var layers: [(color: String?, commands: [PlotCommand])] = []

        // Prefer grouped layers with stroke colors (Inkscape multi-pen workflow).
        let groupPattern = #"<g\b([^>]*)>(.*?)</g>"#
        if let groupRegex = try? NSRegularExpression(
            pattern: groupPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
            let range = NSRange(svg.startIndex..., in: svg)
            let groupMatches = groupRegex.matches(in: svg, options: [], range: range)
            if !groupMatches.isEmpty {
                for match in groupMatches {
                    guard let attrsR = Range(match.range(at: 1), in: svg),
                          let bodyR = Range(match.range(at: 2), in: svg) else { continue }
                    let attrs = String(svg[attrsR])
                    let body = String(svg[bodyR])
                    let color = strokeColor(in: attrs) ?? strokeColor(in: body)
                    let groupXf = parseTransform(attrs) ?? .identity
                    let cmds = applyAffine(extractPrimitiveCommands(from: body), groupXf)
                    if !cmds.isEmpty {
                        layers.append((color, cmds))
                    }
                }
            }
        }

        if layers.isEmpty {
            let cmds = extractPrimitiveCommands(from: svg)
            if !cmds.isEmpty { layers.append((nil, cmds)) }
        }

        var commands: [PlotCommand] = []
        var seenFirstDrawable = false
        for layer in layers {
            if seenFirstDrawable, let color = layer.color, color.lowercased() != "none" {
                commands.append(.penChange(color))
            }
            if !layer.commands.isEmpty { seenFirstDrawable = true }
            commands.append(contentsOf: layer.commands)
        }

        // Fallback: if no groups but multiple stroked paths with different colors
        if layers.count <= 1 {
            commands = extractPrimitiveCommands(from: svg)
            let colored = extractColoredPathCommands(from: svg)
            if colored.count > 1 {
                commands = []
                for (idx, item) in colored.enumerated() {
                    if idx > 0 { commands.append(.penChange(item.color)) }
                    commands.append(contentsOf: item.commands)
                }
            }
        }

        if commands.isEmpty { throw SVGToGCodeError.noPaths }
        return commands
    }

    private static func extractColoredPathCommands(from svg: String) -> [(color: String, commands: [PlotCommand])] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<path\b([^>]*)>"#,
            options: [.caseInsensitive]
        ) else { return [] }
        let range = NSRange(svg.startIndex..., in: svg)
        var result: [(String, [PlotCommand])] = []
        for match in regex.matches(in: svg, options: [], range: range) {
            guard let r = Range(match.range(at: 1), in: svg) else { continue }
            let attrs = String(svg[r])
            guard let d = attrString(attrs, "d") else { continue }
            let color = strokeColor(in: attrs) ?? "#000000"
            let xf = parseTransform(attrs) ?? .identity
            let cmds = applyAffine(parsePathD(d), xf)
            if !cmds.isEmpty { result.append((color, cmds)) }
        }
        let colors = Set(result.map(\.0))
        return colors.count > 1 ? result : []
    }

    private static func extractPrimitiveCommands(from svg: String) -> [PlotCommand] {
        var commands: [PlotCommand] = []

        for element in matches(svg, pattern: #"<path\b[^>]*>"#) {
            guard let d = attrString(element, "d") else { continue }
            let xf = parseTransform(element) ?? .identity
            commands.append(contentsOf: applyAffine(parsePathD(d), xf))
        }
        for element in matches(svg, pattern: #"<polyline\b[^>]*>"#) {
            guard let pts = attrString(element, "points") else { continue }
            let xf = parseTransform(element) ?? .identity
            commands.append(contentsOf: applyAffine(polylineCommands(pts, closed: false), xf))
        }
        for element in matches(svg, pattern: #"<polygon\b[^>]*>"#) {
            guard let pts = attrString(element, "points") else { continue }
            let xf = parseTransform(element) ?? .identity
            commands.append(contentsOf: applyAffine(polylineCommands(pts, closed: true), xf))
        }
        for element in matches(svg, pattern: #"<line\b[^>]*>"#) {
            if let lineCmds = parseLineElement(element) {
                let xf = parseTransform(element) ?? .identity
                commands.append(contentsOf: applyAffine(lineCmds, xf))
            }
        }
        for element in matches(svg, pattern: #"<rect\b[^>]*>"#) {
            if let rectCmds = parseRectElement(element) {
                let xf = parseTransform(element) ?? .identity
                commands.append(contentsOf: applyAffine(rectCmds, xf))
            }
        }
        for element in matches(svg, pattern: #"<circle\b[^>]*>"#) {
            if let circleCmds = parseCircleElement(element) {
                let xf = parseTransform(element) ?? .identity
                commands.append(contentsOf: applyAffine(circleCmds, xf))
            }
        }
        for element in matches(svg, pattern: #"<ellipse\b[^>]*>"#) {
            if let ellipseCmds = parseEllipseElement(element) {
                let xf = parseTransform(element) ?? .identity
                commands.append(contentsOf: applyAffine(ellipseCmds, xf))
            }
        }
        return commands
    }

    // MARK: - viewBox / transform

    struct ViewBox {
        var minX: Double
        var minY: Double
        var width: Double
        var height: Double
    }

    struct Affine2D: Equatable {
        var a: Double, b: Double, c: Double, d: Double, e: Double, f: Double

        static let identity = Affine2D(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0)

        static func translate(tx: Double, ty: Double) -> Affine2D {
            Affine2D(a: 1, b: 0, c: 0, d: 1, e: tx, f: ty)
        }

        static func scale(sx: Double, sy: Double) -> Affine2D {
            Affine2D(a: sx, b: 0, c: 0, d: sy, e: 0, f: 0)
        }

        func apply(_ p: PlotPoint) -> PlotPoint {
            PlotPoint(x: a * p.x + c * p.y + e, y: b * p.x + d * p.y + f)
        }

        func concatenating(_ o: Affine2D) -> Affine2D {
            // self ∘ o  (apply o first, then self)
            Affine2D(
                a: a * o.a + c * o.b,
                b: b * o.a + d * o.b,
                c: a * o.c + c * o.d,
                d: b * o.c + d * o.d,
                e: a * o.e + c * o.f + e,
                f: b * o.e + d * o.f + f
            )
        }
    }

    static func parseViewBox(_ svg: String) -> ViewBox? {
        guard let regex = try? NSRegularExpression(
            pattern: #"viewBox\s*=\s*["']([^"']+)["']"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(svg.startIndex..., in: svg)
        guard let match = regex.firstMatch(in: svg, options: [], range: range),
              let r = Range(match.range(at: 1), in: svg) else { return nil }
        let parts = String(svg[r])
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return ViewBox(minX: parts[0], minY: parts[1], width: parts[2], height: parts[3])
    }

    /// Parses simple `transform="translate(..) scale(..) matrix(..)"` lists.
    static func parseTransform(_ attrs: String) -> Affine2D? {
        guard let raw = attrString(attrs, "transform") else { return nil }
        var result = Affine2D.identity
        guard let regex = try? NSRegularExpression(
            pattern: #"(translate|scale|matrix)\s*\(([^)]*)\)"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(raw.startIndex..., in: raw)
        for match in regex.matches(in: raw, options: [], range: range) {
            guard let nameR = Range(match.range(at: 1), in: raw),
                  let argsR = Range(match.range(at: 2), in: raw) else { continue }
            let name = String(raw[nameR]).lowercased()
            let nums = String(raw[argsR])
                .replacingOccurrences(of: ",", with: " ")
                .split(whereSeparator: { $0.isWhitespace })
                .compactMap { Double($0) }
            let next: Affine2D?
            switch name {
            case "translate":
                guard let tx = nums.first else { next = nil; break }
                next = .translate(tx: tx, ty: nums.count > 1 ? nums[1] : 0)
            case "scale":
                guard let sx = nums.first else { next = nil; break }
                next = .scale(sx: sx, sy: nums.count > 1 ? nums[1] : sx)
            case "matrix":
                guard nums.count >= 6 else { next = nil; break }
                next = Affine2D(a: nums[0], b: nums[1], c: nums[2], d: nums[3], e: nums[4], f: nums[5])
            default:
                next = nil
            }
            if let next {
                result = result.concatenating(next)
            }
        }
        return result
    }

    static func applyAffine(_ commands: [PlotCommand], _ xf: Affine2D) -> [PlotCommand] {
        if xf == .identity { return commands }
        return commands.map { cmd in
            switch cmd {
            case .move(let p): return .move(xf.apply(p))
            case .line(let p): return .line(xf.apply(p))
            case .penChange(let label): return .penChange(label)
            }
        }
    }

    private static func strokeColor(in text: String) -> String? {
        if let s = attrString(text, "stroke"), s.lowercased() != "none" { return s }
        // style="stroke:#f00"
        guard let regex = try? NSRegularExpression(
            pattern: #"stroke\s*:\s*([^;\"']+)"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let r = Range(match.range(at: 1), in: text) else { return nil }
        let value = String(text[r]).trimmingCharacters(in: .whitespaces)
        return value.lowercased() == "none" ? nil : value
    }

    private static func attrString(_ element: String, _ name: String) -> String? {
        let pattern = #"\#(name)=["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(element.startIndex..., in: element)
        guard let match = regex.firstMatch(in: element, options: [], range: range),
              let r = Range(match.range(at: 1), in: element) else { return nil }
        return String(element[r])
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

    private static func parseCircleElement(_ element: String) -> [PlotCommand]? {
        guard let cx = attr(element, "cx"),
              let cy = attr(element, "cy"),
              let r = attr(element, "r"),
              r > 0 else { return nil }
        return ellipseCommands(cx: cx, cy: cy, rx: r, ry: r)
    }

    private static func parseEllipseElement(_ element: String) -> [PlotCommand]? {
        guard let cx = attr(element, "cx"),
              let cy = attr(element, "cy"),
              let rx = attr(element, "rx"),
              let ry = attr(element, "ry"),
              rx > 0, ry > 0 else { return nil }
        return ellipseCommands(cx: cx, cy: cy, rx: rx, ry: ry)
    }

    private static func ellipseCommands(cx: Double, cy: Double, rx: Double, ry: Double, segments: Int = 48) -> [PlotCommand] {
        var cmds: [PlotCommand] = []
        for i in 0...segments {
            let t = Double(i) / Double(segments) * 2 * .pi
            let p = PlotPoint(x: cx + rx * cos(t), y: cy + ry * sin(t))
            cmds.append(i == 0 ? .move(p) : .line(p))
        }
        return cmds
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

    /// SVG path `d` — lines plus cubic/quadratic/arc tessellation.
    public static func parsePathD(_ d: String) -> [PlotCommand] {
        let tokens = tokenizePath(d)
        var commands: [PlotCommand] = []
        var i = 0
        var cx = 0.0
        var cy = 0.0
        var startX = 0.0
        var startY = 0.0
        var lastCtrlX = 0.0
        var lastCtrlY = 0.0
        var lastWasCubic = false
        var lastWasQuad = false

        func takeNumber() -> Double? {
            guard i < tokens.count, let v = Double(tokens[i]) else { return nil }
            i += 1
            return v
        }

        func appendLine(_ x: Double, _ y: Double) {
            cx = x; cy = y
            commands.append(.line(PlotPoint(x: cx, y: cy)))
            lastWasCubic = false
            lastWasQuad = false
        }

        while i < tokens.count {
            let t = tokens[i]
            if Double(t) != nil {
                if let x = takeNumber(), let y = takeNumber() {
                    appendLine(x, y)
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
                lastWasCubic = false; lastWasQuad = false
                while let x2 = takeNumber(), let y2 = takeNumber() {
                    appendLine(x2, y2)
                }
            case "m":
                guard let x = takeNumber(), let y = takeNumber() else { continue }
                cx += x; cy += y
                startX = cx; startY = cy
                commands.append(.move(PlotPoint(x: cx, y: cy)))
                lastWasCubic = false; lastWasQuad = false
                while let x2 = takeNumber(), let y2 = takeNumber() {
                    appendLine(cx + x2, cy + y2)
                }
            case "L":
                while let x = takeNumber(), let y = takeNumber() { appendLine(x, y) }
            case "l":
                while let x = takeNumber(), let y = takeNumber() { appendLine(cx + x, cy + y) }
            case "H":
                while let x = takeNumber() { appendLine(x, cy) }
            case "h":
                while let x = takeNumber() { appendLine(cx + x, cy) }
            case "V":
                while let y = takeNumber() { appendLine(cx, y) }
            case "v":
                while let y = takeNumber() { appendLine(cx, cy + y) }
            case "Z", "z":
                if !commands.isEmpty {
                    commands.append(.line(PlotPoint(x: startX, y: startY)))
                    cx = startX; cy = startY
                }
                lastWasCubic = false; lastWasQuad = false
            case "C":
                while let x1 = takeNumber(), let y1 = takeNumber(),
                      let x2 = takeNumber(), let y2 = takeNumber(),
                      let x = takeNumber(), let y = takeNumber() {
                    appendCubic(x0: cx, y0: cy, x1: x1, y1: y1, x2: x2, y2: y2, x3: x, y3: y, into: &commands)
                    lastCtrlX = x2; lastCtrlY = y2
                    cx = x; cy = y
                    lastWasCubic = true; lastWasQuad = false
                }
            case "c":
                while let dx1 = takeNumber(), let dy1 = takeNumber(),
                      let dx2 = takeNumber(), let dy2 = takeNumber(),
                      let dx = takeNumber(), let dy = takeNumber() {
                    let x1 = cx + dx1, y1 = cy + dy1
                    let x2 = cx + dx2, y2 = cy + dy2
                    let x = cx + dx, y = cy + dy
                    appendCubic(x0: cx, y0: cy, x1: x1, y1: y1, x2: x2, y2: y2, x3: x, y3: y, into: &commands)
                    lastCtrlX = x2; lastCtrlY = y2
                    cx = x; cy = y
                    lastWasCubic = true; lastWasQuad = false
                }
            case "S":
                while let x2 = takeNumber(), let y2 = takeNumber(),
                      let x = takeNumber(), let y = takeNumber() {
                    let x1 = lastWasCubic ? 2 * cx - lastCtrlX : cx
                    let y1 = lastWasCubic ? 2 * cy - lastCtrlY : cy
                    appendCubic(x0: cx, y0: cy, x1: x1, y1: y1, x2: x2, y2: y2, x3: x, y3: y, into: &commands)
                    lastCtrlX = x2; lastCtrlY = y2
                    cx = x; cy = y
                    lastWasCubic = true; lastWasQuad = false
                }
            case "s":
                while let dx2 = takeNumber(), let dy2 = takeNumber(),
                      let dx = takeNumber(), let dy = takeNumber() {
                    let x1 = lastWasCubic ? 2 * cx - lastCtrlX : cx
                    let y1 = lastWasCubic ? 2 * cy - lastCtrlY : cy
                    let x2 = cx + dx2, y2 = cy + dy2
                    let x = cx + dx, y = cy + dy
                    appendCubic(x0: cx, y0: cy, x1: x1, y1: y1, x2: x2, y2: y2, x3: x, y3: y, into: &commands)
                    lastCtrlX = x2; lastCtrlY = y2
                    cx = x; cy = y
                    lastWasCubic = true; lastWasQuad = false
                }
            case "Q":
                while let x1 = takeNumber(), let y1 = takeNumber(),
                      let x = takeNumber(), let y = takeNumber() {
                    appendQuad(x0: cx, y0: cy, x1: x1, y1: y1, x2: x, y2: y, into: &commands)
                    lastCtrlX = x1; lastCtrlY = y1
                    cx = x; cy = y
                    lastWasQuad = true; lastWasCubic = false
                }
            case "q":
                while let dx1 = takeNumber(), let dy1 = takeNumber(),
                      let dx = takeNumber(), let dy = takeNumber() {
                    let x1 = cx + dx1, y1 = cy + dy1
                    let x = cx + dx, y = cy + dy
                    appendQuad(x0: cx, y0: cy, x1: x1, y1: y1, x2: x, y2: y, into: &commands)
                    lastCtrlX = x1; lastCtrlY = y1
                    cx = x; cy = y
                    lastWasQuad = true; lastWasCubic = false
                }
            case "T":
                while let x = takeNumber(), let y = takeNumber() {
                    let x1 = lastWasQuad ? 2 * cx - lastCtrlX : cx
                    let y1 = lastWasQuad ? 2 * cy - lastCtrlY : cy
                    appendQuad(x0: cx, y0: cy, x1: x1, y1: y1, x2: x, y2: y, into: &commands)
                    lastCtrlX = x1; lastCtrlY = y1
                    cx = x; cy = y
                    lastWasQuad = true; lastWasCubic = false
                }
            case "t":
                while let dx = takeNumber(), let dy = takeNumber() {
                    let x1 = lastWasQuad ? 2 * cx - lastCtrlX : cx
                    let y1 = lastWasQuad ? 2 * cy - lastCtrlY : cy
                    let x = cx + dx, y = cy + dy
                    appendQuad(x0: cx, y0: cy, x1: x1, y1: y1, x2: x, y2: y, into: &commands)
                    lastCtrlX = x1; lastCtrlY = y1
                    cx = x; cy = y
                    lastWasQuad = true; lastWasCubic = false
                }
            case "A", "a":
                let relative = cmd == "a"
                while let rx = takeNumber(), let ry = takeNumber(),
                      let rot = takeNumber(),
                      let large = takeNumber(), let sweep = takeNumber(),
                      let x = takeNumber(), let y = takeNumber() {
                    let endX = relative ? cx + x : x
                    let endY = relative ? cy + y : y
                    appendArc(
                        x0: cx, y0: cy,
                        rx: abs(rx), ry: abs(ry),
                        xAxisRotDeg: rot,
                        largeArc: large != 0,
                        sweep: sweep != 0,
                        x: endX, y: endY,
                        into: &commands
                    )
                    cx = endX; cy = endY
                    lastWasCubic = false; lastWasQuad = false
                }
            default:
                while i < tokens.count, Double(tokens[i]) != nil { i += 1 }
            }
        }
        return commands
    }

    private static func appendCubic(
        x0: Double, y0: Double,
        x1: Double, y1: Double,
        x2: Double, y2: Double,
        x3: Double, y3: Double,
        into commands: inout [PlotCommand],
        segments: Int = 16
    ) {
        for i in 1...segments {
            let t = Double(i) / Double(segments)
            let u = 1 - t
            let x = u*u*u*x0 + 3*u*u*t*x1 + 3*u*t*t*x2 + t*t*t*x3
            let y = u*u*u*y0 + 3*u*u*t*y1 + 3*u*t*t*y2 + t*t*t*y3
            commands.append(.line(PlotPoint(x: x, y: y)))
        }
    }

    private static func appendQuad(
        x0: Double, y0: Double,
        x1: Double, y1: Double,
        x2: Double, y2: Double,
        into commands: inout [PlotCommand],
        segments: Int = 12
    ) {
        for i in 1...segments {
            let t = Double(i) / Double(segments)
            let u = 1 - t
            let x = u*u*x0 + 2*u*t*x1 + t*t*x2
            let y = u*u*y0 + 2*u*t*y1 + t*t*y2
            commands.append(.line(PlotPoint(x: x, y: y)))
        }
    }

    /// SVG elliptical arc → line segments (W3C endpoint-to-center).
    private static func appendArc(
        x0: Double, y0: Double,
        rx: Double, ry: Double,
        xAxisRotDeg: Double,
        largeArc: Bool,
        sweep: Bool,
        x: Double, y: Double,
        into commands: inout [PlotCommand],
        segments: Int = 24
    ) {
        if rx == 0 || ry == 0 {
            commands.append(.line(PlotPoint(x: x, y: y)))
            return
        }
        if abs(x0 - x) < 1e-9 && abs(y0 - y) < 1e-9 { return }

        let phi = xAxisRotDeg * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (x0 - x) / 2, dy = (y0 - y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        var rx_ = rx, ry_ = ry
        let lam = (x1p*x1p)/(rx_*rx_) + (y1p*y1p)/(ry_*ry_)
        if lam > 1 {
            let s = sqrt(lam)
            rx_ *= s; ry_ *= s
        }

        let sign: Double = (largeArc == sweep) ? -1 : 1
        let num = rx_*rx_*ry_*ry_ - rx_*rx_*y1p*y1p - ry_*ry_*x1p*x1p
        let den = rx_*rx_*y1p*y1p + ry_*ry_*x1p*x1p
        let coef = den == 0 ? 0 : sign * sqrt(max(0, num / den))
        let cxp = coef * (rx_ * y1p) / ry_
        let cyp = coef * (-ry_ * x1p) / rx_

        let cx = cosPhi * cxp - sinPhi * cyp + (x0 + x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (y0 + y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux*vx + uy*vy
            let len = sqrt(ux*ux + uy*uy) * sqrt(vx*vx + vy*vy)
            var ang = acos(min(max(dot / max(len, 1e-12), -1), 1))
            if ux*vy - uy*vx < 0 { ang = -ang }
            return ang
        }

        let v1x = (x1p - cxp) / rx_
        let v1y = (y1p - cyp) / ry_
        let v2x = (-x1p - cxp) / rx_
        let v2y = (-y1p - cyp) / ry_
        var theta1 = angle(1, 0, v1x, v1y)
        var dtheta = angle(v1x, v1y, v2x, v2y)
        if !sweep && dtheta > 0 { dtheta -= 2 * .pi }
        if sweep && dtheta < 0 { dtheta += 2 * .pi }

        for i in 1...segments {
            let t = Double(i) / Double(segments)
            let theta = theta1 + dtheta * t
            let xp = rx_ * cos(theta)
            let yp = ry_ * sin(theta)
            let px = cosPhi * xp - sinPhi * yp + cx
            let py = sinPhi * xp + cosPhi * yp + cy
            commands.append(.line(PlotPoint(x: px, y: py)))
        }
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

        let commands = job.commands.map { cmd -> PlotCommand in
            switch cmd {
            case .move(let p):
                return .move(transform(p, bounds: b, scale: scale, margin: margin, profile: profile))
            case .line(let p):
                return .line(transform(p, bounds: b, scale: scale, margin: margin, profile: profile))
            case .penChange(let label):
                return .penChange(label)
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
            case .penChange(let label):
                return .penChange(label)
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
