import SwiftUI

struct EinstellungenView: View {
    @Environment(BackupManager.self) private var manager
    @State private var piTestErgebnis: String?
    @State private var fritzTestErgebnis: String?
    @State private var piTestLaeuft = false
    @State private var fritzTestLaeuft = false
    @State private var gespeichert = false

    var body: some View {
        @Bindable var manager = manager

        Form {
            // ── Pi SSH ──────────────────────────────────────────────────────
            Section("Raspberry Pi (SSH)") {
                TextField("IP-Adresse / Hostname", text: $manager.einstellungen.piHost)
                TextField("Benutzername", text: $manager.einstellungen.piBenutzer)
                TextField("Backup-Verzeichnis", text: $manager.einstellungen.backupPfad)
                TextField("Backup-Script", text: $manager.einstellungen.scriptPfad)
                LabeledContent("SSH-Key") {
                    Text("~/.ssh/id_ed25519").foregroundStyle(.secondary)
                }
                HStack {
                    Button {
                        piTestLaeuft = true; piTestErgebnis = nil
                        Task {
                            piTestErgebnis = await manager.piVerbindungTesten()
                            piTestLaeuft = false
                        }
                    } label: {
                        if piTestLaeuft { ProgressView().scaleEffect(0.7) }
                        else { Label("Verbindung testen", systemImage: "network") }
                    }
                    .disabled(piTestLaeuft || !manager.einstellungen.piIstKonfiguriert)

                    if let e = piTestErgebnis {
                        Text(e).font(.caption)
                            .foregroundStyle(e.contains("OK") ? Color.green : Color.red)
                            .lineLimit(2)
                    }
                }
            }

            // ── Fritz!Box FTPS ──────────────────────────────────────────────
            Section("Fritz!Box (FTPS — für Restore)") {
                TextField("Host / IP", text: $manager.einstellungen.fritzHost)
                TextField("Port", value: $manager.einstellungen.fritzPort, format: .number)
                TextField("Benutzername", text: $manager.einstellungen.fritzBenutzer)
                SecureField("Passwort", text: $manager.einstellungen.fritzPasswort)
                TextField("Basispfad", text: $manager.einstellungen.fritzPfad)
                Toggle("Selbstsigniertes Zertifikat akzeptieren",
                       isOn: $manager.einstellungen.zertifikatIgnorieren)
                HStack {
                    Button {
                        fritzTestLaeuft = true; fritzTestErgebnis = nil
                        Task {
                            fritzTestErgebnis = await manager.fritzVerbindungTesten()
                            fritzTestLaeuft = false
                        }
                    } label: {
                        if fritzTestLaeuft { ProgressView().scaleEffect(0.7) }
                        else { Label("Verbindung testen", systemImage: "network") }
                    }
                    .disabled(fritzTestLaeuft || !manager.einstellungen.fritzIstKonfiguriert)

                    if let e = fritzTestErgebnis {
                        Text(e).font(.caption)
                            .foregroundStyle(e.contains("erfolgreich") ? Color.green : Color.red)
                            .lineLimit(2)
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    if gespeichert {
                        Label("Gespeichert", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                            .transition(.opacity)
                    }
                    Button("Einstellungen speichern") {
                        manager.einstellungenSpeichern()
                        withAnimation { gespeichert = true }
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation { gespeichert = false }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
    }
}
