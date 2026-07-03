//
//  FritzBackupApp.swift
//  FritzBackup
//
//  Created by Markus Weisenauer on 03.07.26.
//

import SwiftUI
import CoreData

@main
struct FritzBackupApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
