import Foundation

/// Conecta Lagoon con Claude Code editando `~/.claude/settings.json`:
/// agrega hooks que llaman a `Lagoon --claude-hook` y la barra de estado `Lagoon --claude-statusline`.
///
/// Antes de escribir guarda una copia (`settings.json.lagoon-backup`). Desconectar quita solo las
/// entradas de Lagoon y devuelve la barra de estado que hubiera antes.
enum ClaudeHookInstaller {
    enum Failure: LocalizedError {
        case unreadable, unwritable

        var errorDescription: String? {
            switch self {
            case .unreadable: return "No se pudo leer ~/.claude/settings.json (¿JSON con errores?)."
            case .unwritable: return "No se pudo escribir ~/.claude/settings.json."
            }
        }
    }

    static let hookFlag = "--claude-hook"
    static let statusFlag = "--claude-statusline"

    /// Eventos que se escuchan. `PermissionRequest` es el único que espera respuesta; los demás
    /// son asíncronos para no retrasar a Claude.
    static let events: [(name: String, timeout: Int, async: Bool)] = [
        ("SessionStart", 10, true),
        ("UserPromptSubmit", 10, true),
        ("PreToolUse", 10, true),
        ("PostToolUse", 10, true),
        ("PermissionRequest", Int(ClaudeHelper.permissionWait) + 10, false),
        ("Notification", 10, true),
        ("Stop", 10, true),
        ("SessionEnd", 5, true),
    ]

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    private static var previousStatusLineURL: URL {
        ClaudeSocket.directory.appendingPathComponent("claude-statusline-previous.txt")
    }

    /// Ruta del ejecutable entre comillas simples (sirve con espacios en la ruta).
    private static var executable: String {
        let path = Bundle.main.executablePath ?? "/Applications/Lagoon.app/Contents/MacOS/Lagoon"
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Estado

    static var isInstalled: Bool {
        guard let data = try? Data(contentsOf: settingsURL),
              let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains(hookFlag)
    }

    static var claudeInstalled: Bool {
        FileManager.default.fileExists(atPath: settingsURL.deletingLastPathComponent().path)
    }

    static func previousStatusLineCommand() -> String? {
        try? String(contentsOf: previousStatusLineURL, encoding: .utf8)
    }

    // MARK: - Instalar / desinstalar

    static func install(statusLine: Bool) throws {
        var settings = try readSettings()
        backup()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        removeOurHooks(from: &hooks)
        for event in events {
            var groups = hooks[event.name] as? [Any] ?? []
            var hook: [String: Any] = ["type": "command", "command": "\(executable) \(hookFlag)", "timeout": event.timeout]
            if event.async { hook["async"] = true }
            if event.name == "PermissionRequest" { hook["statusMessage"] = "Esperando respuesta en Lagoon…" }
            groups.append(["hooks": [hook]])
            hooks[event.name] = groups
        }
        settings["hooks"] = hooks

        if statusLine {
            let current = settings["statusLine"] as? [String: Any]
            let currentCommand = current?["command"] as? String ?? ""
            if !currentCommand.isEmpty, !currentCommand.contains(statusFlag) {
                try? FileManager.default.createDirectory(at: ClaudeSocket.directory, withIntermediateDirectories: true)
                try? currentCommand.write(to: previousStatusLineURL, atomically: true, encoding: .utf8)
            }
            var line = current ?? [:]
            line["type"] = "command"
            line["command"] = "\(executable) \(statusFlag)"
            settings["statusLine"] = line
        }
        try writeSettings(settings)
    }

    static func uninstall() throws {
        var settings = try readSettings()
        backup()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        removeOurHooks(from: &hooks)
        settings["hooks"] = hooks.isEmpty ? nil : hooks

        if let line = settings["statusLine"] as? [String: Any],
           (line["command"] as? String)?.contains(statusFlag) == true {
            if let previous = previousStatusLineCommand(), !previous.isEmpty {
                var restored = line
                restored["command"] = previous
                settings["statusLine"] = restored
            } else {
                settings["statusLine"] = nil
            }
            try? FileManager.default.removeItem(at: previousStatusLineURL)
        }
        try writeSettings(settings)
    }

    private static func removeOurHooks(from hooks: inout [String: Any]) {
        for (event, value) in hooks {
            guard var groups = value as? [Any] else { continue }
            groups = groups.compactMap { group -> Any? in
                guard var dict = group as? [String: Any], var inner = dict["hooks"] as? [Any] else { return group }
                inner.removeAll { (($0 as? [String: Any])?["command"] as? String)?.contains(hookFlag) == true }
                if inner.isEmpty { return nil }
                dict["hooks"] = inner
                return dict
            }
            hooks[event] = groups.isEmpty ? nil : groups
        }
    }

    // MARK: - Archivo

    private static func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        guard let data = try? Data(contentsOf: settingsURL) else { throw Failure.unreadable }
        if data.isEmpty { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unreadable
        }
        return object
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        do {
            try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: settings,
                                                  options: [.prettyPrinted, .withoutEscapingSlashes])
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            throw Failure.unwritable
        }
    }

    private static func backup() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: settingsURL.path) else { return }
        let backupURL = settingsURL.deletingLastPathComponent().appendingPathComponent("settings.json.lagoon-backup")
        try? fm.removeItem(at: backupURL)
        try? fm.copyItem(at: settingsURL, to: backupURL)
    }
}
