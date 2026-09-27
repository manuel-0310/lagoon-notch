import AppKit
import Observation
import SwiftUI

struct FocusMode: Equatable {
    var id: String
    var name: String
    var icon: MS
    var tint: Color
}

/// Modo Concentración activo (No molestar, Trabajo, Dormir…).
///
/// macOS no tiene una API pública para leerlo. Se vigila la carpeta `~/Library/DoNotDisturb/DB`
/// con un aviso del sistema de archivos (sin sondeo) y se leen `Assertions.json` (qué modo está
/// activo) y `ModeConfigurations.json` (nombre y símbolo de cada modo). Leer esa carpeta
/// suele requerir Acceso total al disco; sin él la función queda apagada sin errores.
///
/// Limitación: los modos que se activan solos por horario no dejan rastro en esos archivos.
@Observable
final class FocusService {
    enum Access: Equatable { case unknown, granted, denied }

    var access: Access = .unknown
    var current: FocusMode?

    @ObservationIgnored weak var notch: NotchViewModel?
    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var pending: DispatchWorkItem?
    @ObservationIgnored private var started = false

    private static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")
    }

    func start() {
        guard !started else { return }
        started = true
        attach()
        // Estado inicial sin aviso.
        current = readCurrent()
    }

    /// Vuelve a intentarlo (por ejemplo, después de conceder Acceso total al disco).
    func retryIfNeeded() {
        guard started, source == nil else { return }
        attach()
        if source != nil { current = readCurrent() }
    }

    private func attach() {
        let fd = open(Self.directory.path, O_EVTONLY)
        guard fd >= 0 else {
            access = .denied
            return
        }
        // Comprobar que de verdad se puede leer (sin permiso, open() funciona pero la lectura no).
        if (try? FileManager.default.contentsOfDirectory(atPath: Self.directory.path)) == nil {
            close(fd)
            access = .denied
            return
        }
        access = .granted
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete],
                                                               queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleRead() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func scheduleRead() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func reload() {
        let next = readCurrent()
        guard next != current else { return }
        let previous = current
        current = next
        guard Prefs.bool(Prefs.showFocusChanges) else { return }
        if let next {
            notch?.post(.focusChanged(next, active: true))
        } else if let previous {
            notch?.post(.focusChanged(previous, active: false))
        }
    }

    // MARK: - Lectura

    private func readCurrent() -> FocusMode? {
        let assertionsURL = Self.directory.appendingPathComponent("Assertions.json")
        guard let data = try? Data(contentsOf: assertionsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["data"] as? [[String: Any]] else { return nil }
        var modeID: String?
        for entry in entries {
            let records = entry["storeAssertionRecords"] as? [[String: Any]] ?? []
            for record in records {
                if let details = record["assertionDetails"] as? [String: Any],
                   let id = details["assertionDetailsModeIdentifier"] as? String {
                    modeID = id
                }
            }
        }
        guard let modeID else { return nil }
        return mode(for: modeID)
    }

    private func mode(for id: String) -> FocusMode {
        var name: String?
        var symbol: String?
        var tintName: String?
        let configURL = Self.directory.appendingPathComponent("ModeConfigurations.json")
        if let data = try? Data(contentsOf: configURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let entries = json["data"] as? [[String: Any]] {
            for entry in entries {
                guard let configs = entry["modeConfigurations"] as? [String: Any],
                      let config = configs[id] as? [String: Any],
                      let mode = config["mode"] as? [String: Any] else { continue }
                name = mode["name"] as? String
                symbol = mode["symbolImageName"] as? String
                tintName = mode["tintColorName"] as? String
            }
        }
        let displayName = (name?.isEmpty == false ? name : nil) ?? Self.builtInNames.first { id.contains($0.key) }?.value
            ?? "Concentración"
        return FocusMode(id: id, name: displayName, icon: Self.icon(symbol: symbol, id: id), tint: Self.tint(tintName))
    }

    private static let builtInNames: [String: String] = [
        "mode.default": "No molestar",
        "sleep": "Dormir",
        "focus.work": "Trabajo",
        "personal": "Personal",
        "driving": "Conducción",
        "reduce-interruptions": "Menos interrupciones",
        "mindfulness": "Mindfulness",
        "reading": "Lectura",
        "fitness": "Ejercicio",
        "workout": "Ejercicio",
        "gaming": "Juegos",
    ]

    private static func icon(symbol: String?, id: String) -> MS {
        let key = (symbol ?? "") + " " + id
        let table: [(String, MS)] = [
            ("moon", .darkMode), ("bed", .bedtime), ("sleep", .bedtime),
            ("briefcase", .work), ("work", .work), ("person", .person), ("personal", .person),
            ("car", .directionsCar), ("driving", .directionsCar), ("book", .menuBook), ("reading", .menuBook),
            ("mind", .selfImprovement), ("leaf", .selfImprovement), ("gamecontroller", .sportsEsports),
            ("gaming", .sportsEsports), ("figure", .selfImprovement),
        ]
        return table.first { key.localizedCaseInsensitiveContains($0.0) }?.1 ?? .doNotDisturbOn
    }

    private static func tint(_ name: String?) -> Color {
        let name = (name ?? "").lowercased()
        if name.contains("orange") { return Palette.orange }
        if name.contains("green") || name.contains("mint") || name.contains("teal") { return Palette.green }
        if name.contains("blue") || name.contains("cyan") { return Palette.blue }
        if name.contains("pink") || name.contains("red") { return Palette.pink }
        if name.contains("yellow") { return Palette.yellow }
        return Palette.purple
    }
}
