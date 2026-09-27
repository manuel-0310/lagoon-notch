import AppKit
import Observation

struct ClaudePermissionRequest: Identifiable, Equatable {
    let id: String
    let sessionID: String
    let project: String
    let tool: String
    let summary: String
    let detail: String?
    let canAlwaysAllow: Bool
}

struct ClaudeNotice: Equatable {
    enum Kind: String { case done, waiting, permission }

    let sessionID: String
    let project: String
    let kind: Kind
    let message: String?

    var title: String {
        switch kind {
        case .done: return "Claude terminó"
        case .waiting: return "Claude te espera"
        case .permission: return "Claude pide permiso"
        }
    }
}

struct ClaudeSession: Identifiable, Equatable {
    enum State: Equatable {
        case idle, thinking, tool(String), permission, waiting, done

        var isWorking: Bool {
            switch self {
            case .thinking, .tool: return true
            default: return false
            }
        }
    }

    let id: String
    var cwd: String
    var state: State = .idle
    var started = Date()
    var updated = Date()
    var transcriptPath: String?
    var terminalBundleID: String?
    var model: String?
    var costUSD: Double?
    var contextPercent: Double?

    var project: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "Claude Code" : name
    }

    var stateLabel: String {
        switch state {
        case .idle: return "Lista"
        case .thinking: return "Pensando…"
        case let .tool(name): return ClaudeService.toolLabel(name)
        case .permission: return "Esperando permiso"
        case .waiting: return "Esperando tu respuesta"
        case .done: return "Terminó"
        }
    }
}

/// Límite de uso del plan (5 horas o semanal) según la barra de estado de Claude Code.
struct ClaudeRateLimit: Equatable {
    var usedPercent: Double
    var resetsAt: Date?
}

/// Tokens de los últimos 7 días, por día (del más antiguo al de hoy).
struct ClaudeDailyUsage: Equatable, Identifiable {
    var day: Date
    var input: Int
    var output: Int
    var cacheWrite: Int
    var cacheRead: Int
    var id: Date { day }

    /// Tokens nuevos (sin contar lecturas de caché, que son baratas y enormes).
    var total: Int { input + output + cacheWrite }
}

/// Sesiones de Claude Code, permisos pendientes y consumo.
///
/// Recibe los hooks por un socket Unix (ver `ClaudeSocket`); no hay sondeo. El consumo semanal se
/// calcula leyendo los registros de `~/.claude/projects` solo al abrir la pestaña.
@Observable
final class ClaudeService {
    var sessions: [ClaudeSession] = []
    var pending: [ClaudePermissionRequest] = []
    var fiveHour: ClaudeRateLimit?
    var sevenDay: ClaudeRateLimit?
    var weekly: [ClaudeDailyUsage] = []
    var isLoadingUsage = false
    var isConnected = ClaudeHookInstaller.isInstalled
    var lastError: String?

    @ObservationIgnored weak var notch: NotchViewModel?
    @ObservationIgnored private let server = ClaudeSocketServer()
    @ObservationIgnored private var clients: [String: ClaudeSocketServer.Client] = [:]
    @ObservationIgnored private var cleanupTimer: Timer?
    @ObservationIgnored private let usageReader = ClaudeUsageReader()
    @ObservationIgnored private var usageLoadedAt: Date?

    var isWorking: Bool { sessions.contains { $0.state.isWorking } }

    /// Texto corto para el ala derecha ("Editando", "Terminal"…).
    var wingLabel: String {
        guard let session = sessions.filter({ $0.state.isWorking }).max(by: { $0.updated < $1.updated }) else { return "" }
        if case let .tool(name) = session.state { return Self.toolLabel(name) }
        return "Pensando"
    }

    // MARK: - Ciclo de vida

    func start() {
        guard !AppEnvironment.isSnapshot else { return }
        server.onMessage = { [weak self] object, client in self?.handle(object, client: client) }
        server.onDisconnect = { [weak self] client in self?.clientDisconnected(client) }
        if !server.start() { lastError = "No se pudo abrir el socket de Lagoon." }
    }

    func stop() {
        server.stop()
    }

    func connect(statusLine: Bool = true) {
        do {
            try ClaudeHookInstaller.install(statusLine: statusLine)
            isConnected = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func disconnect() {
        do {
            try ClaudeHookInstaller.uninstall()
            isConnected = false
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Mensajes

    private func handle(_ object: [String: Any], client: ClaudeSocketServer.Client) {
        let payload = object["payload"] as? [String: Any] ?? [:]
        let env = object["env"] as? [String: String] ?? [:]
        switch object["kind"] as? String {
        case "statusline":
            handleStatusLine(payload, env: env)
            server.close(client)
        case "hook":
            handleHook(payload, env: env, client: client)
        default:
            server.close(client)
        }
    }

    private func session(for payload: [String: Any], env: [String: String]) -> Int? {
        guard let id = payload["session_id"] as? String else { return nil }
        let cwd = payload["cwd"] as? String ?? ""
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            if !cwd.isEmpty { sessions[index].cwd = cwd }
            sessions[index].updated = Date()
            if let path = payload["transcript_path"] as? String { sessions[index].transcriptPath = path }
            if let bundle = Self.terminalBundle(env) { sessions[index].terminalBundleID = bundle }
            return index
        }
        var session = ClaudeSession(id: id, cwd: cwd)
        session.transcriptPath = payload["transcript_path"] as? String
        session.terminalBundleID = Self.terminalBundle(env)
        sessions.append(session)
        scheduleCleanup()
        return sessions.count - 1
    }

    private func handleHook(_ payload: [String: Any], env: [String: String], client: ClaudeSocketServer.Client) {
        let event = payload["hook_event_name"] as? String ?? ""
        guard let index = session(for: payload, env: env) else {
            server.close(client)
            return
        }
        let sessionID = sessions[index].id
        let project = sessions[index].project

        switch event {
        case "SessionStart":
            sessions[index].state = .idle
        case "UserPromptSubmit":
            sessions[index].state = .thinking
            sessions[index].started = Date()
            dismissNotices(for: sessionID)
        case "PreToolUse":
            sessions[index].state = .tool(payload["tool_name"] as? String ?? "")
        case "PostToolUse":
            sessions[index].state = .thinking
        case "PermissionRequest":
            sessions[index].state = .permission
            guard Prefs.bool(Prefs.claudePermissions) else { break }
            let request = Self.makeRequest(payload, sessionID: sessionID, project: project)
            clients[request.id] = client
            pending.append(request)
            notch?.post(.claudePermission(request))
            return // el cliente queda abierto hasta que se responda
        case "Notification":
            switch payload["notification_type"] as? String {
            case "idle_prompt":
                sessions[index].state = .waiting
                notice(.waiting, session: sessions[index], message: payload["message"] as? String)
            case "permission_prompt":
                sessions[index].state = .permission
                if !pending.contains(where: { $0.sessionID == sessionID }) {
                    notice(.permission, session: sessions[index], message: payload["message"] as? String)
                }
            default:
                break
            }
        case "Stop":
            sessions[index].state = .done
            if Prefs.bool(Prefs.claudeShowDone) {
                notice(.done, session: sessions[index], message: payload["last_assistant_message"] as? String)
            }
        case "SessionEnd":
            sessions.remove(at: index)
            cancelPending(for: sessionID)
            dismissNotices(for: sessionID)
        default:
            break
        }
        server.close(client)
    }

    private func handleStatusLine(_ payload: [String: Any], env: [String: String]) {
        if let limits = payload["rate_limits"] as? [String: Any] {
            fiveHour = Self.rateLimit(limits["five_hour"])
            sevenDay = Self.rateLimit(limits["seven_day"])
        }
        guard let index = session(for: payload, env: env) else { return }
        if let model = (payload["model"] as? [String: Any])?["display_name"] as? String { sessions[index].model = model }
        if let cost = (payload["cost"] as? [String: Any])?["total_cost_usd"] as? NSNumber {
            sessions[index].costUSD = cost.doubleValue
        }
        if let context = (payload["context_window"] as? [String: Any])?["used_percentage"] as? NSNumber {
            sessions[index].contextPercent = context.doubleValue
        }
    }

    private func notice(_ kind: ClaudeNotice.Kind, session: ClaudeSession, message: String?) {
        // Si ya estás mirando esa terminal, no hace falta avisar.
        if let bundle = session.terminalBundleID,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundle { return }
        let trimmed = message.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { String($0.prefix(140)) }
        notch?.post(.claudeNotice(ClaudeNotice(sessionID: session.id, project: session.project,
                                               kind: kind, message: trimmed)))
    }

    private func dismissNotices(for sessionID: String) {
        notch?.dismiss {
            if case let .claudeNotice(notice) = $0 { return notice.sessionID == sessionID }
            return false
        }
    }

    // MARK: - Permisos

    enum Decision: String { case allow, always, deny, terminal }

    func respond(_ request: ClaudePermissionRequest, _ decision: Decision) {
        pending.removeAll { $0.id == request.id }
        notch?.dismiss {
            if case let .claudePermission(r) = $0 { return r.id == request.id }
            return false
        }
        if let index = sessions.firstIndex(where: { $0.id == request.sessionID }) {
            sessions[index].state = decision == .terminal ? .permission : .thinking
        }
        guard let client = clients.removeValue(forKey: request.id) else { return }
        let value = decision == .terminal ? "ask" : decision.rawValue
        server.reply(client, ["decision": value])
        if decision == .terminal { activateTerminal(sessionID: request.sessionID) }
    }

    private func clientDisconnected(_ client: ClaudeSocketServer.Client) {
        // Claude Code canceló el hook (o se respondió en la terminal).
        guard let id = clients.first(where: { $0.value === client })?.key else { return }
        clients.removeValue(forKey: id)
        pending.removeAll { $0.id == id }
        notch?.dismiss {
            if case let .claudePermission(r) = $0 { return r.id == id }
            return false
        }
    }

    private func cancelPending(for sessionID: String) {
        for request in pending where request.sessionID == sessionID {
            if let client = clients.removeValue(forKey: request.id) { server.close(client) }
        }
        pending.removeAll { $0.sessionID == sessionID }
        notch?.dismiss {
            if case let .claudePermission(r) = $0 { return r.sessionID == sessionID }
            return false
        }
    }

    // MARK: - Terminal

    func activateTerminal(sessionID: String) {
        guard let bundle = sessions.first(where: { $0.id == sessionID })?.terminalBundleID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { return }
        app.activate()
    }

    private static func terminalBundle(_ env: [String: String]) -> String? {
        if let bundle = env["__CFBundleIdentifier"], !bundle.isEmpty { return bundle }
        switch env["TERM_PROGRAM"] {
        case "Apple_Terminal": return "com.apple.Terminal"
        case "iTerm.app": return "com.googlecode.iterm2"
        case "vscode": return "com.microsoft.VSCode"
        case "WarpTerminal": return "dev.warp.Warp-Stable"
        case "ghostty": return "com.mitchellh.ghostty"
        case "WezTerm": return "com.github.wez.wezterm"
        default: return nil
        }
    }

    // MARK: - Limpieza de sesiones abandonadas

    /// Si una sesión no manda nada en 30 min (se cerró la terminal sin SessionEnd), se quita.
    /// El temporizador solo existe mientras hay sesiones.
    private func scheduleCleanup() {
        guard cleanupTimer == nil else { return }
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let cutoff = Date().addingTimeInterval(-30 * 60)
            let waiting = Set(self.pending.map(\.sessionID))
            self.sessions.removeAll { $0.updated < cutoff && !waiting.contains($0.id) }
            // Una sesión "trabajando" sin eventos en 10 min probablemente se interrumpió.
            let stale = Date().addingTimeInterval(-10 * 60)
            for index in self.sessions.indices where self.sessions[index].state.isWorking && self.sessions[index].updated < stale {
                self.sessions[index].state = .idle
            }
            if self.sessions.isEmpty {
                timer.invalidate()
                self.cleanupTimer = nil
            }
        }
    }

    // MARK: - Consumo

    func refreshUsageIfNeeded() {
        guard !AppEnvironment.isSnapshot, !isLoadingUsage else { return }
        if let usageLoadedAt, Date().timeIntervalSince(usageLoadedAt) < 60 { return }
        isLoadingUsage = true
        usageReader.readWeek { [weak self] days in
            guard let self else { return }
            self.weekly = days
            self.isLoadingUsage = false
            self.usageLoadedAt = Date()
        }
    }

    var weeklyTotal: Int { weekly.reduce(0) { $0 + $1.total } }

    // MARK: - Utilidades

    private static func rateLimit(_ value: Any?) -> ClaudeRateLimit? {
        guard let dict = value as? [String: Any],
              let used = (dict["used_percentage"] as? NSNumber)?.doubleValue else { return nil }
        let resets = (dict["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return ClaudeRateLimit(usedPercent: used, resetsAt: resets)
    }

    static func toolLabel(_ tool: String) -> String {
        switch tool {
        case "Bash", "BashOutput", "KillShell": return "Terminal"
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return "Editando"
        case "Read": return "Leyendo"
        case "Grep", "Glob", "LS": return "Buscando"
        case "WebFetch", "WebSearch": return "Web"
        case "Task", "Agent": return "Agente"
        case "TodoWrite", "TaskCreate", "TaskUpdate": return "Tareas"
        case "": return "Trabajando"
        default: return tool.hasPrefix("mcp__") ? "MCP" : tool
        }
    }

    private static func makeRequest(_ payload: [String: Any], sessionID: String, project: String) -> ClaudePermissionRequest {
        let tool = payload["tool_name"] as? String ?? "Herramienta"
        let input = payload["tool_input"] as? [String: Any] ?? [:]
        var summary = tool
        var detail = input["description"] as? String
        if let command = input["command"] as? String {
            summary = command
        } else if let path = input["file_path"] as? String ?? input["notebook_path"] as? String {
            summary = "\(toolLabel(tool)) \(URL(fileURLWithPath: path).lastPathComponent)"
            detail = detail ?? path
        } else if let url = input["url"] as? String {
            summary = url
        } else if let query = input["query"] as? String {
            summary = query
        } else if let pattern = input["pattern"] as? String {
            summary = pattern
        }
        summary = summary.replacingOccurrences(of: "\n", with: " ")
        let suggestions = payload["permission_suggestions"] as? [Any] ?? []
        return ClaudePermissionRequest(id: UUID().uuidString, sessionID: sessionID, project: project, tool: tool,
                                       summary: String(summary.prefix(200)), detail: detail.map { String($0.prefix(200)) },
                                       canAlwaysAllow: !suggestions.isEmpty)
    }
}

// MARK: - Lectura del consumo (registros de ~/.claude/projects)

/// Suma los tokens de los mensajes del asistente de los últimos 7 días.
/// Guarda el resultado por archivo (fecha de modificación + tamaño) para no releer lo que no cambió.
final class ClaudeUsageReader {
    private struct Entry {
        var modified: Date
        var size: Int
        /// Tokens por día (inicio del día) y por id de mensaje (Claude Code escribe varias veces el mismo mensaje).
        var messages: [String: (day: Date, input: Int, output: Int, cacheWrite: Int, cacheRead: Int)]
    }

    private var cache: [String: Entry] = [:]
    private let queue = DispatchQueue(label: "app.lagoon.claude.usage", qos: .utility)

    func readWeek(completion: @escaping ([ClaudeDailyUsage]) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let days = self.scan()
            DispatchQueue.main.async { completion(days) }
        }
    }

    private func scan() -> [ClaudeDailyUsage] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let firstDay = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles]) else { return [] }

        var seen = Set<String>()
        var totals: [Date: ClaudeDailyUsage] = [:]
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let modified = values.contentModificationDate, modified >= firstDay else { continue }
            let size = values.fileSize ?? 0
            let path = url.path
            seen.insert(path)
            if cache[path]?.modified != modified || cache[path]?.size != size {
                cache[path] = Entry(modified: modified, size: size, messages: parse(url, since: firstDay))
            }
            guard let entry = cache[path] else { continue }
            for message in entry.messages.values where message.day >= firstDay {
                var day = totals[message.day] ?? ClaudeDailyUsage(day: message.day, input: 0, output: 0, cacheWrite: 0, cacheRead: 0)
                day.input += message.input
                day.output += message.output
                day.cacheWrite += message.cacheWrite
                day.cacheRead += message.cacheRead
                totals[message.day] = day
            }
        }
        cache = cache.filter { seen.contains($0.key) }

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { return nil }
            return totals[day] ?? ClaudeDailyUsage(day: day, input: 0, output: 0, cacheWrite: 0, cacheRead: 0)
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterPlain = ISO8601DateFormatter()

    private func parse(_ url: URL, since firstDay: Date) -> [String: (day: Date, input: Int, output: Int, cacheWrite: Int, cacheRead: Int)] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [:] }
        let calendar = Calendar.current
        var result: [String: (day: Date, input: Int, output: Int, cacheWrite: Int, cacheRead: Int)] = [:]
        let usageMarker = Data("\"usage\"".utf8)
        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: 0x0A) ?? data.endIndex
            let line = data[start..<end]
            start = end < data.endIndex ? data.index(after: end) : data.endIndex
            // Filtro rápido antes de interpretar el JSON.
            guard line.range(of: usageMarker) != nil,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "assistant",
                  let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let stamp = object["timestamp"] as? String,
                  let date = Self.isoFormatter.date(from: stamp) ?? Self.isoFormatterPlain.date(from: stamp),
                  date >= firstDay else { continue }
            let id = (message["id"] as? String ?? UUID().uuidString) + "|" + (object["requestId"] as? String ?? "")
            func int(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
            result[id] = (calendar.startOfDay(for: date), int("input_tokens"), int("output_tokens"),
                          int("cache_creation_input_tokens"), int("cache_read_input_tokens"))
        }
        return result
    }
}
