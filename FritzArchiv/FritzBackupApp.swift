//
//  FritzArchivApp.swift
//  FritzArchiv
//
//  Created by Markus Weisenauer on 03.07.26.
//

import SwiftUI

@main
struct FritzArchivApp: App {
    @State private var manager = BackupManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(manager)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
