import Foundation

/// All methods and callbacks run on the request's serial delegate queue.
final class NetworkRequestWaitMonitor: @unchecked Sendable {
    private let queue: DispatchQueue
    private let onConnectionTimeout: @Sendable () -> Void
    private let onLongWait: @Sendable (_ hasResponseProgress: Bool) -> Void
    private var timer: DispatchSourceTimer?
    private var deadline = DispatchTime.now()
    private var isConnected = false
    private var hasResponseProgress = false
    private var isActive = false

    init(
        queue: DispatchQueue,
        onConnectionTimeout: @escaping @Sendable () -> Void,
        onLongWait: @escaping @Sendable (Bool) -> Void
    ) {
        self.queue = queue
        self.onConnectionTimeout = onConnectionTimeout
        self.onLongWait = onLongWait
    }

    func start() {
        stop()
        isActive = true
        isConnected = false
        hasResponseProgress = false
        schedule(after: NetworkRequestTimeouts.connection)
    }

    func markConnectionEstablished() {
        guard isActive, !isConnected else { return }
        isConnected = true
        schedule(after: NetworkRequestTimeouts.longResponseNotice)
    }

    func markResponseProgress() {
        guard isActive else { return }
        isConnected = true
        hasResponseProgress = true
        schedule(after: NetworkRequestTimeouts.longResponseNotice)
    }

    func stop() {
        isActive = false
        timer?.cancel()
        timer = nil
    }

    private func schedule(after delay: TimeInterval) {
        deadline = .now() + delay
        if let timer {
            timer.schedule(deadline: deadline)
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: deadline)
        timer.setEventHandler { [weak self] in
            guard let self, self.isActive else { return }
            guard DispatchTime.now() >= self.deadline else { return }
            if self.isConnected {
                self.onLongWait(self.hasResponseProgress)
            } else {
                self.stop()
                self.onConnectionTimeout()
            }
        }
        self.timer = timer
        timer.resume()
    }

    deinit {
        timer?.cancel()
    }
}
