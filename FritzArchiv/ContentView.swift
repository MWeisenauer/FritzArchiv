import SwiftUI

enum Ansicht: Hashable {
    case status, backups, wiederherstellen, upload, einstellungen
}

struct ContentView: View {
    @Environment(BackupManager.self) private var manager
    @State private var auswahl: Ansicht? = .status

    var body: some View {
        NavigationSplitView {
            List(selection: $auswahl) {
                Section("Übersicht") {
                    Label("Status", systemImage: "externaldrive.connected.to.line.below")
                        .tag(Ansicht.status)
                    Label("Backups", systemImage: "calendar")
                        .tag(Ansicht.backups)
                    Label("Wiederherstellen", systemImage: "arrow.counterclockwise")
                        .tag(Ansicht.wiederherstellen)
                    Label("Upload", systemImage: "arrow.up.to.line")
                        .tag(Ansicht.upload)
                }
                Section {
                    Label("Einstellungen", systemImage: "gearshape")
                        .tag(Ansicht.einstellungen)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                switch auswahl {
                case .status:
                    StatusView()
                case .backups:
                    BackupsView()
                case .wiederherstellen:
                    WiederherstellenView()
                case .upload:
                    UploadView()
                case .einstellungen:
                    EinstellungenView()
                case nil:
                    ContentUnavailableView("Willkommen", systemImage: "externaldrive",
                                           description: Text("Wähle links eine Ansicht."))
                }
            }
            .environment(manager)
        }
        .frame(minWidth: 750, minHeight: 500)
    }
}
