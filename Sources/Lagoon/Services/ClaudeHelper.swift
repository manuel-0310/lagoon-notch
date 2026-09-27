import Foundation

/// Modo ayudante: `Lagoon --claude-hook` y `Lagoon --claude-statusline`.
///
/// Claude Code ejecuta este binario en cada hook o actualización de la barra de estado. Lee el JSON
/// de la entrada estándar, lo manda por el socket a la app y termina. No crea `NSApplication` ni
/// toca la interfaz. Si Lagoon no está abierta, sale enseguida sin escribir nada, así que Claude
/// Code sigue su flujo normal.
enum ClaudeHelper {
    /// Espera máxima por una decisión de permiso (el hook se instala con un timeout algo mayor).
    static let permissionWait: TimeInterval = 120

    static func runHook() -> Never {
        signal(SIGPIPE, SIG_IGN)
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard let payload = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else { exit(0) }
        let event = payload["hook_event_name"] as? String ?? ""
        let wantsReply = event == "PermissionRequest"

        let message: [String: Any] = [
            "kind": "hook",
            "payload": payload,
            "env": environment(),
        ]
        guard let reply = send(message, waitForReply: wantsReply) else { exit(0) }
        if wantsReply, let output = permissionOutput(reply: reply, payload: payload),
           let data = try? JSONSerialization.data(withJSONObject: output) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        exit(0)
    }

    static func runStatusLine() -> Never {
        signal(SIGPIPE, SIG_IGN)
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let payload = (try? JSONSerialization.jsonObject(with: input) as? [String: Any]) ?? [:]
        _ = send(["kind": "statusline", "payload": payload, "env": environment()], waitForReply: false)

        // Se respeta la barra de estado que el usuario ya tenía.
        if let previous = ClaudeHookInstaller.previousStatusLineCommand(), !previous.isEmpty {
            let output = runShell(previous, input: input, timeout: 5)
            FileHandle.standardOutput.write(output)
            exit(0)
        }
        FileHandle.standardOutput.write(Data(defaultStatusLine(payload).utf8))
        exit(0)
    }

    // MARK: - Salida

    private static func permissionOutput(reply: [String: Any], payload: [String: Any]) -> [String: Any]? {
        var decision: [String: Any]
        switch reply["decision"] as? String {
        case "allow":
            decision = ["behavior": "allow"]
        case "always":
            decision = ["behavior": "allow"]
            if let suggestions = payload["permission_suggestions"] as? [Any], !suggestions.isEmpty {
                decision["updatedPermissions"] = suggestions
            }
        case "deny":
            decision = ["behavior": "deny", "message": "Rechazado desde Lagoon."]
        default:
            return nil
        }
        return ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
    }

    private static func defaultStatusLine(_ payload: [String: Any]) -> String {
        var parts: [String] = []
        if let model = (payload["model"] as? [String: Any])?["display_name"] as? String { parts.append(model) }
        if let context = (payload["context_window"] as? [String: Any])?["used_percentage"] as? NSNumber {
            parts.append("contexto \(context.intValue) %")
        }
        if let limits = payload["rate_limits"] as? [String: Any],
           let five = (limits["five_hour"] as? [String: Any])?["used_percentage"] as? NSNumber {
            parts.append("5 h \(five.intValue) %")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Socket (cliente)

    /// Envía el mensaje; si `waitForReply`, espera una línea de respuesta. nil si Lagoon no está abierta.
    private static func send(_ message: [String: Any], waitForReply: Bool) -> [String: Any]? {
        guard var data = try? JSONSerialization.data(withJSONObject: message),
              var address = ClaudeSocket.address(for: ClaudeSocket.path) else { return nil }
        data.append(0x0A)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        ClaudeSocket.disableSigpipe(fd)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0, ClaudeSocket.writeAll(fd, data) else { return nil }
        guard waitForReply else { return [:] }

        var buffer = Data()
        let deadline = Date().addingTimeInterval(permissionWait)
        var chunk = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let remaining = Int32(max(0, deadline.timeIntervalSinceNow) * 1000)
            let ready = poll(&poller, 1, min(remaining, 1000))
            if ready < 0 && errno != EINTR { break }
            guard ready > 0 else { continue }
            let count = read(fd, &chunk, chunk.count)
            if count <= 0 { break }
            buffer.append(contentsOf: chunk[0..<count])
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                return (try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]) ?? [:]
            }
        }
        return [:]
    }

    /// Variables útiles para volver a la terminal correcta.
    private static func environment() -> [String: String] {
        let env = ProcessInfo.processInfo.environment
        var result: [String: String] = [:]
        for key in ["TERM_PROGRAM", "__CFBundleIdentifier", "ITERM_SESSION_ID", "TERM_SESSION_ID", "TMUX"] {
            if let value = env[key] { result[key] = value }
        }
        result["ppid"] = String(getppid())
        return result
    }

    private static func runShell(_ command: String, input: Data, timeout: TimeInterval) -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return Data()
        }
        stdin.fileHandleForWriting.write(input)
        try? stdin.fileHandleForWriting.close()
        let done = DispatchSemaphore(value: 0)
        var output = Data()
        DispatchQueue.global().async {
            output = stdout.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return Data()
        }
        process.waitUntilExit()
        return output
    }
}
