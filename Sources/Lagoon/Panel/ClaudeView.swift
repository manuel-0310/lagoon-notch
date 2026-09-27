import SwiftUI

/// Pestaña Claude Code: sesiones activas, permisos pendientes y consumo.
struct ClaudeView: View {
    @Environment(AppState.self) var app

    var body: some View {
        let claude = app.claude
        Group {
            if !claude.isConnected {
                EmptyStateContent(icon: .smartToy, title: "Conecta Claude Code",
                                  message: "Lagoon añade unos hooks a ~/.claude/settings.json (con copia de seguridad) para ver qué hace cada sesión, aprobar permisos y ver tu consumo.") {
                    VStack(spacing: 6) {
                        PillButton(title: "Conectar", icon: .smartToy, style: .filled(Palette.claude, text: .black)) {
                            claude.connect()
                        }
                        if let error = claude.lastError {
                            Text(error).lagoonFont(11).foregroundStyle(Palette.red)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    ClaudeSessionsColumn()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .stagger(1)
                    ClaudeUsageColumn()
                        .frame(width: 210)
                        .stagger(2)
                }
            }
        }
        .onAppear { claude.refreshUsageIfNeeded() }
    }
}

// MARK: - Sesiones y permisos

struct ClaudeSessionsColumn: View {
    @Environment(AppState.self) var app

    var body: some View {
        let claude = app.claude
        VStack(alignment: .leading, spacing: 8) {
            Text("SESIONES").sectionLabel()
            if claude.sessions.isEmpty && claude.pending.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ninguna sesión abierta").lagoonFont(13, .semibold)
                    Text("Abre `claude` en una terminal y aparecerá aquí.")
                        .lagoonFont(11)
                        .foregroundStyle(Palette.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 10, radius: 12)
            } else {
                LagoonScrollView {
                    VStack(spacing: 6) {
                        ForEach(claude.pending) { request in
                            ClaudePendingRow(request: request)
                        }
                        ForEach(claude.sessions.sorted { $0.updated > $1.updated }) { session in
                            ClaudeSessionRow(session: session)
                        }
                    }
                }
            }
        }
    }
}

struct ClaudePendingRow: View {
    @Environment(AppState.self) var app
    let request: ClaudePermissionRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Icon(.lockOpen, size: 13, color: Palette.claude)
                Text("\(request.project) · \(request.tool)")
                    .lagoonFont(11, .semibold)
                    .foregroundStyle(Palette.claude)
                    .lineLimit(1)
            }
            Text(request.summary)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
            HStack(spacing: 6) {
                PillButton(title: "Terminal") { app.claude.respond(request, .terminal) }
                Spacer(minLength: 0)
                PillButton(title: "Rechazar", style: .tinted(Palette.red)) { app.claude.respond(request, .deny) }
                if request.canAlwaysAllow {
                    PillButton(title: "Siempre") { app.claude.respond(request, .always) }
                        .help("Permitir y no volver a preguntar por esto")
                }
                PillButton(title: "Permitir", style: .filled(Palette.claude, text: .black)) {
                    app.claude.respond(request, .allow)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.claude.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.claude.opacity(0.35), lineWidth: 1))
    }
}

struct ClaudeSessionRow: View {
    @Environment(AppState.self) var app
    let session: ClaudeSession

    var body: some View {
        Button { app.claude.activateTerminal(sessionID: session.id) } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(color.opacity(0.18))
                    if session.state.isWorking {
                        ClaudeSpinner(size: 15)
                    } else {
                        Icon(icon, size: 15, color: color)
                    }
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.project).lagoonFont(12.5, .semibold).lineLimit(1)
                    Text(session.stateLabel)
                        .lagoonFont(11)
                        .foregroundStyle(color)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    if let context = session.contextPercent {
                        Text("\(Int(context.rounded())) % contexto")
                            .lagoonFont(10.5)
                            .foregroundStyle(Palette.secondary)
                    }
                    TimelineView(.everyMinute) { context in
                        Text(Formatters.relative(session.updated, now: context.date))
                            .lagoonFont(10.5)
                            .foregroundStyle(Color.white(0.4))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.card))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressableStyle())
        .help("Ir a la terminal")
    }

    private var color: Color {
        switch session.state {
        case .thinking, .tool: return Palette.claude
        case .permission, .waiting: return Palette.orange
        case .done: return Palette.green
        case .idle: return Palette.secondary
        }
    }

    private var icon: MS {
        switch session.state {
        case .permission: return .lockOpen
        case .waiting: return .pending
        case .done: return .doneAll
        default: return .terminal
        }
    }
}

// MARK: - Consumo

struct ClaudeUsageColumn: View {
    @Environment(AppState.self) var app

    var body: some View {
        let claude = app.claude
        let current = claude.sessions.max { $0.updated < $1.updated }
        VStack(alignment: .leading, spacing: 8) {
            Text("CONSUMO").sectionLabel()
            VStack(alignment: .leading, spacing: 8) {
                if let current, current.costUSD != nil || current.contextPercent != nil {
                    HStack {
                        Text("Sesión").lagoonFont(11).foregroundStyle(Palette.secondary)
                        Spacer(minLength: 0)
                        if let cost = current.costUSD {
                            Text(String(format: "US$ %.2f", cost).replacingOccurrences(of: ".", with: ","))
                                .lagoonFont(12, .semibold)
                                .monospacedDigit()
                        }
                    }
                }
                LimitRow(label: "5 horas", limit: claude.fiveHour)
                LimitRow(label: "Semana", limit: claude.sevenDay)
                if claude.fiveHour == nil && claude.sevenDay == nil {
                    Text("Los límites del plan aparecen tras el primer mensaje (planes Pro y Max).")
                        .lagoonFont(10)
                        .foregroundStyle(Color.white(0.4))
                        .fixedSize(horizontal: false, vertical: true)
                }
                WeeklyTokensChart(days: claude.weekly, total: claude.weeklyTotal, loading: claude.isLoadingUsage)
            }
            .card(padding: 10, radius: 12)
        }
    }
}

struct LimitRow: View {
    let label: String
    let limit: ClaudeRateLimit?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).lagoonFont(11).foregroundStyle(Palette.secondary)
                Spacer(minLength: 0)
                Text(limit.map { "\(Int($0.usedPercent.rounded())) %" } ?? "—")
                    .lagoonFont(12, .semibold)
                    .monospacedDigit()
            }
            ProgressBar(value: (limit?.usedPercent ?? 0) / 100, color: tint, track: .white(0.12), height: 4)
            if let resets = limit?.resetsAt {
                Text("Se reinicia " + Self.resetText(resets))
                    .lagoonFont(9.5)
                    .foregroundStyle(Color.white(0.4))
            }
        }
    }

    private var tint: Color {
        let used = limit?.usedPercent ?? 0
        if used >= 90 { return Palette.red }
        if used >= 70 { return Palette.orange }
        return Palette.claude
    }

    static func resetText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "a las " + Formatters.time(date) }
        if calendar.isDateInTomorrow(date) { return "mañana a las " + Formatters.time(date) }
        return Formatters.formatter("EEEE H:mm").string(from: date)
    }
}

/// Barras de tokens de los últimos 7 días.
struct WeeklyTokensChart: View {
    let days: [ClaudeDailyUsage]
    let total: Int
    let loading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Tokens, 7 días").lagoonFont(11).foregroundStyle(Palette.secondary)
                Spacer(minLength: 0)
                Text(loading && days.isEmpty ? "…" : Self.compact(total))
                    .lagoonFont(12, .semibold)
                    .monospacedDigit()
            }
            let top = max(1, days.map(\.total).max() ?? 1)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(days) { day in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Calendar.current.isDateInToday(day.day) ? Palette.claude : Palette.claude.opacity(0.45))
                            .frame(height: max(2, 22 * CGFloat(day.total) / CGFloat(top)))
                        Text(Formatters.formatter("EEEEE").string(from: day.day).uppercased())
                            .lagoonFont(8.5)
                            .foregroundStyle(Color.white(0.4))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 34, alignment: .bottom)
        }
    }

    /// "1,2 M" / "830 k"
    static func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1f M", Double(value) / 1_000_000).replacingOccurrences(of: ".", with: ",")
        case 1_000...: return "\(value / 1_000) k"
        default: return "\(value)"
        }
    }
}
