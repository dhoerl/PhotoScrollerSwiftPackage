//
//  ContentDetail.swift
//  PhotoScrollerNetworkTest
//
//  Created by David Hoerl on 1/21/20.
//  Copyright © 2020 Self. All rights reserved.
//

import SwiftUI


struct DetailView: View {
    @EnvironmentObject var appEnvironment: AppEnvironment
    var kvp: (key: String, value: URL)

    
//    @Binding var dates: [Date]

//    init(_ dates: Binding<[Date]>) {
//        self.dates = dates
//
//        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
//            self.dates.insert(Date(), at: 0)
//            print("FAD")
//        }
//    }

    var body: some View {

//NavigationView {
        Group {
            if kvp.key != "" {
                Text("\(kvp.key)")
//                .onAppear {
//                    withAnimation(Animation.easeInOut(duration: 2.0)) {
//                        //self.animate = true
//                    }
//                }
            } else {
                Text("Detail view content goes here")
            }
        }
//}
            .navigationBarTitle(Text("Detail"), displayMode: .inline)
            .navigationBarItems(
                //leading: Text("Howdie"),
                trailing: Button(
                    action: {
                        //withAnimation { self.dates.insert(Date(), at: 0) }
                    }
                ) {
                    Image(systemName: "plus")
                }
            )
    }
}

//struct DetailView_Previews: PreviewProvider {
//    static var previews: some View {
//        DetailView(selectedDate: Date())
//    }
//}

