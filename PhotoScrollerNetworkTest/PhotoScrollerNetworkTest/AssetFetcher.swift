//
//  AssetFetcher.swift
//  PhotoScrollerNetworkTest
//
//  Created by David Hoerl on 1/25/20.
//  Copyright © 2020 Self. All rights reserved.
//

import Foundation
import Combine


//https://www.avanderlee.com/swift/custom-combine-publisher/ TOO COMPLICATED
// https://ruiper.es/2019/08/05/custom-publishers-part1/ Two parts!

private func LOG(_ items: Any..., separator: String = " ", terminator: String = "\n") {
#if DEBUG
        print("ASSET: " + items.map{String(describing: $0)}.joined(separator: separator), terminator: terminator)
#endif
}

private let assetQueue = DispatchQueue(label: "com.AssetFetcher", qos: .userInitiated)

final class AssetFetcher: Publisher {

    typealias Output = Data
    typealias Failure = Error

    let url: URL

    init(url: URL) {
        self.url = url
    }

    func receive<S>(subscriber: S) where S: Subscriber, Failure == S.Failure, Output == S.Input {
        let subscription = AssetFetcherSubscription(url: url, downstream: subscriber)
        subscriber.receive(subscription: subscription)
    }

}

protocol StreamReceive: class {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event)
}

extension AssetFetcher {

    final class AssetFetcherSubscription<DownStream>: StreamReceive, Subscription where DownStream: Subscriber, DownStream.Input == Data, DownStream.Failure == Error {

        private let standardLen = 4_096

        private var downstream: DownStream? // optional so we can nil it on cancel
        private let url: URL
        //private var isFileURL: Bool { url.isFileURL }
        private lazy var streamReceiver: StreamReceiver = StreamReceiver(delegate: self)
        private lazy var _fileFetcher: FileFetcherStream = FileFetcherStream(url: url, queue: assetQueue, delegate: streamReceiver)
        private lazy var _webFetcher: WebFetcherStream = {
            WebFetcherStream.startMonitoring(onQueue: assetQueue)
            let fetcher = WebFetcherStream(url: url, delegate: streamReceiver)
            return fetcher
        }()
        private lazy var fetcher: InputStream = { url.isFileURL ? _fileFetcher : _webFetcher }()

        private var runningDemand: Subscribers.Demand = Subscribers.Demand.max(0)
        private var savedData = Data()

        init(url: URL, downstream: DownStream) {
            self.url = url
            self.downstream = downstream

            fetcher.open()
            LOG("INIT")
        }

        func request(_ demand: Subscribers.Demand) {
            LOG("REQUEST")
            guard let downstream = downstream else { return LOG("FUCKED") }
            runningDemand += demand
            let askLen = howMuchToRead(request: standardLen)
LOG("request, demand:", demand.max ?? "<infinite>", "runningDemand:", runningDemand.max ?? "<infinite>", "ASKLEN:", askLen)
            if askLen > 0 && savedData.count > 0 {
                let readLen = askLen > savedData.count ? savedData.count : askLen // min won't work
                let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: readLen)  // mutable Data won't let us get a pointer anymore...
                let range = 0..<readLen
                savedData.copyBytes(to: bytes, from: range)
                let data = Data(bytesNoCopy: bytes, count: readLen, deallocator: .custom({ (_, _) in bytes.deallocate() })) // (UnsafeMutableRawPointer, Int)

                savedData.removeSubrange(range)
                let fuck = downstream.receive(data)
if let val = fuck.max {
    LOG("FUCK VAL:", val)
} else { LOG("FUCK IS INFINITE!") }

if let val = runningDemand.max {
    LOG("runningDemand VAL:", val)
} else { LOG("runningDemand IS INFINITE!") }
            }
        }

        // downstream?.receive(completion: .finished)
        // downstream = nil

        func cancel() {
            downstream = nil
        }

        private func howMuchToRead(request: Int) -> Int {
            let askLen: Int
            if let demandMax = runningDemand.max {
                askLen = request < demandMax ? request : demandMax
            } else {
                askLen = request
            }
            return askLen
        }

        // MARK: StreamDelegate

        func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
            guard let stream = aStream as? InputStream else { fatalError() }
            dispatchPrecondition(condition: .onQueue(assetQueue))

            switch eventCode {
            case .openCompleted:
                LOG("OPEN COMPLETED")
            case .endEncountered:
                LOG("AT END :-)")
                fetcher.close()
            case .hasBytesAvailable:
                LOG("hasBytesAvailable")
                guard let downstream = downstream else { return }
                guard stream.hasBytesAvailable else { return }

                var askLen: Int
                do {
                    //var byte: UInt8 = 0
                    var ptr: UnsafeMutablePointer<UInt8>? = nil
                    var len: Int = 0

                    if stream.getBuffer(&ptr, length: &len) {
                        askLen = len
                    } else {
                        askLen = standardLen
                    }
                }
                askLen = howMuchToRead(request: askLen)

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
            case .errorOccurred:
                LOG("WTF!!! Error", stream.streamError!)
            default:
                LOG("UNEXPECTED \(eventCode)", String(describing: eventCode))
            }

        }
    }

    @objcMembers final class StreamReceiver: NSObject, StreamDelegate {

        private weak var delegate: StreamReceive?

        init(delegate: StreamReceive) {
            self.delegate = delegate
        }

        func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
            dispatchPrecondition(condition: .onQueue(assetQueue))
            self.delegate?.stream(aStream, handle: eventCode)
        }

    }

}

//struct UIControlPublisher<Control: UIControl>: Publisher {
//
//    typealias Output = Control
//    typealias Failure = Never
//
//    let control: Control
//    let controlEvents: UIControl.Event
//
//    init(control: Control, events: UIControl.Event) {
//        self.control = control
//        self.controlEvents = events
//    }
//
//    func receive<S>(subscriber: S) where S : Subscriber, S.Failure == UIControlPublisher.Failure, S.Input == UIControlPublisher.Output {
//        let subscription = UIControlSubscription(subscriber: subscriber, control: control, event: controlEvents)
//        subscriber.receive(subscription: subscription)
//    }
//}
