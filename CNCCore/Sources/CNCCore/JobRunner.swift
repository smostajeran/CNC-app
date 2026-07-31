import Foundation

/// Drives a `GCodeStreamer` against a `GRBLClient`.
public final class JobRunner: @unchecked Sendable {
    public let streamer = GCodeStreamer()
    private weak var client: GRBLClient?
    private var pumpTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "cnc.job.runner")

    public var onProgress: ((Double, StreamerState) -> Void)?
    public var onState: ((StreamerState) -> Void)?

    public init() {}

    public func attach(client: GRBLClient) {
        self.client = client
        client.onLine = { [weak self] line in
            self?.queue.async {
                self?.streamer.handleResponse(line)
                self?.emit()
                self?.pump()
            }
        }
    }

    public func loadGCode(_ text: String) {
        streamer.load(text: text)
        emit()
    }

    public func start() {
        streamer.start()
        emit()
        startPump()
        pump()
    }

    public func pause() {
        streamer.pause()
        try? client?.feedHold()
        emit()
    }

    public func resume() {
        streamer.resume()
        try? client?.cycleStart()
        emit()
        pump()
    }

    public func cancel() {
        streamer.cancel()
        try? client?.halt()
        stopPump()
        emit()
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
        while let line = streamer.nextLineToSend() {
            do {
                try client.sendLine(line)
            } catch {
                streamer.handleResponse("error:send_failed")
                stopPump()
                emit()
                return
            }
            // Wait for ok before next (streamer enforces awaitingOk)
            break
        }
        if streamer.state == .completed || streamer.state == .cancelled {
            stopPump()
        }
        if case .fault = streamer.state {
            stopPump()
        }
        emit()
    }

    private func emit() {
        onProgress?(streamer.progress, streamer.state)
        onState?(streamer.state)
    }
}
