import Foundation

enum NetworkSessions {
    /// Short operations must finish the entire transfer within the shared deadline,
    /// even when the server keeps sending occasional bytes.
    static let standard: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = NetworkRequestTimeouts.standardResponse
        configuration.timeoutIntervalForResource = NetworkRequestTimeouts.standardResponse
        return URLSession(configuration: configuration)
    }()
}

/// Buffered response transport. Mutable state is confined to the session's serial queue.
final class NetworkDataRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let id: UUID
    private let task: URLSessionDataTask
    private let queue: DispatchQueue
    private let onLongWait: @Sendable () -> Void
    private var completion: (@Sendable (Data, URLResponse?, Error?) -> Void)?
    private var data = Data()
    private lazy var waitMonitor = NetworkRequestWaitMonitor(
        queue: queue,
        onConnectionTimeout: { [weak self] in
            guard let self else { return }
            self.task.cancel()
            self.finish(error: URLError(.timedOut))
        },
        onLongWait: { [weak self] _ in self?.onLongWait() }
    )

    init(
        id: UUID,
        request: URLRequest,
        session: URLSession,
        queue: DispatchQueue,
        onLongWait: @escaping @Sendable () -> Void,
        completion: @escaping @Sendable (Data, URLResponse?, Error?) -> Void
    ) {
        self.id = id
        self.task = session.dataTask(with: request)
        self.queue = queue
        self.onLongWait = onLongWait
        self.completion = completion
        super.init()
        task.delegate = self
    }

    func start() {
        queue.async { [self] in
            guard completion != nil else { return }
            waitMonitor.start()
            task.resume()
        }
    }

    func cancel() {
        queue.async { [self] in
            waitMonitor.stop()
            completion = nil
            data = Data()
            task.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        if totalBytesSent > 0 { waitMonitor.markConnectionEstablished() }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        waitMonitor.markConnectionEstablished()
        completionHandler(completion == nil ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard completion != nil else { return }
        waitMonitor.markConnectionEstablished()
        self.data.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error: error)
    }

    private func finish(error: Error?) {
        waitMonitor.stop()
        let callback = completion
        completion = nil
        callback?(data, task.response, error)
        data = Data()
    }
}
