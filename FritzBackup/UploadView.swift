import SwiftUI
import UniformTypeIdentifiers
import Observation

// MARK: - Datenmodell Fritz!Box-Ordner (lazy geladen)

@Observable
final class FritzOrdner: Identifiable {
    let id = UUID()
    let name: String
    let pfad: String
    var kinder: [FritzOrdner]? = nil   // nil = noch nicht geladen
    var laedt = false
    let istPlatzhalter: Bool

    init(name: String, pfad: String, istPlatzhalter: Bool = false) {
        self.name = name; self.pfad = pfad; self.istPlatzhalter = istPlatzhalter
    }

    var kinderFuerListe: [FritzOrdner]? {
        if let k = kinder { return k.isEmpty ? nil : k }
        // Noch nicht geladen: Platzhalter zeigt Disclosure-Pfeil
        return [FritzOrdner(name: "Lädt…", pfad: pfad, istPlatzhalter: true)]
    }
}

// MARK: - UploadView

struct UploadView: View {
    @Environment(BackupManager.self) private var manager

    @State private var ordnerBaum: [FritzOrdner] = []
    @State private var ausgewaehlterPfad: String = ""
    @State private var baumLaedt = true

    // Dateiauswahl + Upload
    @State private var ausgewaehlteDateien: [URL] = []
    @State private var zeigeFilePicker = false
    @State private var uploadLaedt = false
    @State private var meldung: String?
    @State private var fehlerMeldung: String?
    @State private var fortschritt: Double = 0

    var body: some View {
        HSplitView {
            // ── Linke Spalte: Fritz!Box Ordner-Tree ────────────────────────
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Zielordner").font(.headline)
                    Spacer()
                    if baumLaedt { ProgressView().scaleEffect(0.7) }
                }
                .padding()
                Divider()

                if !ausgewaehlterPfad.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
                        Text(ausgewaehlterPfad).font(.caption).lineLimit(1)
                    }
                    .padding(.horizontal).padding(.vertical, 6)
                    Divider()
                }

                List(ordnerBaum, children: \.kinderFuerListe) { ordner in
                    if ordner.istPlatzhalter {
                        Label("Lädt…", systemImage: "ellipsis.circle")
                            .foregroundStyle(.secondary).font(.callout)
                    } else {
                        HStack {
                            Image(systemName: "folder.fill").foregroundStyle(Color.yellow)
                            Text(ordner.name)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .background(ausgewaehlterPfad == ordner.pfad
                                    ? Color.accentColor.opacity(0.15) : Color.clear)
                        .onTapGesture { ausgewaehlterPfad = ordner.pfad }
                        .onAppear {
                            guard ordner.kinder == nil && !ordner.laedt else { return }
                            ordner.laedt = true
                            Task { await ladeKinder(fuer: ordner) }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)

            // ── Rechte Spalte: Dateiauswahl + Upload ───────────────────────
            VStack(alignment: .leading, spacing: 16) {
                Text("Dateien hochladen").font(.title2).bold()

                GroupBox("Lokale Dateien") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button { zeigeFilePicker = true } label: {
                            Label("Dateien wählen…", systemImage: "plus.circle")
                        }
                        if ausgewaehlteDateien.isEmpty {
                            Text("Noch keine Dateien ausgewählt.")
                                .foregroundStyle(.secondary).font(.callout)
                        } else {
                            ForEach(ausgewaehlteDateien, id: \.self) { url in
                                HStack {
                                    Image(systemName: "doc").foregroundStyle(.secondary)
                                    Text(url.lastPathComponent).lineLimit(1)
                                    Spacer()
                                    Text(dateiGroesse(url)).font(.caption).foregroundStyle(.secondary)
                                    Button {
                                        ausgewaehlteDateien.removeAll { $0 == url }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Button { Task { await hochladen() } } label: {
                        if uploadLaedt {
                            Label("Hochladen…", systemImage: "arrow.up.to.line")
                        } else {
                            Label("Hochladen (\(ausgewaehlteDateien.count)) → \(ausgewaehlterPfad.isEmpty ? "/" : ausgewaehlterPfad)",
                                  systemImage: "arrow.up.to.line")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(ausgewaehlteDateien.isEmpty || uploadLaedt || !manager.einstellungen.fritzIstKonfiguriert)

                    if uploadLaedt && ausgewaehlteDateien.count > 1 {
                        ProgressView(value: fortschritt).frame(maxWidth: 250)
                    }
                    if let m = meldung {
                        Label(m, systemImage: "checkmark.circle.fill").foregroundStyle(Color.green)
                    }
                    if let f = fehlerMeldung {
                        Label(f, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.red)
                    }
                    if !manager.einstellungen.fritzIstKonfiguriert {
                        Label("Fritz!Box in Einstellungen konfigurieren.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
            }
            .padding()
        }
        .task { await wurzelLaden() }
        .fileImporter(isPresented: $zeigeFilePicker,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { ergebnis in
            if case .success(let urls) = ergebnis {
                ausgewaehlteDateien.append(contentsOf: urls.filter { !ausgewaehlteDateien.contains($0) })
            }
        }
    }

    // MARK: - Laden

    private func wurzelLaden() async {
        baumLaedt = true
        let client = FTPSRestoreClient(einstellungen: manager.einstellungen)
        do {
            let namen = try await client.verzeichnisListe(pfad: "")
            ordnerBaum = namen.map { FritzOrdner(name: $0, pfad: $0) }
        } catch { }
        baumLaedt = false
    }

    private func ladeKinder(fuer ordner: FritzOrdner) async {
        let client = FTPSRestoreClient(einstellungen: manager.einstellungen)
        do {
            let namen = try await client.verzeichnisListe(pfad: ordner.pfad)
            ordner.kinder = namen.map { name in
                FritzOrdner(name: name, pfad: "\(ordner.pfad)/\(name)")
            }
        } catch {
            ordner.kinder = []
        }
        ordner.laedt = false
    }

    // MARK: - Upload

    private func hochladen() async {
        uploadLaedt = true; meldung = nil; fehlerMeldung = nil; fortschritt = 0
        let client = FTPSRestoreClient(einstellungen: manager.einstellungen)
        var erfolgreich = 0
        let gesamt = ausgewaehlteDateien.count
        for (i, url) in ausgewaehlteDateien.enumerated() {
            let zugriff = url.startAccessingSecurityScopedResource()
            defer { if zugriff { url.stopAccessingSecurityScopedResource() } }
            do {
                let daten = try Data(contentsOf: url)
                let ziel = ausgewaehlterPfad.isEmpty ? url.lastPathComponent
                                                     : "\(ausgewaehlterPfad)/\(url.lastPathComponent)"
                try await client.dateiHochladen(relativerPfad: ziel, daten: daten)
                erfolgreich += 1
                fortschritt = Double(i + 1) / Double(gesamt)
            } catch {
                fehlerMeldung = "\(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        uploadLaedt = false
        if erfolgreich > 0 {
            meldung = "\(erfolgreich) von \(gesamt) Datei(en) hochgeladen."
            if erfolgreich == gesamt { ausgewaehlteDateien.removeAll() }
        }
    }

    private func dateiGroesse(_ url: URL) -> String {
        let zugriff = url.startAccessingSecurityScopedResource()
        defer { if zugriff { url.stopAccessingSecurityScopedResource() } }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attrs[.size] as? Int64 else { return "" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
