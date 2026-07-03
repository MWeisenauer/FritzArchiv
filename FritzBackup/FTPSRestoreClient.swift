import Foundation

enum FTPSRestoreFehler: LocalizedError {
    case verbindungFehlgeschlagen(String)
    case anmeldungFehlgeschlagen
    case tlsFehler
    case uebertragungFehlgeschlagen(String)
    case ungueltigeAntwort(String)
    case nichtVerbunden

    var errorDescription: String? {
        switch self {
        case .verbindungFehlgeschlagen(let m): return "FTPS-Verbindungsfehler: \(m)"
        case .anmeldungFehlgeschlagen:         return "Anmeldung fehlgeschlagen"
        case .tlsFehler:                       return "TLS-Handshake fehlgeschlagen"
        case .uebertragungFehlgeschlagen(let m): return "Übertragung fehlgeschlagen: \(m)"
        case .ungueltigeAntwort(let m):        return "Ungültige Serverantwort: \(m)"
        case .nichtVerbunden:                  return "Nicht verbunden"
        }
    }
}

private final class FTPSRestoreDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    let ignorieren: Bool
    nonisolated(unsafe) var datenkanal = false
    init(ignorieren: Bool) { self.ignorieren = ignorieren }

    nonisolated func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                                completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil); return
        }
        if ignorieren || datenkanal { completionHandler(.useCredential, URLCredential(trust: trust)) }
        else { completionHandler(.performDefaultHandling, nil) }
    }
}

actor FTPSRestoreClient {
    private let host: String
    private let port: Int
    private let benutzer: String
    private let passwort: String
    private let basisPfad: String
    private let zertifikatIgnorieren: Bool

    private var controlTask: URLSessionStreamTask?
    private var urlSession: URLSession?
    private var ftpDelegate: FTPSRestoreDelegate?
    private var puffer = Data()
    private var verschluesselteDaten = false
    private var verbundenerHost = ""

    private let befehlTimeout: TimeInterval = 30
    private let leseTimeout: TimeInterval   = 60
    private let datenTimeout: TimeInterval  = 120

    init(einstellungen: BackupSettings) {
        self.host                = einstellungen.fritzHost
        self.port                = einstellungen.fritzPort
        self.benutzer            = einstellungen.fritzBenutzer
        self.passwort            = einstellungen.fritzPasswort
        self.basisPfad           = einstellungen.fritzPfad
        self.zertifikatIgnorieren = einstellungen.zertifikatIgnorieren
    }

    // MARK: - Public

    func verzeichnisListe(pfad: String = "") async throws -> [String] {
        try await verbinden()
        defer { trennen() }
        guard let t = controlTask, let session = urlSession else { throw FTPSRestoreFehler.nichtVerbunden }
        let befehl = pfad.isEmpty ? "LIST\r\n" : "LIST \(pfad)\r\n"
        var dataTask = try await datenkanalOeffnen(controlTask: t, session: session)
        try await senden(befehl, an: t)
        var resp = try await antwortLesen(von: t)
        if resp.hasPrefix("425") {
            dataTask.cancel()
            try await aufProtPUpgraden(t)
            dataTask = try await datenkanalOeffnen(controlTask: t, session: session)
            try await senden(befehl, an: t)
            resp = try await antwortLesen(von: t)
        }
        guard resp.hasPrefix("125") || resp.hasPrefix("150") else {
            dataTask.cancel(); throw FTPSRestoreFehler.uebertragungFehlgeschlagen(resp)
        }
        let roh = try await datenLesen(von: dataTask)
        _ = try? await antwortLesen(von: t)
        let listing = String(data: roh, encoding: .utf8) ?? String(data: roh, encoding: .isoLatin1) ?? ""
        var ordner: [String] = []
        for zeile in listing.components(separatedBy: "\n") {
            let z = zeile.trimmingCharacters(in: .whitespacesAndNewlines)
            guard z.hasPrefix("d") || z.hasPrefix("D") else { continue }
            let teile = z.split(separator: " ", omittingEmptySubsequences: true)
            guard teile.count >= 9 else { continue }
            let name = teile[8...].joined(separator: " ")
            if name != "." && name != ".." { ordner.append(name) }
        }
        return ordner.sorted()
    }

    func verbindungTesten() async throws -> String {
        try await verbinden()
        defer { trennen() }
        try await senden("NOOP\r\n")
        _ = try await antwortLesen()
        return "FTPS-Verbindung zu \(host) erfolgreich"
    }

    func dateiHochladen(relativerPfad: String, daten: Data) async throws {
        try await verbinden()
        defer { trennen() }
        let teile = relativerPfad.components(separatedBy: "/").dropLast()
        var aktuell = ""
        for teil in teile where !teil.isEmpty {
            aktuell += "/\(teil)"
            try? await mkd(pfad: aktuell)
        }
        try await stor(relativerPfad: relativerPfad, daten: daten)
    }

    // MARK: - Verbindung

    private func verbinden() async throws {
        let delegate = FTPSRestoreDelegate(ignorieren: zertifikatIgnorieren)
        let config   = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = befehlTimeout
        config.timeoutIntervalForResource = datenTimeout
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        ftpDelegate = delegate; urlSession = session
        puffer = Data(); verschluesselteDaten = false

        let task = session.streamTask(withHostName: host, port: port)
        task.resume()
        let banner = try await antwortLesen(von: task)
        guard banner.hasPrefix("220") else { throw FTPSRestoreFehler.verbindungFehlgeschlagen(banner) }

        try await senden("AUTH TLS\r\n", an: task)
        guard (try await antwortLesen(von: task)).hasPrefix("234") else { throw FTPSRestoreFehler.tlsFehler }
        task.startSecureConnection()

        try await senden("USER \(benutzer)\r\n", an: task)
        let userResp = try await antwortLesen(von: task)
        if userResp.hasPrefix("331") {
            try await senden("PASS \(passwort)\r\n", an: task)
            guard (try await antwortLesen(von: task)).hasPrefix("230") else { throw FTPSRestoreFehler.anmeldungFehlgeschlagen }
        } else if !userResp.hasPrefix("230") { throw FTPSRestoreFehler.anmeldungFehlgeschlagen }

        try await senden("PBSZ 0\r\n", an: task); _ = try await antwortLesen(von: task)
        let protKey = "FritzArchiv.protP_\(host)_\(port)"
        if UserDefaults.standard.bool(forKey: protKey) {
            verschluesselteDaten = true
            try await senden("PROT P\r\n", an: task)
        } else {
            try await senden("PROT C\r\n", an: task)
        }
        _ = try await antwortLesen(von: task)

        if !basisPfad.isEmpty && basisPfad != "/" {
            try await senden("CWD \(basisPfad)\r\n", an: task)
            let cwd = try await antwortLesen(von: task)
            guard cwd.hasPrefix("2") else { throw FTPSRestoreFehler.verbindungFehlgeschlagen("Pfad nicht gefunden: \(basisPfad)") }
        }
        verbundenerHost = host; controlTask = task
    }

    private func trennen() {
        controlTask?.cancel(); controlTask = nil
        urlSession?.invalidateAndCancel(); urlSession = nil
        ftpDelegate = nil; verschluesselteDaten = false; verbundenerHost = ""
    }

    // MARK: - FTP-Operationen

    private func mkd(pfad: String) async throws {
        guard let t = controlTask else { throw FTPSRestoreFehler.nichtVerbunden }
        try await senden("MKD \(pfad)\r\n", an: t)
        _ = try await antwortLesen(von: t) // 257 OK, 550 exists — beides akzeptabel
    }

    private func stor(relativerPfad: String, daten: Data) async throws {
        guard let t = controlTask, let session = urlSession else { throw FTPSRestoreFehler.nichtVerbunden }
        try await senden("TYPE I\r\n", an: t); _ = try await antwortLesen(von: t)
        var dataTask = try await datenkanalOeffnen(controlTask: t, session: session)
        try await senden("STOR \(relativerPfad)\r\n", an: t)
        var resp = try await antwortLesen(von: t)
        if resp.hasPrefix("425") {
            dataTask.cancel()
            try await aufProtPUpgraden(t)
            dataTask = try await datenkanalOeffnen(controlTask: t, session: session)
            try await senden("STOR \(relativerPfad)\r\n", an: t)
            resp = try await antwortLesen(von: t)
        }
        guard resp.hasPrefix("125") || resp.hasPrefix("150") else {
            dataTask.cancel(); throw FTPSRestoreFehler.uebertragungFehlgeschlagen(resp)
        }
        try await datenSchreiben(daten, an: dataTask)
        dataTask.closeWrite()
        if let done = try? await antwortLesen(von: t), done.hasPrefix("4") || done.hasPrefix("5") {
            throw FTPSRestoreFehler.uebertragungFehlgeschlagen(done)
        }
    }

    private func datenkanalOeffnen(controlTask: URLSessionStreamTask, session: URLSession) async throws -> URLSessionStreamTask {
        try await senden("PASV\r\n", an: controlTask)
        let resp = try await antwortLesen(von: controlTask)
        guard resp.hasPrefix("227") else { throw FTPSRestoreFehler.verbindungFehlgeschlagen("PASV: \(resp)") }
        let (_, port) = try parsePASV(resp)
        ftpDelegate?.datenkanal = verschluesselteDaten
        let dt = session.streamTask(withHostName: verbundenerHost, port: port)
        dt.resume()
        if verschluesselteDaten { dt.startSecureConnection() }
        return dt
    }

    private func aufProtPUpgraden(_ task: URLSessionStreamTask) async throws {
        verschluesselteDaten = true
        UserDefaults.standard.set(true, forKey: "FritzArchiv.protP_\(verbundenerHost)_\(port)")
        try await senden("PROT P\r\n", an: task); _ = try await antwortLesen(von: task)
    }

    // MARK: - I/O

    private func senden(_ befehl: String, an task: URLSessionStreamTask? = nil) async throws {
        let t = task ?? controlTask!
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            t.write(Data(befehl.utf8), timeout: befehlTimeout) {
                if let e = $0 { cont.resume(throwing: e) } else { cont.resume() }
            }
        }
    }

    private func datenLesen(von task: URLSessionStreamTask) async throws -> Data {
        var result = Data()
        while true {
            do {
                let (chunk, atEOF): (Data, Bool) = try await withCheckedThrowingContinuation { cont in
                    task.readData(ofMinLength: 1, maxLength: 65536, timeout: datenTimeout) { data, atEOF, error in
                        if let e = error { cont.resume(throwing: e) }
                        else { cont.resume(returning: (data ?? Data(), atEOF)) }
                    }
                }
                result.append(chunk)
                if atEOF { break }
            } catch { break }
        }
        return result
    }

    private func datenSchreiben(_ daten: Data, an task: URLSessionStreamTask) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            task.write(daten, timeout: datenTimeout) {
                if let e = $0 { cont.resume(throwing: e) } else { cont.resume() }
            }
        }
    }

    private func antwortLesen(von task: URLSessionStreamTask? = nil, timeout: TimeInterval? = nil) async throws -> String {
        let t = task ?? controlTask!
        while true {
            let zeile = try await zeileLesen(von: t, timeout: timeout)
            guard zeile.count >= 4 else { continue }
            if zeile[zeile.index(zeile.startIndex, offsetBy: 3)] == " " { return zeile }
        }
    }

    private func zeileLesen(von task: URLSessionStreamTask, timeout: TimeInterval? = nil) async throws -> String {
        let t = timeout ?? leseTimeout
        while true {
            if let r = puffer.range(of: Data("\r\n".utf8)) {
                let z = String(data: puffer[..<r.lowerBound], encoding: .utf8) ?? ""
                puffer.removeSubrange(..<r.upperBound); return z
            }
            if let r = puffer.range(of: Data("\n".utf8)) {
                var z = String(data: puffer[..<r.lowerBound], encoding: .utf8) ?? ""
                if z.hasSuffix("\r") { z.removeLast() }
                puffer.removeSubrange(..<r.upperBound); return z
            }
            let chunk: Data = try await withCheckedThrowingContinuation { cont in
                task.readData(ofMinLength: 1, maxLength: 4096, timeout: t) { data, _, error in
                    if let e = error { cont.resume(throwing: e) }
                    else { cont.resume(returning: data ?? Data()) }
                }
            }
            puffer.append(chunk)
        }
    }

    private func parsePASV(_ resp: String) throws -> (String, Int) {
        guard let o = resp.firstIndex(of: "("), let c = resp.firstIndex(of: ")") else {
            throw FTPSRestoreFehler.ungueltigeAntwort(resp)
        }
        let parts = String(resp[resp.index(after: o)..<c])
            .split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 6 else { throw FTPSRestoreFehler.ungueltigeAntwort(resp) }
        return ("\(parts[0]).\(parts[1]).\(parts[2]).\(parts[3])", parts[4] * 256 + parts[5])
    }
}
