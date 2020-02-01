//
//  WebFetcherStream.swift
//  PhotoScrollerNetworkTest
//
//  Created by David Hoerl on 1/27/20.
//  Copyright © 2020 Self. All rights reserved.
//

import Foundation
import Network

private let domain = "com.WebFetcherStream"

/*
 public enum Status : UInt { case notOpen opening open reading writing atEnd closed error
*/

// Good blog on subclassing NSInputStream: http://khanlou.com/2018/11/streaming-multipart-requests/
// Code: https://gist.github.com/khanlou/b5e07f963bedcb6e0fcc5387b46991c3

@objcMembers
final class WebFetcherStream: InputStream {

    // Customization Points
    static var maxOperations = 4
    static var dataTaskTimeout: TimeInterval = 60.0
    static var qualityOfService: QualityOfService = .userInitiated

    // Must be called prior to instantiating any objects
    static func startMonitoring(onQueue: DispatchQueue) {
        queue = onQueue
        let _ = monitor
    }

    static private var queue = DispatchQueue.main   // will crash if not set to something else

    static private let monitor: NWPathMonitor = {
        let m = NWPathMonitor()
        m.pathUpdateHandler = { isInternetUp = $0.status == .satisfied }
        m.start(queue: queue)
        return m
    }()
    static private var isInternetUp = false

    static fileprivate let sessionDelegate = SessionDelegate()
    static fileprivate let operationQueue: OperationQueue = {
        let opQueue = OperationQueue()
        opQueue.maxConcurrentOperationCount = maxOperations
        opQueue.name = "com.WebFetcherStream"
        opQueue.qualityOfService = qualityOfService
        opQueue.underlyingQueue = queue
        return opQueue
    }()
    static fileprivate var tasks: [Int: WebFetcherStream] = [:] // Key is the taskIdentifier

    static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.httpShouldUsePipelining = true
        return URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: operationQueue)
    }()

    private let url: URL
    private weak var _delegate: StreamDelegate?     // must do this because InputStream subclasses don't have a 'delegate' property (try to use it, crash and burn!)

    private var dataTask: URLSessionDataTask?
    private var data = Data()

    @AtomicWrapper private var _streamStatus: Stream.Status = .notOpen
    @AtomicWrapper private var _streamError: Error?
    @AtomicWrapper private var _hasBytesAvailable = false

    init(url: URL, delegate: StreamDelegate) {
        assert(!url.isFileURL)
        assert(Self.queue != DispatchQueue.main)

        self.url = url
        _delegate = delegate

        super.init(data: Data())
    }
    deinit {
        close()
#if UNIT_TESTING
        NotificationCenter.default.post(name: FetcherDeinit, object: nil, userInfo: [FetcherURL: url])
#endif
    }

}

extension WebFetcherStream {

    static func startTask(_ dataTask: URLSessionDataTask) {
        guard let fetcher = Self.tasks[dataTask.taskIdentifier], let delegate = fetcher.delegate, let stream = delegate.stream  else { return }

        fetcher._streamStatus = .open
        stream(fetcher, .openCompleted)
    }

    static func cancelTask(_ dataTask: URLSessionDataTask, statusCode: Int) {
        guard let fetcher = Self.tasks[dataTask.taskIdentifier], let delegate = fetcher.delegate, let stream = delegate.stream  else { return }

        fetcher._streamStatus = .error
        fetcher._streamError = NSError(domain: domain, code: statusCode, userInfo:[ NSLocalizedDescriptionKey: "Failed to connect: statusCode \(statusCode)"])
        stream(fetcher, .errorOccurred)
    }

    static func dataFromTask(_ dataTask: URLSessionDataTask, data nData: Data) {
        guard let fetcher = Self.tasks[dataTask.taskIdentifier], let delegate = fetcher.delegate, let stream = delegate.stream  else { return }

        nData.regions.forEach { fetcher.data.append($0) }

        let oldHasBytes = fetcher._hasBytesAvailable
        let newHasBytes = !fetcher.data.isEmpty
        fetcher._hasBytesAvailable = newHasBytes

        if oldHasBytes == false && newHasBytes == true {
            queue.async {
                stream(fetcher, .hasBytesAvailable)
            }
        }
    }

    static func completeFromTask(_ dataTask: URLSessionDataTask, error: Error?) {
        guard let fetcher = Self.tasks[dataTask.taskIdentifier], let delegate = fetcher.delegate, let stream = delegate.stream  else { return }

        if let error = error {
            fetcher._streamStatus = .error
            fetcher._streamError = error
            stream(fetcher, .errorOccurred)
        } else {
            fetcher._streamStatus = .atEnd
            if fetcher.data.isEmpty {
                stream(fetcher, .endEncountered)
            }
        }
    }
}

extension WebFetcherStream {

    // MARK: Stream

    override var delegate: StreamDelegate? {
        get { return _delegate }
        set { _delegate = newValue }
    }

    override func open() {
        guard _streamStatus == .notOpen else { fatalError() }

        Self.queue.async {
            guard Self.isInternetUp else {
                self._streamStatus = .error
                self._streamError = NSError(domain: domain, code: 1, userInfo:[ NSLocalizedDescriptionKey: "Internet is down"])
                self._delegate?.stream?(self, handle: .errorOccurred)
                return
            }

            let request = URLRequest(url: self.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.dataTaskTimeout)
            let dataTask = Self.urlSession.dataTask(with: request)
            Self.tasks[dataTask.taskIdentifier] = self
            self.dataTask = dataTask

            dataTask.resume()
            self._streamStatus = .opening
        }
    }

    override func close() {
        guard _streamStatus != .closed else { return }
        _streamStatus = .closed
        delegate = nil

        if let dataTask = dataTask, dataTask.state == .running {
            dataTask.cancel()
            Self.queue.async {
                Self.tasks[dataTask.taskIdentifier] = nil
                self.dataTask = nil
            }
        }
    }

    override var streamStatus: Stream.Status {
        return _streamStatus
    }

    override var streamError: Error? {
        return _streamError
    }

    // MARK: InputStream

    override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        dispatchPrecondition(condition: .onQueue(Self.queue))
        guard _streamStatus == .open || _streamStatus == .atEnd else { return 0 }

        _streamStatus = .reading
        let count = min(data.count, len)
        if count > 0 {
            let range = 0..<count
            data.copyBytes(to: buffer, from: range)
            data.removeSubrange(range)
            _streamStatus = .open
        }

        _hasBytesAvailable = !data.isEmpty
        if let delegate = delegate, let stream = delegate.stream {
            Self.queue.async {
                self._hasBytesAvailable = !self.data.isEmpty
                if self._hasBytesAvailable {
                    // we do this so we don't stack recurse - happens some time in the future
                    stream(self, .hasBytesAvailable)
                } else
                if self._streamStatus == .atEnd {
                    stream(self, .endEncountered)
                }
            }
        }

        return count
    }

    override func getBuffer(_ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, length len: UnsafeMutablePointer<Int>) -> Bool {
        len[0] = data.count

        data.withUnsafeMutableBytes({ (bufPtr: UnsafeMutableRawBufferPointer) -> Void in
            if let addr = bufPtr.baseAddress {
                let ptr: UnsafeMutablePointer<UInt8> = addr.assumingMemoryBound(to: UInt8.self)
                buffer[0] = ptr
            }
        })
        return true
    }

    override var hasBytesAvailable: Bool {
        return _hasBytesAvailable
    }

    // From Soroush Khanlou, for completeness
    override func property(forKey key: Stream.PropertyKey) -> Any? { return nil }
    override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool { return false }
    override func schedule(in aRunLoop: RunLoop, forMode mode: RunLoop.Mode) { }
    override func remove(from aRunLoop: RunLoop, forMode mode: RunLoop.Mode) { }

}

// Helper task because the Class itself cannot be a delegate to a URL Session

@objcMembers
private class SessionDelegate: NSObject, URLSessionDataDelegate {

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else { fatalError() }

        if response.statusCode == 200 {
            completionHandler(.allow)
            WebFetcherStream.startTask(dataTask)
        } else {
            completionHandler(.cancel)
            WebFetcherStream.cancelTask(dataTask, statusCode: response.statusCode)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        //(NSData *)dispatch_data_create_concat((dispatch_data_t)fetcher.webData, (dispatch_data_t)data);
        WebFetcherStream.dataFromTask(dataTask, data: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let dataTask = task as? URLSessionDataTask else { fatalError() }
        WebFetcherStream.completeFromTask(dataTask, error: error)
    }

}

@propertyWrapper
private struct AtomicWrapper<T> {
    private var semaphore = DispatchSemaphore(value: 1)
    private var _wrappedValue: T

    var wrappedValue: T  {
        get {
            semaphore.wait()
            let tmp = _wrappedValue
            semaphore.signal()
            return tmp
        }
        set {
            semaphore.wait()
            _wrappedValue = newValue
            semaphore.signal()
        }
    }

    init(wrappedValue value: T) {
        _wrappedValue = value
    }

    public var projectedValue: Self {
      get { self }
      set { self = newValue }
    }

    @discardableResult mutating func perform(block: (() -> T)) -> T {
        semaphore.wait()
        let tmp = block()
        _wrappedValue = tmp
        semaphore.signal()
        return tmp
    }

    mutating func mutate(mutation: (inout T) -> Void)  {
        semaphore.wait()
        mutation(&_wrappedValue)
        semaphore.signal()
    }
}
