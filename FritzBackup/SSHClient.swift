import Foundation

enum SSHFehler: LocalizedError {
    case befehlFehlgeschlagen(String)
    case verbindungFehlgeschlagen(String)

    var errorDescription: String? {
        switch self {
        case .befehlFehlgeschlagen(let m): return "SSH-Fehler: \(m)"
        case .verbindungFehlgeschlagen(let m): return "Verbindungsfehler: \(m)"
        }
    }
}

struct BackupTag: Identifiable, Hashable {
    let id = UUID()
    let datumString: String
    let datum: Date
    let groesse: String
}

final class DateiEintrag: Identifiable {
    let id = UUID()
    let pfad: String
    let name: String
    let istOrdner: Bool
    let groesse: Int
    var kinder: [DateiEintrag]?

    init(pfad: String, istOrdner: Bool, groesse: Int) {
        self.pfad      = pfad
        self.name      = String(pfad.split(separator: "/").last ?? Substring(pfad))
        self.istOrdner = istOrdner
        self.groesse   = groesse
        self.kinder    = istOrdner ? [] : nil
    }

    var groesseFormatiert: String {
        guard !istOrdner else { return "" }
        if groesse < 1_024 { return "\(groesse) B" }
        if groesse < 1_048_576 { return "\(groesse / 1_024) KB" }
        return String(format: "%.1f MB", Double(groesse) / 1_048_576)
    }

    static func baum(aus liste: [DateiEintrag]) -> [DateiEintrag] {
        var verzeichnisse: [String: DateiEintrag] = [:]
        var wurzeln: [DateiEintrag] = []
        for e in liste.sorted(by: { $0.pfad < $1.pfad }) {
            if e.istOrdner { verzeichnisse[e.pfad] = e }
            let elternPfad: String
            if let idx = e.pfad.lastIndex(of: "/") {
                elternPfad = String(e.pfad[..<idx])
            } else {
                elternPfad = ""
            }
            if elternPfad.isEmpty {
                wurzeln.append(e)
            } else if let eltern = verzeichnisse[elternPfad] {
                eltern.kinder?.append(e)
            }
        }
        return wurzeln
    }
}

class SSHClient {
    private let host: String
    private let benutzer: String
    private let keyPfad = "\(NSHomeDirectory())/.ssh/id_ed25519"

    init(einstellungen: BackupSettings) {
        self.host     = einstellungen.piHost
        self.benutzer = einstellungen.piBenutzer
    }

    func ausfuehrenRoh(_ befehl: String) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            p.arguments = [
                "-i", keyPfad,
                "-o", "StrictHostKeyChecking=no",
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=10",
                "\(benutzer)@\(host)",
                befehl
            ]
            let out = Pipe(); let err = Pipe()
            p.standardOutput = out; p.standardError = err
            p.terminationHandler = { proc in
                let daten = out.fileHandleForReading.readDataToEndOfFile()
                if proc.terminationStatus == 0 {
                    cont.resume(returning: daten)
                } else {
                    let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unbekannt"
                    cont.resume(throwing: SSHFehler.befehlFehlgeschlagen(msg))
                }
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }

    func ausfuehren(_ befehl: String) async throws -> String {
        let d = try await ausfuehrenRoh(befehl)
        return String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1) ?? ""
    }

    func verbindungTesten() async throws -> String {
        try await ausfuehren("echo OK && hostname && uptime")
    }

    func backupListe(pfad: String) async throws -> [BackupTag] {
        let ausgabe = try await ausfuehren("du -sh \(pfad)/????-??-?? 2>/dev/null | sort -r")
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        return ausgabe.components(separatedBy: "\n").compactMap { zeile in
            let t = zeile.split(separator: "\t", maxSplits: 1)
            guard t.count == 2 else { return nil }
            let groesse = String(t[0]).trimmingCharacters(in: .whitespaces)
            let datumStr = URL(fileURLWithPath: String(t[1]).trimmingCharacters(in: .whitespaces)).lastPathComponent
            guard let datum = fmt.date(from: datumStr) else { return nil }
            return BackupTag(datumString: datumStr, datum: datum, groesse: groesse)
        }
    }

    func dateiListe(backupPfad: String, datumString: String) async throws -> [DateiEintrag] {
        let basis = "\(backupPfad)/\(datumString)"
        let ausgabe = try await ausfuehren(
            "find \(basis) \\( -type f -o -type d \\) -printf '%y\\t%s\\t%P\\n' 2>/dev/null | sort"
        )
        return ausgabe.components(separatedBy: "\n").compactMap { zeile in
            guard !zeile.isEmpty else { return nil }
            let t = zeile.split(separator: "\t", maxSplits: 2)
            guard t.count == 3 else { return nil }
            let pfad = String(t[2])
            guard !pfad.isEmpty else { return nil }
            return DateiEintrag(pfad: pfad, istOrdner: t[0] == "d", groesse: Int(t[1]) ?? 0)
        }
    }

    func dateiInhalt(backupPfad: String, datumString: String, relativerPfad: String) async throws -> Data {
        let vollPfad = "\(backupPfad)/\(datumString)/\(relativerPfad)"
            .replacingOccurrences(of: "'", with: "'\\''")
        return try await ausfuehrenRoh("cat '\(vollPfad)'")
    }

    func letzterLog(logPfad: String) async throws -> String {
        try await ausfuehren("tail -30 \(logPfad) 2>/dev/null || echo 'Kein Log gefunden'")
    }

    func backupStarten(scriptPfad: String) async throws -> String {
        try await ausfuehren("bash \(scriptPfad) 2>&1; tail -3 \(scriptPfad.replacingOccurrences(of: "backup_fritzbox.sh", with: "backup/backup.log"))")
    }
}
