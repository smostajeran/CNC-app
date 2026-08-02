import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum SerialPortError: Error, LocalizedError, Equatable {
    case openFailed(String)
    case configureFailed
    case notOpen
    case writeFailed
    case readFailed

    public var errorDescription: String? {
        switch self {
        case .openFailed(let path): return "Could not open serial port \(path)"
        case .configureFailed: return "Could not configure serial port"
        case .notOpen: return "Serial port is not open"
        case .writeFailed: return "Serial write failed"
        case .readFailed: return "Serial read failed"
        }
    }
}

/// Minimal POSIX serial port for macOS USB-serial adapters.
public final class SerialPort: @unchecked Sendable {
    private var fd: Int32 = -1
    public private(set) var path: String?
    public private(set) var baudRate: Int = 115_200

    public var isOpen: Bool { fd >= 0 }

    public init() {}

    deinit {
        close()
    }

    public func open(path: String, baudRate: Int = 115_200) throws {
        if isOpen { close() }

        let handle = path.withCString { GlibcOrDarwin.openPath($0, O_RDWR | O_NOCTTY | O_NONBLOCK) }
        guard handle >= 0 else { throw SerialPortError.openFailed(path) }

        var options = termios()
        guard tcgetattr(handle, &options) == 0 else {
            _ = GlibcOrDarwin.close(handle)
            throw SerialPortError.configureFailed
        }

        cfmakeraw(&options)
        options.c_cflag |= tcflag_t(CLOCAL | CREAD)
        options.c_cflag &= ~tcflag_t(PARENB)
        options.c_cflag &= ~tcflag_t(CSTOPB)
        options.c_cflag &= ~tcflag_t(CSIZE)
        options.c_cflag |= tcflag_t(CS8)
#if os(macOS)
        options.c_cflag &= ~tcflag_t(CRTSCTS)
#endif
        options.c_lflag = 0
        options.c_iflag = 0
        options.c_oflag = 0
        options.c_cc.16 = 0 // VMIN
        options.c_cc.17 = 0 // VTIME

        let speed = Self.baudConstant(baudRate)
        cfsetispeed(&options, speed)
        cfsetospeed(&options, speed)

        guard tcsetattr(handle, TCSANOW, &options) == 0 else {
            _ = GlibcOrDarwin.close(handle)
            throw SerialPortError.configureFailed
        }

        let flags = fcntl(handle, F_GETFL)
        _ = fcntl(handle, F_SETFL, flags | O_NONBLOCK)

        self.fd = handle
        self.path = path
        self.baudRate = baudRate
    }

    public func close() {
        guard fd >= 0 else { return }
        _ = GlibcOrDarwin.close(fd)
        fd = -1
        path = nil
    }

    public func write(_ data: Data) throws {
        guard fd >= 0 else { throw SerialPortError.notOpen }
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            var sent = 0
            let total = data.count
            while sent < total {
                let n = GlibcOrDarwin.write(fd, base.advanced(by: sent), total - sent)
                if n < 0 {
                    if errno == EINTR { continue }
                    if errno == EAGAIN {
                        Thread.sleep(forTimeInterval: 0.01)
                        continue
                    }
                    throw SerialPortError.writeFailed
                }
                sent += Int(n)
            }
        }
    }

    /// Read available bytes. If none, wait up to `timeout` seconds.
    public func read(maxLength: Int = 4096, timeout: TimeInterval = 0.05) throws -> Data {
        guard fd >= 0 else { throw SerialPortError.notOpen }

        if timeout > 0 {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ms = Int32(timeout * 1000)
            let pr = poll(&pfd, 1, ms)
            if pr < 0 {
                if errno == EINTR { return Data() }
                throw SerialPortError.readFailed
            }
            if pr == 0 { return Data() }
        }

        var buffer = [UInt8](repeating: 0, count: maxLength)
        let n = GlibcOrDarwin.read(fd, &buffer, maxLength)
        if n < 0 {
            if errno == EINTR || errno == EAGAIN { return Data() }
            throw SerialPortError.readFailed
        }
        if n == 0 { return Data() }
        return Data(buffer.prefix(Int(n)))
    }

    private static func baudConstant(_ baud: Int) -> speed_t {
        switch baud {
        case 9600: return speed_t(B9600)
        case 19200: return speed_t(B19200)
        case 38400: return speed_t(B38400)
        case 57600: return speed_t(B57600)
        case 115_200: return speed_t(B115200)
        case 230_400: return speed_t(B230400)
        default: return speed_t(B115200)
        }
    }
}

/// Thin shim so POSIX calls resolve on Darwin and Glibc.
private enum GlibcOrDarwin {
    static func openPath(_ path: UnsafePointer<CChar>, _ oflag: Int32) -> Int32 {
        #if canImport(Darwin)
        return Darwin.open(path, oflag)
        #else
        return Glibc.open(path, oflag)
        #endif
    }

    static func close(_ fd: Int32) -> Int32 {
        #if canImport(Darwin)
        return Darwin.close(fd)
        #else
        return Glibc.close(fd)
        #endif
    }

    static func write(_ fd: Int32, _ buf: UnsafeRawPointer!, _ nbyte: Int) -> Int {
        #if canImport(Darwin)
        return Darwin.write(fd, buf, nbyte)
        #else
        return Glibc.write(fd, buf, nbyte)
        #endif
    }

    static func read(_ fd: Int32, _ buf: UnsafeMutableRawPointer!, _ nbyte: Int) -> Int {
        #if canImport(Darwin)
        return Darwin.read(fd, buf, nbyte)
        #else
        return Glibc.read(fd, buf, nbyte)
        #endif
    }
}
