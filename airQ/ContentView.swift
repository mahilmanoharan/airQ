//
//  ContentView.swift
//  airQ
//
//  Created by Mahil Manoharan on 4/12/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Location: Chapel Hill, NC")
            Text("AQI: 50")
            Text("")
        }
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
    }
}

#Preview {
    ContentView()
}
