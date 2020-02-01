//
//  AppDelegate.swift
//  PhotoScrollerNetworkTest
//
//  Created by David Hoerl on 1/21/20.
//  Copyright © 2020 Self. All rights reserved.
//

import UIKit
import Combine
import Network

private let assetQueue = DispatchQueue(label: "com.AssetFetcher", qos: .userInitiated)

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    private var fileFetcher: FileFetcherStream?
    private var webFetcher: WebFetcherStream?
    private var mySubscriber: AnyCancellable?
    private var data = Data()

// private lazy var  pmC = NWPathMonitor(requiredInterfaceType: .cellular)
// private lazy var  pmW = NWPathMonitor(requiredInterfaceType: .wifi)

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.



//pmC.pathUpdateHandler = { (path: NWPath) in
//    print("C PATH STATUS:", path.status)
//    path.availableInterfaces.forEach( { interfce in
//        DispatchQueue.main.async {
//            print("  C INTERFACE:", interfce, "Status:", path.status)
//        }
//    } )
//}
//pmC.start(queue: assetQueue)
//
//pmW.pathUpdateHandler = { (path: NWPath) in
//    print("W PATH STATUS:", path.status)
//    path.availableInterfaces.forEach( { interfce in
//        DispatchQueue.main.async {
//            print("  W INTERFACE:", interfce, "Status:", path.status)
//        }
//    } )
//}
//pmW.start(queue: assetQueue)

        //fileTest()
        //combineFileTest()

        //webTest()
        combineWebTest()


        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

}

extension AppDelegate: StreamDelegate {

    func combineFileTest() {
        let path = Bundle.main.path(forResource: "Coffee", ofType: "jpg")!
        let url = URL(fileURLWithPath: path)

        mySubscriber = AssetFetcher(url: url)
                        .sink(receiveCompletion: { (completion) in
                            switch completion {
                            case .finished:
                                print("SUCCESS:", self.data.count, UIImage(data: self.data) ?? "WTF")
                            case .failure(let error):
                                print("ERROR:", error)
                            }
                            DispatchQueue.main.async {
                                self.mySubscriber = nil
                            }
                        },
                        receiveValue: { (data) in
                            //print("SINK: got data:", data.count)
                            self.data.append(data)
                        })
//DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//    self.mySubscriber?.cancel()
//}

    }

    func fileTest() {
        let path = Bundle.main.path(forResource: "Coffee", ofType: "jpg")!
        let url = URL(fileURLWithPath: path)

        fileFetcher = FileFetcherStream(url: url, queue: assetQueue, delegate: self)
        fileFetcher?.open()
    }

    func combineWebTest() {
        let url = URL(string: "https://www.dropbox.com/s/b337y2sn1597sry/Lake.jpg?dl=1")!

        mySubscriber = AssetFetcher(url: url)
                        .sink(receiveCompletion: { (completion) in
                            switch completion {
                            case .finished:
                                print("SUCCESS:", self.data.count, UIImage(data: self.data) ?? "WTF")
                            case .failure(let error):
                                print("ERROR:", error)
                            }
                            DispatchQueue.main.async {
                                self.mySubscriber = nil
                            }
                        },
                        receiveValue: { (data) in
                            //print("SINK: got data:", data.count)
                            self.data.append(data)
                        })

//        mySubscriber = AssetFetcher(url: url)
//                        .sink(receiveCompletion: { (error) in
//                            print("SINK ERROR:", error)
//                        },
//                        receiveValue: { (data) in
//                            print("SINK: got data:", data.count)
//                        })

    }

    func webTest() {
        WebFetcherStream.startMonitoring(onQueue: assetQueue)

        let url = URL(string: "https://www.dropbox.com/s/b337y2sn1597sry/Lake.jpg?dl=1")!

        webFetcher = WebFetcherStream(url: url, delegate: self) // uses assetQueue
        webFetcher?.open()
    }

    @objc
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        dispatchPrecondition(condition: .onQueue(assetQueue))

        switch eventCode {
        case .openCompleted:
            print("OPEN COMPLETED")
        case .endEncountered:
            print("AT END :-)")

            DispatchQueue.main.async {
                self.fileFetcher?.close()    // NOT stream!!!
                self.webFetcher?.close()
                self.fileFetcher = nil
                self.webFetcher = nil
            }
        case .hasBytesAvailable:
            guard let stream = aStream as? InputStream else { fatalError() }
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

#if false
            if readLen < askLen {
                print("READ 1 \(readLen) bytes!")
            } else {
                print("READ 2 \(readLen) bytes!")
            }
#endif

            if readLen == 0 {
                print("WTF!")
            }
        case .errorOccurred:
            aStream.close()
            if let error = aStream.streamError {
                print("WTF!!! Error:", error)
            } else {
                print("ERROR BUT NO STREAM ERROR!!!")
            }
        default:
            print("UNEXPECTED \(eventCode)", String(describing: eventCode))
        }
    }

}
