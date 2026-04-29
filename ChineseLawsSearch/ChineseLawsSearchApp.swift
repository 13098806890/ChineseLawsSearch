//
//  ChineseLawsSearchApp.swift
//  ChineseLawsSearch
//
//  Created by Xie, Dongze on 2026/4/29.
//

import SwiftUI
import SwiftData

@main
struct ChineseLawsSearchApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
