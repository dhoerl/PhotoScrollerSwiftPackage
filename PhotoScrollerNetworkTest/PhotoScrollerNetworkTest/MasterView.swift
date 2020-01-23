//
//  ContentMaster.swift
//  PhotoScrollerNetworkTest
//
//  Created by David Hoerl on 1/21/20.
//  Copyright © 2020 Self. All rights reserved.
//

import SwiftUI

private let dateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .medium
    dateFormatter.timeStyle = .medium
    return dateFormatter
}()

struct MasterView: View {
    @Binding var dates: [Date]

    var body: some View {
        MasterViewInternal(dates: $dates)
        .navigationBarTitle(
            Text("Images")
        )

//                .navigationBarItems(
//                    leading: EditButton(),
//                    trailing: Button(
//                        action: {
//                            withAnimation { self.dates.insert(Date(), at: 0) }
//                        }
//                    ) {
//                        Image(systemName: "plus")
//                    }
//                )
    }
}

struct MasterViewInternal: View {
    @Binding var dates: [Date]

    var body: some View {
        List {
            ForEach(dates, id: \.self) { date in
                NavigationLink(
                    destination: DetailView(selectedDate: date)
                ) {
                    Text("\(date, formatter: dateFormatter)")
                }
            }.onDelete { indices in
                indices.forEach { self.dates.remove(at: $0) }
            }
        }
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
