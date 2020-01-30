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

@objcMembers
final class WebFetcherStream: InputStream {

    static private var queue = DispatchQueue.main   // will crash if not set to something else

//    static fileprivate let queue = DispatchQueue(label: "com.WebFetcherStream", qos: .userInitiated)
//    static fileprivate var paths: [NWInterface: NWPath.Status] = [:]
    static private let monitor: NWPathMonitor = {
        let m = NWPathMonitor()
        m.pathUpdateHandler = { (path: NWPath) in
            isInternetUp = path.status == .satisfied
//            print("WEB PATH STATUS:", path.status)
//            path.availableInterfaces.forEach( { interfce in
//                paths[interfce] = path.status
//                DispatchQueue.main.async {
//                    print("WEB INTERFACE PATH:", path.debugDescription, "Interface:", interfce, "Status:", path.status)
//                }
//
//            } )
        }
        m.start(queue: queue)
        return m
    }()
    static var isInternetUp = false

    static fileprivate let sessionDelegate = SessionDelegate()
    static fileprivate let operationQueue: OperationQueue = {
        let opQueue = OperationQueue()
        opQueue.maxConcurrentOperationCount = 1   // Apple says to make this a serial queue
        opQueue.name = "com.WebFetcherStream"
        opQueue.qualityOfService = .userInitiated
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

    //private var task: URLSessionDataTask? = nil
    private let url: URL
    private weak var _delegate: StreamDelegate?     // must do this because InputStream subclasses don't have a 'delegate' property (try to use it, crash and burn!)
    private var isOpen = false

    private var data = Data()
    private var _streamStatus: Stream.Status = .notOpen
    private var _streamError: Error?
    private var _hasBytesAvailable = false  // TODO: could use an atomic property wrapper

    init(url: URL, delegate: StreamDelegate) {
        assert(!url.isFileURL)
        assert(Self.queue != DispatchQueue.main)

        //myDelegate = delegate // Strong!
        self.url = url
        _delegate = delegate

        super.init(data: Data())
    }
    deinit {
        if isOpen {
            close()
        }
    }

    static func startMonitoring(onQueue: DispatchQueue) {
        queue = onQueue
        let _ = monitor
    }
}

extension WebFetcherStream {

    static func startTask(_ dataTask: URLSessionDataTask) {
        guard let fetcher = Self.tasks[dataTask.taskIdentifier], let delegate = fetcher.delegate, let stream = delegate.stream  else { return print("START TASK FAILED") }

        fetcher._streamStatus = .open
        //delegate.stream?(fetcher, handle: .openCompleted)
        stream(fetcher, .openCompleted)
    }

    static func cancelTask(_ dataTask: URLSessionDataTask, statusCode: Int) {
        guard let fetcher = Self.tasks[dataTask.taskIdentifier], let delegate = fetcher.delegate, let stream = delegate.stream  else { return }


        // error is the connection failed
        fetcher._streamStatus = .notOpen
        fetcher._streamError = NSError(domain: domain, code: statusCode, userInfo:[ NSLocalizedDescriptionKey: "Failed to connect: statusCode \(statusCode)"])
        //delegate.stream?(fetcher, handle: .errorOccurred)
        stream(fetcher, .errorOccurred)
    }

    static func dataFromTask(_ dataTask: URLSessionDataTask, data nData: Data) {
        guard let fetcher = Self.tasks[dataTask.taskIdentifier], let delegate = fetcher.delegate, let stream = delegate.stream  else { return }

        nData.regions.forEach { (d) in
            fetcher.data.append(d)
        }

        //delegate.stream?(fetcher, handle: .hasBytesAvailable)
        let oldHasBytes = fetcher._hasBytesAvailable
        let newHasBytes = !fetcher.data.isEmpty
        fetcher._hasBytesAvailable = newHasBytes

        if oldHasBytes == false && newHasBytes == true {
            queue.async {
                //print("POST 2")
                stream(fetcher, .hasBytesAvailable)
            }
        }
    }

    static func completeFromTask(_ dataTask: URLSessionDataTask, error: Error?) {
        guard let fetcher = Self.tasks[dataTask.taskIdentifier], let delegate = fetcher.delegate, let stream = delegate.stream  else { return }

        fetcher._streamStatus = .atEnd
        //delegate.stream?(fetcher, handle: .endEncountered)
        stream(fetcher, .endEncountered)
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

        // TODO: check network state, if down send error


        //let dataTask = Self.urlSession.dataTask(with: self.url)
        let request = URLRequest(url: self.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10.0)
        let dataTask = Self.urlSession.dataTask(with: request)
        Self.tasks[dataTask.taskIdentifier] = self

        dataTask.resume()
        self._streamStatus = .opening

        /*
                 public enum Status : UInt {
                     case notOpen
                     case opening
                     case open
                     case reading
                     case writing
                     case atEnd
                     case closed
                     case error
                 }
        */
}
        //print("OPEN WEB:", dataTask.state.rawValue)
    }

    override func close() {
        _streamStatus = .closed
        delegate = nil
    }

    override var streamStatus: Stream.Status {
        return _streamStatus
    }

    override var streamError: Error? {
        return nil
    }

    // MARK: InputStream

    override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        let count = min(data.count, len)
        let range = 0..<count
        data.copyBytes(to: buffer, from: range)
        data.removeSubrange(range)

        _hasBytesAvailable = !data.isEmpty
        if _hasBytesAvailable, let delegate = delegate, let stream = delegate.stream {
            Self.queue.async {
                // we do this so we don't stack recurse - happens some time in the future
                print("POST 1")
                stream(self, .hasBytesAvailable)
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

}

// Helper task because the Class itself cannot be a delegate to a URL Session

@objcMembers
fileprivate class SessionDelegate: NSObject, URLSessionDataDelegate {

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


/*
func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
guard let stream = aStream as? InputStream else { fatalError() }
dispatchPrecondition(condition: .onQueue(assetQueue))

    switch eventCode {
    case .openCompleted:
        LOG("OPEN COMPLETED")
    case .endEncountered:
        LOG("AT END :-)")
        fileFetcher.close()
    case .hasBytesAvailable:
// File fetcher does not implement this
//                    do {
//                        //var byte: UInt8 = 0
//                        var ptr: UnsafeMutablePointer<UInt8>? = nil
//                        var len: Int = 0
//
//                        if stream.getBuffer(&ptr, length: &len) {
//                            LOG("HAHAHA GOT \(len)")
//                            if let ptr = ptr {
//                                LOG("and pointer:", String(describing: ptr))
//                            }
//                        }
//                    }
        guard let downstream = downstream else { return }

        let askLen = howMuchToRead()
LOG("GOT DATA ASKLEN:", askLen)
        if askLen > 0 {
            // We have outstanding requests
            let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: askLen)  // mutable Data won't let us get a pointer anymore...
            let readLen = stream.read(bytes, maxLength: askLen)
            let data = Data(bytesNoCopy: bytes, count: readLen, deallocator: .custom({ (_, _) in bytes.deallocate() })) // (UnsafeMutableRawPointer, Int)

            let fuck = downstream.receive(data)
if let val = fuck.max {
LOG("FUCK2 VAL:", val)
} else { LOG("FUCK2 IS INFINITE!") }

if let val = runningDemand.max {
LOG("runningDemand2 VAL:", val)
} else { LOG("runningDemand2 IS INFINITE!") }

            LOG("READ \(readLen) bytes!")
        } else {
            // No outstanding requests, so buffer the data
            let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: standardLen)  // mutable Data won't let us get a pointer anymore...
            let readLen = stream.read(bytes, maxLength: standardLen)
            savedData.append(bytes, count: readLen)
            LOG("CACHE \(readLen) bytes!")
        }
/*
        let readLen = stream.read(bytes, maxLength: 100_000)
        LOG("READLEN:", readLen)
        if self.outputStream.hasSpaceAvailable {
            LOG("READ: writeLen=\(writeLen)")
        } else {
            LOG("READ: no space!!!")
        }
*/
    case .errorOccurred:
/*
         NSError *theError = [stream streamError];
         NSAlert *theAlert = [[NSAlert alloc] init];
         [theAlert setMessageText:@"Error reading stream!"];
         [theAlert setInformativeText:[NSString stringWithFormat:@"Error %i: %@",
             [theError code], [theError localizedDescription]]];
         [theAlert addButtonWithTitle:@"OK"];
         [theAlert beginSheetModalForWindow:[NSApp mainWindow]
             modalDelegate:self
             didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:)
             contextInfo:nil];
         [stream close];
         [stream release];
         break;
         */
        LOG("WTF!!! Error")
    default:
        LOG("UNEXPECTED \(eventCode)", String(describing: eventCode))
    }

}
*/
