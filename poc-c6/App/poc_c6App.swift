//
//  poc_c6App.swift
//  poc-c6
//
//  Created by Zildjian Vito  on 31/10/26.
//

import SwiftUI

@main
struct poc_c6App: App {
    @State private var flow = AppFlow(container: .makeDefault())

    var body: some Scene {
        WindowGroup {
            RootView(flow: flow)
        }
    }
}
