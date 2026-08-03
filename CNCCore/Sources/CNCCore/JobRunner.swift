import Foundation

/// Drives a `GCodeStreamer` through a `CommandCoordinator` (exclusive serial ownership).
public final class JobRunner: @unchecked Sendable {
    public let streamer = GCodeStreamer()
    private weak var coordinator: CommandCoordinator?
    private weak var client: GRBLClient?
    private var pumpTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "cnc.job.runner")
    private var lastProgressEmit = Date.distantPast
    private var statusPollCount = 0

    public var onProgress: ((Double, StreamerState) -> Void)?
    public var onState: ((StreamerState) -> Void)?
    public var onPenChange: (() -> Void)?

    public init() {}

    public func attach(coordinator: CommandCoordinator, client: GRBLClient) {
        self.coordinator = coordinator
        self.client = client
        client.onLine = { [weak self] line in
            self?.queue.async {
                self?.handleIncoming(line)
            }
        }
        // Note: AppModel also observes status; Idle completion is polled via requestStatus.
    }

    /// Test helper without coordinator.
    public func attach(client: GRBLClient) {
        self.client = client
        client.onLine = { [weak self] line in
            self?.queue.async {
                self?.handleIncoming(line)
            }
        }
    }

    public func loadGCode(_ text: String) {
        streamer.load(text: text)
        emit(force: true)
    }

    public func start() throws {
        if let coordinator {
            try coordinator.beginStreaming()
        }
        streamer.start()
        emit(force: true)
        startPump()
        pump()
    }

    public func pause() {
        streamer.pause()
        try? feedHold()
        emit(force: true)
    }

    public func resume() {
        do {
            if streamer.state == .waitingForPenChange, let coordinator {
                try coordinator.resumeStreamingAfterPenChange()
            }
            streamer.resume()
            if streamer.state != .waitingForPenChange {
                try cycleStart()
            }
            emit(force: true)
            pump()
        } catch {
            streamer.handleResponse("error:resume_blocked")
            emit(force: true)
        }
    }

    public func cancel() {
        streamer.cancel()
        try? halt()
        coordinator?.endStreaming()
        stopPump()
        emit(force: true)
    }

    /// Call when a status report shows Idle (finalizes ack-complete jobs).
    public func noteStatus(_ status: GRBLStatus) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.streamer.awaitingIdleForCompletion,
               status.state.lowercased().contains("idle") {
                self.streamer.noteMachineIdle()
                if self.streamer.state == .completed {
                    self.coordinator?.endStreaming()
                    self.stopPump()
                }
                self.emit(force: true)
            }
        }
    }

    private func handleIncoming(_ line: String) {
        let previous = streamer.state
        streamer.handleResponse(line)
        if streamer.state == .waitingForPenChange, previous != .waitingForPenChange {
            try? coordinator?.enterPenChangeWait()
            onPenChange?()
        }
        emit(force: true)
        pump()
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
        statusPollCount += 1
        if streamer.awaitingIdleForCompletion, statusPollCount % 10 == 0 {
            try? requestStatus()
        }

        while let line = streamer.nextLineToSend() {
            do {
                if let coordinator {
                    try coordinator.sendJobLine(line)
                } else if let client {
                    try client.sendLine(line)
                } else {
                    return
                }
            } catch {
                streamer.handleResponse("error:send_failed")
                coordinator?.endStreaming()
                stopPump()
                emit(force: true)
                return
            }
        }

        switch streamer.state {
        case .completed, .cancelled, .fault:
            coordinator?.endStreaming()
            stopPump()
        default:
            break
        }
        emit(force: false)
    }

    private func emit(force: Bool) {
        let now = Date()
        if !force && now.timeIntervalSince(lastProgressEmit) < 0.08 {
            return
        }
        lastProgressEmit = now
        var progress = streamer.progress
        if streamer.awaitingIdleForCompletion {
            progress = min(progress, 0.99)
        }
        onProgress?(progress, streamer.state)
        onState?(streamer.state)
    }

    private func feedHold() throws {
        if let coordinator { try coordinator.feedHold() }
        else if let client { try client.feedHold() }
    }

    private func cycleStart() throws {
        if let coordinator { try coordinator.cycleStart() }
        else if let client { try client.cycleStart() }
    }

    private func halt() throws {
        if let coordinator { try coordinator.halt() }
        else if let client { try client.halt() }
    }

    private func requestStatus() throws {
        if let coordinator { try coordinator.requestStatus() }
        else if let client { try client.requestStatus() }
    }
}
