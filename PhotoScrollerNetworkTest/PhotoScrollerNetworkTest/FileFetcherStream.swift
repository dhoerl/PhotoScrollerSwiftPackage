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
final class FileFetcherStream: Stream {

    private let url: URL
    private let queue: DispatchQueue
    private let inputStream: InputStream

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
    }
    deinit {
        close()
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

}

