import SwiftUI

struct BackupsView: View {
    @Environment(BackupManager.self) private var manager
    @State private var ausgewaehlt: BackupTag?

    var body: some View {
        HSplitView {
            // Linke Spalte: Liste der Backup-Tage
            VStack(alignment: .leading, spacing: 0) {
                Text("Backup-Tage")
                    .font(.headline)
                    .padding()
                Divider()
                if manager.backupTage.isEmpty {
                    ContentUnavailableView("Keine Backups", systemImage: "calendar.badge.exclamationmark",
                                          description: Text("Noch kein Backup vorhanden."))
                } else {
                    List(manager.backupTage, selection: $ausgewaehlt) { tag in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tagFormatiert(tag.datumString))
                                .font(.body)
                            Text(tag.groesse)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .tag(tag)
                    }
                }
            }
            .frame(minWidth: 160, idealWidth: 180, maxWidth: 220)

            // Rechte Spalte: Dateien im ausgewählten Backup
            VStack {
                if let tag = ausgewaehlt {
                    DateienView(tag: tag)
                        .environment(manager)
                } else {
                    ContentUnavailableView("Kein Backup ausgewählt",
                                          systemImage: "calendar",
                                          description: Text("Wähle links einen Tag aus."))
                }
            }
        }
        .onChange(of: ausgewaehlt) { _, neuerTag in
            guard let tag = neuerTag else { return }
            Task { await manager.dateiListeLaden(fuer: tag) }
        }
        .task { await manager.backupTageLaden() }
    }

    private func tagFormatiert(_ datumString: String) -> String {
        let ein = DateFormatter(); ein.dateFormat = "yyyy-MM-dd"
        let aus = DateFormatter(); aus.dateStyle = .full; aus.locale = Locale(identifier: "de_DE")
        guard let datum = ein.date(from: datumString) else { return datumString }
        return aus.string(from: datum)
    }
}

struct DateienView: View {
    @Environment(BackupManager.self) private var manager
    let tag: BackupTag

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Inhalt: \(tag.datumString)")
                    .font(.headline)
                Spacer()
                if manager.istLaden { ProgressView().scaleEffect(0.8) }
            }
            .padding()
            Divider()
            if manager.dateibaum.isEmpty && !manager.istLaden {
                ContentUnavailableView("Leer", systemImage: "doc", description: Text("Keine Dateien gefunden."))
            } else {
                List(manager.dateibaum, children: \.kinderOderNil) { eintrag in
                    HStack {
                        Image(systemName: eintrag.istOrdner ? "folder.fill" : "doc")
                            .foregroundStyle(eintrag.istOrdner ? .yellow : .secondary)
                        Text(eintrag.name)
                        Spacer()
                        if !eintrag.groesseFormatiert.isEmpty {
                            Text(eintrag.groesseFormatiert)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

extension DateiEintrag {
    var kinderOderNil: [DateiEintrag]? {
        guard istOrdner, let k = kinder, !k.isEmpty else { return nil }
        return k
    }
}
