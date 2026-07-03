

import SwiftUI

struct StatusView: View {
    @Environment(BackupManager.self) private var manager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Backup-Status")
                        .font(.largeTitle).bold()
                    Text("Raspberry Pi · \(manager.einstellungen.piHost)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await manager.backupTageLaden() }
                } label: {
                    Label("Aktualisieren", systemImage: "arrow.clockwise")
                }
                .disabled(manager.istLaden)

                Button {
                    Task { await manager.backupStarten() }
                } label: {
                    if manager.backupLaeuft {
                        Label("Läuft…", systemImage: "clock")
                    } else {
                        Label("Backup starten", systemImage: "externaldrive.badge.plus")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(manager.backupLaeuft || !manager.einstellungen.piIstKonfiguriert)
            }
            .padding()

            Divider()

            if manager.istLaden && !manager.backupLaeuft {
                ProgressView().padding()
            }

            // Übersicht
            HStack(spacing: 20) {
                StatusKarte(
                    titel: "Backups gesamt",
                    wert: "\(manager.backupTage.count)",
                    symbol: "calendar"
                )
                StatusKarte(
                    titel: "Letztes Backup",
                    wert: manager.backupTage.first.map { formatDatum($0.datum) } ?? "–",
                    symbol: "clock"
                )
                StatusKarte(
                    titel: "Größe (letztes)",
                    wert: manager.backupTage.first?.groesse ?? "–",
                    symbol: "internaldrive"
                )
            }
            .padding()

            Divider()

            // Laufende Meldung
            if !manager.statusMeldung.isEmpty {
                HStack {
                    if manager.backupLaeuft { ProgressView().scaleEffect(0.7) }
                    Text(manager.statusMeldung)
                        .font(.callout)
                        .foregroundStyle(manager.backupLaeuft ? Color.primary : Color.green)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            if let fehler = manager.fehler {
                Text(fehler)
                    .foregroundStyle(Color.red)
                    .font(.callout)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            // Log
            VStack(alignment: .leading, spacing: 6) {
                Text("Backup-Log")
                    .font(.headline)
                ScrollView {
                    Text(manager.logInhalt.isEmpty ? "Noch kein Log vorhanden." : manager.logInhalt)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
            }
            .padding()
        }
        .task { await manager.backupTageLaden() }
    }

    private func formatDatum(_ datum: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium; f.timeStyle = .none; f.locale = Locale(identifier: "de_DE")
        return f.string(from: datum)
    }
}

private struct StatusKarte: View {
    let titel: String
    let wert: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(titel, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(wert)
                .font(.title2).bold()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
