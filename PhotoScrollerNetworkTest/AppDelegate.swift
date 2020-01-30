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

        webTest()


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
                        .sink(receiveCompletion: { (error) in
                            print("SINK ERROR:", error)
                        },
                        receiveValue: { (data) in
                            print("SINK: got data:", data.count)
                        })

    }

    func fileTest() {
        let path = Bundle.main.path(forResource: "Coffee", ofType: "jpg")!
        let url = URL(fileURLWithPath: path)

        fileFetcher = FileFetcherStream(url: url, queue: assetQueue, delegate: self)
        fileFetcher?.open()
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
                do {
                    //var byte: UInt8 = 0
                    var ptr: UnsafeMutablePointer<UInt8>? = nil
                    var len: Int = 0

                    if stream.getBuffer(&ptr, length: &len) {
                        print("HAHAHA GOT \(len)")
                        if let ptr = ptr {
                            print("and pointer:", String(describing: ptr))
                        }
                    } else {
                        //print("AH FUCK NO GETBUFFER!!!")
                    }
                }
                let askLen = 4_096
                let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: askLen)


                let readLen = stream.read(bytes, maxLength: askLen)
//                print("READLEN:", readLen)
//                if self.outputStream.hasSpaceAvailable {
//                    let writeLen = self.outputStream.write(bytes, maxLength: readLen)
//                    print("READ: writeLen=\(writeLen)")
//                } else {
//                    print("READ: no space!!!")
//                }
//                if readLen < askLen {
//                    print("READ 1 \(readLen) bytes!")
//                } else {
//                    print("READ 2 \(readLen) bytes!")
//                }

                if readLen == 0 {
                    print("WTF!")
                }
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
