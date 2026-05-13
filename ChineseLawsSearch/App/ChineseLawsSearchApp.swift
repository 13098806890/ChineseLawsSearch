//
//  ChineseLawsSearchApp.swift
//  ChineseLawsSearch
//
//  Created by Xie, Dongze on 2026/4/29.
//

import SwiftUI

@main
struct ChineseLawsSearchApp: App {
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            if showSplash {
                SplashView(onFinish: { showSplash = false })
            } else {
                ContentView()
            }
        }
    }
}
