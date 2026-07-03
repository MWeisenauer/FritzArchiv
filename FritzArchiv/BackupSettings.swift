import Foundation

struct BackupSettings: Codable {
    // Pi SSH
    var piHost: String = "192.168.178.68"
    var piBenutzer: String = "markus"
    var backupPfad: String = "/home/markus/backup"
    var scriptPfad: String = "/home/markus/backup_fritzbox.sh"
    var logPfad: String = "/home/markus/backup/backup.log"

    // Fritz!Box FTPS
    var fritzHost: String = "192.168.178.1"
    var fritzPort: Int = 21
    var fritzBenutzer: String = ""
    var fritzPasswort: String = ""
    var fritzPfad: String = "/freeCloud"
    var zertifikatIgnorieren: Bool = true

    private static let schluessel = "FritzArchiv.Einstellungen"

    static func laden() -> BackupSettings {
        guard let data = UserDefaults.standard.data(forKey: schluessel),
              let s = try? JSONDecoder().decode(BackupSettings.self, from: data) else {
            return BackupSettings()
        }
        return s
    }

    func speichern() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.schluessel)
        }
    }

    var piIstKonfiguriert: Bool { !piHost.isEmpty && !piBenutzer.isEmpty }
    var fritzIstKonfiguriert: Bool { !fritzHost.isEmpty && !fritzBenutzer.isEmpty && !fritzPasswort.isEmpty }
}
