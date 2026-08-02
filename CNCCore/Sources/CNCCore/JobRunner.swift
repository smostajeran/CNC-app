import Foundation

/// Drives a `GCodeStreamer` against a `GRBLClient` using the character window.
public final class JobRunner: @unchecked Sendable {
    public let streamer = GCodeStreamer()
    private weak var client: GRBLClient?
    private var pumpTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "cnc.job.runner")
    private var lastProgressEmit = Date.distantPast

    public var onProgress: ((Double, StreamerState) -> Void)?
    public var onState: ((StreamerState) -> Void)?

    public init() {}

    public func attach(client: GRBLClient) {
        self.client = client
        client.onLine = { [weak self] line in
            self?.queue.async {
                self?.streamer.handleResponse(line)
                self?.emit(force: true)
                self?.pump()
            }
        }
    }

    public func loadGCode(_ text: String) {
        streamer.load(text: text)
        emit(force: true)
    }

    public func start() {
        streamer.start()
        emit(force: true)
        startPump()
        pump()
    }

    public func pause() {
        streamer.pause()
        try? client?.feedHold()
        emit(force: true)
    }

    public func resume() {
        streamer.resume()
        try? client?.cycleStart()
        emit(force: true)
        pump()
    }

    public func cancel() {
        streamer.cancel()
        try? client?.halt()
        stopPump()
        emit(force: true)
    }

    private func startPump() {
        stopPump()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 0.02)
        timer.setEventHandler { [weak self] in
            self?.pump()
        }
        timer.resume()
        pumpTimer = timer
    }

    private func stopPump() {
        pumpTimer?.cancel()
        pumpTimer = nil
    }

    private func pump() {
        guard let client else { return }
        // Fill GRBL RX window with as many lines as fit.
        while let line = streamer.nextLineToSend() {
            do {
                try client.sendLine(line)
            } catch {
                streamer.handleResponse("error:send_failed")
                stopPump()
                emit(force: true)
                return
            }
        }
        if streamer.state == .completed || streamer.state == .cancelled {
            stopPump()
        }
        if case .fault = streamer.state {
            stopPump()
        }
        emit(force: false)
    }

    private func emit(force: Bool) {
        let now = Date()
        if !force && now.timeIntervalSince(lastProgressEmit) < 0.08 {
            return
        }
        lastProgressEmit = now
        onProgress?(streamer.progress, streamer.state)
        onState?(streamer.state)
    }
}
