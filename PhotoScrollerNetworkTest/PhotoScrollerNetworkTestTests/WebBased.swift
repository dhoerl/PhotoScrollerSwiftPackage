//
//  WebBased.swift
//  PhotoScrollerNetworkTestTests
//
//  Created by David Hoerl on 2/2/20.
//  Copyright © 2020 Self. All rights reserved.
//

import UIKit
import XCTest
import Combine

private let LOOP_COUNT = 0
/* See FileBased:
let FetcherDeinit = Notification.Name("FetcherDeinit")
let FetcherURL = "FetcherURL"
let AssetURL = "AssetURL"

*/

private let allUrls = [
    "https://www.dropbox.com/s/b337y2sn1597sry/Lake.jpg?dl=1",
    "https://www.dropbox.com/s/wq5ed0z4cwgu8xc/Shed.jpg?dl=1",
    "https://www.dropbox.com/s/r1vf3irfero2f04/Tree.jpg?dl=1",
    "https://www.dropbox.com/s/xv4ftt95ud937w4/large_leaves_70mp.jpg?dl=1",
    "https://www.dropbox.com/s/sbda3z1r0komm7g/Space4.jpg?dl=1",
    "https://www.dropbox.com/s/w0s5905cqkcy4ua/Space5.jpg?dl=1",
    "https://www.dropbox.com/s/yx63i2yf8eobrgt/Space6.jpg?dl=1",
]

private func LOG(_ items: Any..., separator: String = " ", terminator: String = "\n") {
#if DEBUG
    // print("ASSET: " + items.map{String(describing: $0)}.joined(separator: separator), terminator: terminator)
#endif
}

final class WebBased: XCTestCase, StreamDelegate {

    private var assetQueue = TestAssetQueue
    private var expectation = XCTestExpectation(description: "")

    private var fetchers: [URL: ByURL] = [:]
    private var subscribers: [URL: AnyCancellable] = [:]
//    private var urls: Set<URL> = []
//    private var data: [URL: Data] = [:]
//    private var events: [URL: Int] = [:]

//    override func invokeTest() {
//        for time in 0...10 {
//            print("WebBased invoking: \(time) times")
//            super.invokeTest()
//        }
//    }


    override func setUp() {
        continueAfterFailure = false

        // Put setup code here. This method is called before the invocation of each test method in the class.
        expectation = XCTestExpectation(description: "WebFetchers deinit")
        expectation.assertForOverFulfill = true

        self.assetQueue.sync {
            fetchers.removeAll()
        }

//        // In UI tests it is usually best to stop immediately when a failure occurs.
//        continueAfterFailure = false
//
//        // UI tests must launch the application that they test. Doing this in setup will make sure it happens for each test method.
//        XCUIApplication().launch()

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.

        NotificationCenter.default.addObserver(self, selector: #selector(notification(_:)), name: FetcherDeinit, object: nil)

        AssetFetcher.startMonitoring(onQueue: assetQueue)   // calls WebFetcherStream.startMonitoring
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        NotificationCenter.default.removeObserver(self, name: FetcherDeinit, object: nil)

        self.assetQueue.sync {
            fetchers.removeAll()
        }
        expectation = XCTestExpectation(description: "")
    }

    @objc
    func notification(_ note: Notification) {
        if let url = note.userInfo?[FetcherURL] as? URL {
            self.assetQueue.async {
                guard let byURL = self.fetchers[url] else { return }    // Combine uses a fetcher, its not in this array
                byURL.dealloced = true
                DispatchQueue.main.async {
                    LOG("EXPECT1:", byURL.name)
                    self.expectation.fulfill()
                }
            }
        } else
        if let url = note.userInfo?[AssetURL] as? URL {
            DispatchQueue.main.async {
                LOG("EXPECT2:", url.path)
                self.expectation.fulfill()
            }
        }

    }

    func test99Loop() {
        for i in 0..<LOOP_COUNT {
            if i > 0 { tearDown(); sleep(1); setUp() }
            test3NineUrls()
            do { tearDown(); sleep(1) }
            setUp()
            test6NineCombine()

            print("Finished Loop \(i)")
        }
    }

    func test1SingleUrl() {
        let urls = Array(allUrls[0..<1])
        runTest(urls: urls)
    }

    func test2TwoUrls() {
        let urls = Array(allUrls[0..<2])
        runTest(urls: urls)
    }

    func test3NineUrls() {
        let urls = allUrls
        runTest(urls: urls)
    }

    private func runTest(urls: [String]) {
        var expectedFulfillmentCount = 0
        for path in urls {
            // sadly, some of the fetchers get retained somehow if we don't autorelease...
            autoreleasepool {
                let url = URL(string: path)!
                let fetcher = WebFetcherStream(url: url, delegate: self)
                let byURL = ByURL(streamOwner: fetcher, inputStream: fetcher.inputStream)
                byURL.name = url.path
                assetQueue.sync {
                    self.fetchers[url] = byURL
                }
                expectedFulfillmentCount += 2   // one for the final stream message, one for the dealloc
                expectation.expectedFulfillmentCount = expectedFulfillmentCount
                fetcher.open()
            }
        }

        wait(for: [expectation], timeout: TimeInterval(urls.count * 20))

        var values: [ByURL] = []
        self.assetQueue.sync {
            self.fetchers.values.forEach({ values.append($0) })
        }
        for byURL in values {
if byURL.image == nil { LOG("NO IMAGE FOR:", byURL.name) }
            XCTAssert( !byURL.data.isEmpty )
            XCTAssert(byURL.image != nil)
        }
    }

    func test4SingleCombine() {
        let urls = Array(allUrls[0..<1])
        runTestCombine(urls: urls)
    }

    func test5TwoCombine() {
         let urls = Array(allUrls[0..<2])
         runTestCombine(urls: urls)
    }

    func test6NineCombine() {
        let urls = allUrls
         runTestCombine(urls: urls)
    }

    private func runTestCombine(urls: [String]) {
        var expectedFulfillmentCount = 0

        for path in urls {
            let url = URL(string: path)!

            var data = Data()
            let mySubscriber = AssetFetcher(url: url)
                                .sink(receiveCompletion: { (completion) in
                                    switch completion {
                                    case .finished:
                                        XCTAssert(!data.isEmpty)
                                        XCTAssertNotNil(UIImage(data: data))
                                        //LOG("SUCCESS:", data.count, UIImage(data: data) ?? "WTF")
                                    case .failure(let error):
                                        LOG("ERROR:", error)
                                    }
                                    DispatchQueue.main.async {
                                        LOG("EXPECT3:", path)
                                        self.expectation.fulfill()
                                    }
                                },
                                receiveValue: { (d) in
                                    data.append(d)
                                })
            subscribers[url] = mySubscriber

            expectedFulfillmentCount += 3   // two classes and the final Subcriber block
            expectation.expectedFulfillmentCount = expectedFulfillmentCount
        }

        wait(for: [expectation], timeout: TimeInterval(urls.count * 10))
    }


    @objc
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        dispatchPrecondition(condition: .onQueue(assetQueue))
        guard let stream = aStream as? InputStream else { fatalError() }
        guard let byURL = fetchers.values.first(where: { $0.inputStream === stream }) else { return LOG("Errant message type \(eventCode.rawValue)") }
        //let fetcher = byURL.fetcher

        byURL.events += 1
        var closeStream = false

        switch eventCode {
        case .openCompleted:
            XCTAssertEqual(byURL.events, 1)
        case .endEncountered:
            byURL.image = UIImage(data: byURL.data)
            XCTAssert(byURL.image != nil)
            closeStream = true
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
                LOG("WTF!")
            }
        case .errorOccurred:
            aStream.close()
            if let error = aStream.streamError {
                byURL.error = error
                LOG("WTF!!! Error:", error)
            } else {
                LOG("ERROR BUT NO STREAM ERROR!!!")
            }
            closeStream = true
        default:
            LOG("UNEXPECTED \(eventCode)", String(describing: eventCode))
            XCTAssert(false)
        }
        if closeStream {
            byURL.streamOwner?.close()
            DispatchQueue.main.async {
                XCTAssert(byURL.image != nil)
                LOG("IMAGE FOR NAME:", byURL.name)
                byURL.streamOwner = nil
                //LOG(eventCode == .endEncountered ? "AT END :-)" : "ERROR")
LOG("EXPECT4:", byURL.name)
                self.expectation.fulfill()
            }
        }
    }

}
