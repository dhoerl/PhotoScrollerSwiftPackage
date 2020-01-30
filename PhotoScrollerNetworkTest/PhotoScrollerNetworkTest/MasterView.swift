//
//  ContentMaster.swift
//  PhotoScrollerNetworkTest
//
//  Created by David Hoerl on 1/21/20.
//  Copyright © 2020 Self. All rights reserved.
//

import Foundation
import SwiftUI

private let dateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .medium
    dateFormatter.timeStyle = .medium
    return dateFormatter
}()

//struct ImageModel: Identifiable {
//    let id: String
//    let url: URL
//    init(_ name: String, _ url: URL) {
//        self.id = name
//        self.url = url
//    }
//    var name: String { return id }
//}

typealias Resource = KeyValuePairs<String, URL>
typealias ResourcePair = (key: String, url: URL)

private let localFiles: KeyValuePairs<String, URL> = [
    "File A": URL(string: "https://www.apple.com/")!,
    "File B": URL(string: "https://www.apple.com/")!,
    "File C": URL(string: "https://www.apple.com/")!,
]

private let remoteFiles: KeyValuePairs<String, URL> = [
    "File A": URL(string: "https://www.apple.com/")!,
    "File B": URL(string: "https://www.apple.com/")!,
    "File C": URL(string: "https://www.apple.com/")!,
]

struct MasterView: View {
    @Binding var dates: [Date]

    var body: some View {
        MasterViewInternal(dates: $dates)
            .navigationBarTitle(
                Text("Images")
            )
//            .navigationBarItems(
//                leading: EditButton(),
//                trailing: Button(
//                    action: {
//                        //withAnimation { self.dates.insert(Date(), at: 0) }
//                    }
//                ) {
//                    Image(systemName: "plus")
//                }
//            )
    }
}

/*
 Text("123").font(.largeTitle)
 Text("123").font(.title)
 Text("123").font(.headline)
 Text("123").font(.subheadline)
 Text("123").font(.body)
 Text("123").font(.callout)
 Text("123").font(.footnote)
 Text("123").font(.caption)
 */

struct MasterViewInternal: View {
    @Binding var dates: [Date]


    var body: some View {
        List {
            Section(header: Text("Internet Based").font(.largeTitle)) { // font works!!!
                ForEach(remoteFiles, id: \.key) { pair in
                    NavigationLink(
                        destination: DetailView(kvp: pair)
                    ) {
                        Text("\(pair.key)")
                    }
                }
            }
        }.listStyle(GroupedListStyle())



//            }.onDelete { indices in
//                indices.forEach { self.dates.remove(at: $0) }
//            }
//        }
    }
}



struct MasterView_Previews: PreviewProvider {
    @State static private var dates: [Date] = [Date]()

    static var previews: some View {
        NavigationView {
            MasterView(dates: $dates)
        }
    }
}
