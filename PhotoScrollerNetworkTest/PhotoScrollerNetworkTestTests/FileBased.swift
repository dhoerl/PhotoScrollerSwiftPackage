//
//  FileBased.swift
//  PhotoScrollerNetworkTestTests
//
//  Created by David Hoerl on 1/31/20.
//  Copyright © 2020 Self. All rights reserved.
//

import UIKit
import XCTest
import Combine

let FetcherDeinit = Notification.Name("FetcherDeinit")
let FetcherURL = "FetcherURL"
let AssetURL = "AssetURL"

final class ByURL {
    var fetcher: FileFetcherStream!

    var data = Data()
    var events = 0
    var image: UIImage?
    var dealloced = false
    var error: Error?

    init(fetcher: FileFetcherStream) {
        self.fetcher = fetcher
    }

}

final class FileBased: XCTestCase, StreamDelegate {

    private var assetQueue = DispatchQueue(label: "com.AssetFetcher", qos: .userInitiated)
    private var expectation = XCTestExpectation(description: "")

    private var fetchers: [URL: ByURL] = [:]
    private var subscribers: [URL: AnyCancellable] = [:]
//    private var urls: Set<URL> = []
//    private var data: [URL: Data] = [:]
//    private var events: [URL: Int] = [:]

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        expectation = XCTestExpectation(description: "FileFetchers deinit")
        expectation.assertForOverFulfill = true

        fetchers.removeAll()
//        // In UI tests it is usually best to stop immediately when a failure occurs.
//        continueAfterFailure = false
//
//        // UI tests must launch the application that they test. Doing this in setup will make sure it happens for each test method.
//        XCUIApplication().launch()

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.

        NotificationCenter.default.addObserver(self, selector: #selector(notification(_:)), name: FetcherDeinit, object: nil)
    }

    @objc
    func notification(_ note: Notification) {
        if let url = note.userInfo?[FetcherURL] as? URL {
            DispatchQueue.main.async {
                guard let byURL = self.fetchers[url] else { return }    // Combine uses a fetcher, its not in this array
                byURL.dealloced = true
                self.expectation.fulfill()
//                print("FETCHER DEALLOC:", url)
            }
        } else
        if let _ = note.userInfo?[AssetURL] as? URL {
            DispatchQueue.main.async {
                self.expectation.fulfill()
//                print("ASSET DEALLOC:", url)
            }
        }

    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        NotificationCenter.default.removeObserver(self, name: FetcherDeinit, object: nil)

        fetchers.removeAll()
        expectation = XCTestExpectation(description: "")
    }

    func xtestSingleFile() {
        let files = ["Coffee"]
        runTest(files: files)
    }

    func xtestTwoFiles() {
        let files = ["Coffee", "Lake"]
        runTest(files: files)
    }

    func xtestNineFiles() {
        let files = ["Coffee", "err_image", "Lake", "large_leaves_70mp", "Shed", "Space4", "Space5", "Space6", "Tree"]
        runTest(files: files)
    }

    private func runTest(files: [String]) {
        var expectedFulfillmentCount = 0
        for file in files {
            let path = Bundle.main.path(forResource: file, ofType: "jpg")!
            let url = URL(fileURLWithPath: path)
            let fetcher = FileFetcherStream(url: url, queue: assetQueue, delegate: self)
            fetchers[url] = ByURL(fetcher: fetcher)

            expectedFulfillmentCount += 2   // one for the final stream message, one for the dealloc
            expectation.expectedFulfillmentCount = expectedFulfillmentCount
            fetcher.open()
        }

        wait(for: [expectation], timeout: TimeInterval(files.count * 1))

        for byURL in fetchers.values {
            XCTAssert( !byURL.data.isEmpty )
            XCTAssert(byURL.image != nil)
        }
    }

    func testSingleCombine() {
        let files = ["Coffee"]
        runTestCombine(files: files)
    }

    func testTwoCombine() {
        let files = ["Coffee", "Lake"]
        runTestCombine(files: files)
    }

    func testNineCombine() {
        let files = ["Coffee", "err_image", "Lake", "large_leaves_70mp", "Shed", "Space4", "Space5", "Space6", "Tree"]
        runTestCombine(files: files)
    }

    private func runTestCombine(files: [String]) {
        var expectedFulfillmentCount = 0

        for file in files {
            let path = Bundle.main.path(forResource: file, ofType: "jpg")!
            let url = URL(fileURLWithPath: path)

            var data = Data()
            let mySubscriber = AssetFetcher(url: url)
                                .sink(receiveCompletion: { (completion) in
                                    switch completion {
                                    case .finished:
                                        XCTAssert(!data.isEmpty)
                                        XCTAssertNotNil(UIImage(data: data))
                                        //print("SUCCESS:", data.count, UIImage(data: data) ?? "WTF")
                                    case .failure(let error):
                                        print("ERROR:", error)
                                    }
                                    DispatchQueue.main.async {
                                        self.expectation.fulfill()
                                    }
                                },
                                receiveValue: { (d) in
                                    data.append(d)
//                                    DispatchQueue.main.async {
//                                        //print("SINK: got data:", data.count)
//                                        if !data.isEmpty && image != nil {
//                                            self.expectation.fulfill()
//                                        }
//                                    }
                                })
            subscribers[url] = mySubscriber

            expectedFulfillmentCount += 3   // two classes and the final Subcriber block
            expectation.expectedFulfillmentCount = expectedFulfillmentCount
        }

        wait(for: [expectation], timeout: TimeInterval(files.count * 10))
    }


    @objc
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        dispatchPrecondition(condition: .onQueue(assetQueue))
        guard let stream = aStream as? InputStream else { fatalError() }
        guard let byURL = fetchers.values.first(where: { $0.fetcher != nil && $0.fetcher.inputStream === stream }) else { fatalError() }
        //let fetcher = byURL.fetcher

        byURL.events += 1

        var sendFullfill = false
        switch eventCode {
        case .openCompleted:
            XCTAssertEqual(byURL.events, 1)
        case .endEncountered:
            byURL.image = UIImage(data: byURL.data)
            sendFullfill = true
        case .hasBytesAvailable:
            guard stream.hasBytesAvailable else { return }

            let askLen: Int
            do {
                //var byte: UInt8 = 0
                var ptr: UnsafeMutablePointer<UInt8>? = nil
                var len: Int = 0

                if stream.getBuffer(&ptr, length: &len) {
                    askLen = len
                } else {
                    askLen = 4_096
                }
            }
            let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: askLen)
            let readLen = stream.read(bytes, maxLength: askLen)
            if readLen > 0 {
                byURL.data.append(bytes, count: readLen)
            } else {
                print("WTF!")
            }

//            if readLen < askLen {
//                print("READ 1 \(readLen) bytes!")
//            } else {
//                print("READ 2 \(readLen) bytes!")
//            }

        case .errorOccurred:
            aStream.close()
            if let error = aStream.streamError {
                byURL.error = error
                print("WTF!!! Error:", error)
            } else {
                print("ERROR BUT NO STREAM ERROR!!!")
            }
            sendFullfill = true
        default:
            print("UNEXPECTED \(eventCode)", String(describing: eventCode))
            XCTAssert(false)
        }
        if sendFullfill {
            DispatchQueue.main.async {
                byURL.fetcher = nil
                print(eventCode == .endEncountered ? "AT END :-)" : "ERROR")
                self.expectation.fulfill()
            }
        }
    }

}
