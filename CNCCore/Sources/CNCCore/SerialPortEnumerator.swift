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
    private static let candidatePrefixes = [
        "/dev/cu.usbserial",
        "/dev/cu.usbmodem",
        "/dev/cu.wchusbserial",
        "/dev/cu.SLAB_USBtoUART",
        "/dev/cu.CH340",
        "/dev/cu.wch",
    ]

    /// Lists likely USB-serial devices (macOS `cu.*` preferred).
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
            .sorted()

        return paths.map { SerialPortInfo(path: $0) }
    }
}
