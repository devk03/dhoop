import Foundation

/// A single ephemeral request with chunked, bounded accumulation and no redirected credentials.
/// The lock covers cancellation racing the serial URLSession delegate queue and request startup.
final class BoundedHTTPDataRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private typealias Reply = (Data, HTTPURLResponse)
    private let lock = NSLock()
    private let validate: (HTTPURLResponse) throws -> Int
    private let overflow: (HTTPURLResponse) -> Error
    private let invalidResponse: Error
    private var continuation: CheckedContinuation<Reply, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var response: HTTPURLResponse?
    private var limit = 0
    private var bytes = Data()
    private var finished = false

    init(invalidResponse: Error, validate: @escaping (HTTPURLResponse) throws -> Int,
         overflow: @escaping (HTTPURLResponse) -> Error) {
        self.invalidResponse = invalidResponse; self.validate = validate; self.overflow = overflow
    }

    func read(_ request: URLRequest, configuration: URLSessionConfiguration) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                let task = session.dataTask(with: request)
                lock.lock()
                guard !finished else {
                    lock.unlock(); session.invalidateAndCancel()
                    continuation.resume(throwing: CancellationError()); return
                }
                self.continuation = continuation; self.session = session; self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            self.finish(.failure(CancellationError()))
        }
    }

    private func finish(_ result: Result<Reply, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let completion = continuation, session = session
        continuation = nil; self.session = nil; task = nil; bytes = Data()
        lock.unlock()
        session?.invalidateAndCancel()
        completion?.resume(with: result)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        do {
            guard let response = response as? HTTPURLResponse else { throw invalidResponse }
            let limit = try validate(response)
            guard limit >= 0, response.expectedContentLength <= limit else { throw overflow(response) }
            lock.lock()
            let active = !finished
            if active { self.response = response; self.limit = limit }
            lock.unlock()
            completionHandler(active ? .allow : .cancel)
        } catch {
            completionHandler(.cancel); finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished, let response else { lock.unlock(); return }
        guard data.count <= limit - bytes.count else {
            lock.unlock(); finish(.failure(overflow(response))); return
        }
        bytes.append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)); return }
        lock.lock()
        let result: Result<Reply, Error> = response.map { .success((bytes, $0)) } ?? .failure(invalidResponse)
        lock.unlock()
        finish(result)
    }
}
