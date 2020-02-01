//
//  FileFetcherStream.swift
//  PhotoScrollerNetworkTest
//
//  Created by David Hoerl on 1/26/20.
//  Copyright © 2020 Self. All rights reserved.
//


import Foundation

// NOTE: cannot subclass InputStream as we'd loose all the built in
@objcMembers
final class FileFetcherStream: InputStream {

    let url: URL
    let queue: DispatchQueue
    let inputStream: InputStream

    init(url: URL, queue: DispatchQueue, delegate: StreamDelegate) {
        assert(url.isFileURL)
        assert(FileManager.default.fileExists(atPath: url.path))

        guard let inputStream = InputStream(url: url) else { fatalError() }
        self.inputStream = inputStream

        self.url = url
        self.queue = queue

        // Order important - see Stream Programming Guide (teardown in reverse order)
        inputStream.delegate = delegate // Strong!
        // https://stackoverflow.com/a/41050351/1633251
        // https://developer.apple.com/library/archive/samplecode/sc1236/Listings/TLSTool_TLSToolCommon_m.html
        CFReadStreamSetDispatchQueue(inputStream, queue)

        super.init(data: Data())
    }
    deinit {
        close()
#if UNIT_TESTING
        NotificationCenter.default.post(name: FetcherDeinit, object: nil, userInfo: [FetcherURL: url])
#endif
    }

    override var delegate: StreamDelegate? {
        get { return inputStream.delegate }
        set { }
    }

    override func open() {
        inputStream.open()
    }

    override func close() {
        inputStream.close()
        CFReadStreamSetDispatchQueue(inputStream, nil)
        inputStream.delegate = nil
    }

    override var streamStatus: Stream.Status {
        return inputStream.streamStatus
    }

    override var streamError: Error? {
        return inputStream.streamError
    }

    override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        return inputStream.read(buffer, maxLength: len)
    }

    override func getBuffer(_ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, length len: UnsafeMutablePointer<Int>) -> Bool {
        return inputStream.getBuffer(buffer, length: len)
    }

    override var hasBytesAvailable: Bool {
        return inputStream.hasBytesAvailable
    }

}
