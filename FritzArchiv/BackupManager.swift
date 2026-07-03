import Foundation
import Observation

@Observable
class BackupManager {
    var einstellungen = BackupSettings.laden()
    var backupTage: [BackupTag] = []
    var dateibaum: [DateiEintrag] = []
    var ausgewaehlterTag: BackupTag?
    var logInhalt: String = ""
    var statusMeldung: String = ""
    var istLaden = false
    var fehler: String?
    var backupLaeuft = false

    private var sshClient: SSHClient { SSHClient(einstellungen: einstellungen) }

    // MARK: - Pi

    func backupTageLaden() async {
        guard einstellungen.piIstKonfiguriert else {
            fehler = "Bitte zuerst die Pi-Einstellungen konfigurieren."
            return
        }
        istLaden = true; fehler = nil
        do {
            backupTage = try await sshClient.backupListe(pfad: einstellungen.backupPfad)
            logInhalt  = try await sshClient.letzterLog(logPfad: einstellungen.logPfad)
        } catch {
            fehler = error.localizedDescription
        }
        istLaden = false
    }

    func dateiListeLaden(fuer tag: BackupTag) async {
        istLaden = true; fehler = nil
        ausgewaehlterTag = tag
        do {
            let liste = try await sshClient.dateiListe(backupPfad: einstellungen.backupPfad, datumString: tag.datumString)
            dateibaum = DateiEintrag.baum(aus: liste)
        } catch {
            fehler = error.localizedDescription
        }
        istLaden = false
    }

    func backupStarten() async {
        backupLaeuft = true; statusMeldung = "Backup wird gestartet…"; fehler = nil
        do {
            let ausgabe = try await sshClient.backupStarten(scriptPfad: einstellungen.scriptPfad)
            statusMeldung = ausgabe.isEmpty ? "Backup abgeschlossen." : ausgabe
            await backupTageLaden()
        } catch {
            fehler = error.localizedDescription
            statusMeldung = ""
        }
        backupLaeuft = false
    }

    func piVerbindungTesten() async -> String {
        do { return try await sshClient.verbindungTesten() }
        catch { return "Fehler: \(error.localizedDescription)" }
    }

    // MARK: - Wiederherstellen

    func wiederherstellen(eintraege: [DateiEintrag]) async {
        guard let tag = ausgewaehlterTag else { fehler = "Kein Backup-Tag ausgewählt."; return }
        guard einstellungen.fritzIstKonfiguriert else { fehler = "Fritz!Box-Einstellungen unvollständig."; return }
        istLaden = true; fehler = nil
        let client = FTPSRestoreClient(einstellungen: einstellungen)
        var erfolgreich = 0; var fehlgeschlagen = 0
        for eintrag in eintraege where !eintrag.istOrdner {
            statusMeldung = "Stelle wieder her: \(eintrag.name)…"
            do {
                let daten = try await sshClient.dateiInhalt(
                    backupPfad: einstellungen.backupPfad,
                    datumString: tag.datumString,
                    relativerPfad: eintrag.pfad
                )
                try await client.dateiHochladen(relativerPfad: eintrag.pfad, daten: daten)
                erfolgreich += 1
            } catch { fehlgeschlagen += 1 }
        }
        statusMeldung = "\(erfolgreich) Datei(en) wiederhergestellt, \(fehlgeschlagen) fehlgeschlagen."
        istLaden = false
    }

    func fritzVerbindungTesten() async -> String {
        let client = FTPSRestoreClient(einstellungen: einstellungen)
        do { return try await client.verbindungTesten() }
        catch { return "Fehler: \(error.localizedDescription)" }
    }

    func einstellungenSpeichern() {
        einstellungen.speichern()
    }
}
