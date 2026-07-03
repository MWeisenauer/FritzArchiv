import SwiftUI

struct WiederherstellenView: View {
    @Environment(BackupManager.self) private var manager
    @State private var ausgewaehlterTag: BackupTag?
    @State private var ausgewaehltePfade: Set<String> = []
    @State private var zeigeBestaetigung = false

    private var ausgewaehlteDateien: [DateiEintrag] {
        alleBlattdateien(aus: manager.dateibaum).filter { ausgewaehltePfade.contains($0.pfad) }
    }

    var body: some View {
        HSplitView {
            // Linke Spalte: Backup-Tag-Auswahl
            VStack(alignment: .leading, spacing: 0) {
                Text("Backup wählen")
                    .font(.headline).padding()
                Divider()
                List(manager.backupTage, selection: $ausgewaehlterTag) { tag in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tag.datumString).font(.body)
                        Text(tag.groesse).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .tag(tag)
                }
            }
            .frame(minWidth: 150, idealWidth: 170, maxWidth: 200)

            // Rechte Spalte: Dateiauswahl + Restore
            VStack(alignment: .leading, spacing: 0) {
                // Toolbar
                HStack {
                    if let tag = ausgewaehlterTag {
                        Text("Backup: \(tag.datumString)")
                            .font(.headline)
                    } else {
                        Text("Kein Backup gewählt").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Alle") {
                        let alle = alleBlattdateien(aus: manager.dateibaum).map(\.pfad)
                        ausgewaehltePfade = Set(alle)
                    }
                    .disabled(manager.dateibaum.isEmpty)

                    Button("Keine") { ausgewaehltePfade.removeAll() }
                        .disabled(ausgewaehltePfade.isEmpty)

                    Divider().frame(height: 20)

                    Button {
                        zeigeBestaetigung = true
                    } label: {
                        Label("Wiederherstellen (\(ausgewaehltePfade.count))", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(ausgewaehltePfade.isEmpty || manager.istLaden)
                }
                .padding()

                Divider()

                if !manager.statusMeldung.isEmpty {
                    HStack {
                        if manager.istLaden { ProgressView().scaleEffect(0.7) }
                        Text(manager.statusMeldung).font(.callout)
                            .foregroundStyle(manager.istLaden ? Color.primary : Color.green)
                    }
                    .padding(.horizontal).padding(.top, 6)
                }

                if let fehler = manager.fehler {
                    Text(fehler).foregroundStyle(Color.red).font(.callout)
                        .padding(.horizontal).padding(.top, 6)
                }

                // Dateibaum mit Checkbox-Auswahl
                if manager.dateibaum.isEmpty && !manager.istLaden {
                    ContentUnavailableView("Kein Backup geladen",
                                          systemImage: "arrow.counterclockwise.circle",
                                          description: Text("Wähle links einen Backup-Tag aus."))
                } else {
                    List(manager.dateibaum, children: \.kinderOderNil) { eintrag in
                        DateiZeile(eintrag: eintrag, ausgewaehlt: istGewaehlt(eintrag)) {
                            umschalten(eintrag)
                        }
                    }
                }
            }
        }
        .onChange(of: ausgewaehlterTag) { _, tag in
            guard let tag else { return }
            ausgewaehltePfade.removeAll()
            Task { await manager.dateiListeLaden(fuer: tag) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await manager.backupTageLaden() }
        .confirmationDialog(
            "Wirklich \(ausgewaehltePfade.count) Datei(en) auf die Fritz!Box zurückspielen?",
            isPresented: $zeigeBestaetigung,
            titleVisibility: .visible
        ) {
            Button("Wiederherstellen", role: .destructive) {
                Task { await manager.wiederherstellen(eintraege: ausgewaehlteDateien) }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private func istGewaehlt(_ eintrag: DateiEintrag) -> Bool {
        if eintrag.istOrdner {
            let blätter = alleBlattdateien(aus: eintrag.kinder ?? [])
            return !blätter.isEmpty && blätter.allSatisfy { ausgewaehltePfade.contains($0.pfad) }
        }
        return ausgewaehltePfade.contains(eintrag.pfad)
    }

    private func umschalten(_ eintrag: DateiEintrag) {
        if eintrag.istOrdner {
            let unterDateien = alleBlattdateien(aus: eintrag.kinder ?? []).map(\.pfad)
            let alleGewaehlt = unterDateien.allSatisfy { ausgewaehltePfade.contains($0) }
            if alleGewaehlt { unterDateien.forEach { ausgewaehltePfade.remove($0) } }
            else { unterDateien.forEach { ausgewaehltePfade.insert($0) } }
        } else {
            if ausgewaehltePfade.contains(eintrag.pfad) { ausgewaehltePfade.remove(eintrag.pfad) }
            else { ausgewaehltePfade.insert(eintrag.pfad) }
        }
    }

    private func alleBlattdateien(aus liste: [DateiEintrag]) -> [DateiEintrag] {
        liste.flatMap { e -> [DateiEintrag] in
            e.istOrdner ? alleBlattdateien(aus: e.kinder ?? []) : [e]
        }
    }
}

private struct DateiZeile: View {
    let eintrag: DateiEintrag
    let ausgewaehlt: Bool
    let aktion: () -> Void

    var body: some View {
        HStack {
            Button { aktion() } label: {
                Image(systemName: ausgewaehlt ? "checkmark.square.fill" : "square")
                    .foregroundStyle(ausgewaehlt ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            Image(systemName: eintrag.istOrdner ? "folder.fill" : "doc")
                .foregroundStyle(eintrag.istOrdner ? Color.yellow : Color.secondary)
            Text(eintrag.name)
            Spacer()
            if !eintrag.groesseFormatiert.isEmpty {
                Text(eintrag.groesseFormatiert).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
