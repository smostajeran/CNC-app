import Foundation

public struct SerialPortInfo: Identifiable, Equatable, Sendable, Hashable {
    public var id: String { path }
    public let path: String
    public let name: String

    public init(path: String, name: String? = nil) {
        self.path = path
        self.name = name ?? URL(fileURLWithPath: path).lastPathComponent
    }
}

public enum SerialPortEnumerator {
    /// Preferred prefixes first (CH340 / Nano clones common on TA-4).
    private static let candidatePrefixes = [
        "/dev/cu.wchusbserial",
        "/dev/cu.usbserial",
        "/dev/cu.CH340",
        "/dev/cu.wch",
        "/dev/cu.usbmodem",
        "/dev/cu.SLAB_USBtoUART",
    ]

    /// Lists likely USB-serial devices (macOS `cu.*` preferred), ranked for TA-4 adapters.
    public static func listPorts() -> [SerialPortInfo] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: "/dev") else { return [] }

        let paths = items
            .filter { $0.hasPrefix("cu.") }
            .map { "/dev/\($0)" }
            .filter { path in
                candidatePrefixes.contains { path.hasPrefix($0) }
                    || path.contains("usbserial")
                    || path.contains("usbmodem")
                    || path.contains("wch")
                    || path.contains("SLAB")
                    || path.contains("CH340")
            }
            .sorted { lhs, rhs in
                let lp = preferenceRank(lhs)
                let rp = preferenceRank(rhs)
                if lp != rp { return lp < rp }
                return lhs < rhs
            }

        return paths.map { SerialPortInfo(path: $0) }
    }

    private static func preferenceRank(_ path: String) -> Int {
        if let idx = candidatePrefixes.firstIndex(where: { path.hasPrefix($0) }) {
            return idx
        }
        if path.contains("usbserial") { return 10 }
        if path.contains("wch") || path.contains("CH340") { return 11 }
        if path.contains("usbmodem") { return 12 }
        return 100
    }
}
