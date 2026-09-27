import AppKit
import SwiftUI

/// Datos de ejemplo idénticos a los del prototipo (solo para las capturas).
enum MockData {
    /// Lunes 27 de septiembre, 9:41:27 (Madrid).
    static var now: Date {
        var components = DateComponents()
        components.year = 2021
        components.month = 9
        components.day = 27
        components.hour = 9
        components.minute = 41
        components.second = 27
        components.timeZone = TimeZone(identifier: "Europe/Madrid")
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }

    static func at(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
    }

    static let airPods = BluetoothDevice(id: "aa:bb", name: "AirPods Pro de Ana", kind: .headphones,
                                         main: nil, left: 82, right: 80, caseLevel: 64)

    static var designReview: CalendarEvent {
        CalendarEvent(id: "design", identifier: "design", title: "Revisión de diseño",
                      start: now.addingTimeInterval(12 * 60), end: at(10, 30), isAllDay: false,
                      color: Palette.blue, location: nil,
                      meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"), meetingService: "Google Meet")
    }

    static var reminders: [ReminderItem] {
        [
            ReminderItem(id: "r1", title: "Enviar el informe trimestral", due: at(11, 0), hasTime: true, isCompleted: false),
            ReminderItem(id: "r2", title: "Comprar café", due: now, hasTime: false, isCompleted: false),
            ReminderItem(id: "r3", title: "Llamar al dentista", due: at(17, 30), hasTime: true, isCompleted: false),
            ReminderItem(id: "r4", title: "Revisar pull request", due: now, hasTime: false, isCompleted: true),
        ]
    }

    static func runTimer(_ app: AppState, kind: TimerService.CountdownKind, remaining: TimeInterval) {
        let timers = app.timers
        timers.mode = kind == .pomodoro ? .pomodoro : .timer
        timers.activeKind = kind
        timers.duration = 25 * 60
        timers.endDate = Date().addingTimeInterval(remaining + 0.5)
        timers.pomodoroCycle = 2
    }

    // MARK: - Funciones nuevas

    static var claudeRequest: ClaudePermissionRequest {
        ClaudePermissionRequest(id: "req-1", sessionID: "s1", project: "lagoon-notch", tool: "Bash",
                                summary: "swift build -c release", detail: "Compilar en modo release",
                                canAlwaysAllow: true)
    }

    static func claudeSessions(_ app: AppState) {
        let claude = app.claude
        claude.isConnected = true
        var main = ClaudeSession(id: "s1", cwd: "/Users/ana/lagoon-notch")
        main.state = .tool("Edit")
        main.updated = now.addingTimeInterval(-20)
        main.model = "Opus"
        main.costUSD = 1.84
        main.contextPercent = 42
        var other = ClaudeSession(id: "s2", cwd: "/Users/ana/web")
        other.state = .done
        other.updated = now.addingTimeInterval(-9 * 60)
        claude.sessions = [main, other]
        claude.fiveHour = ClaudeRateLimit(usedPercent: 38, resetsAt: at(13, 0))
        claude.sevenDay = ClaudeRateLimit(usedPercent: 61, resetsAt: now.addingTimeInterval(3 * 86_400))
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let totals = [820_000, 1_450_000, 300_000, 0, 2_100_000, 960_000, 1_240_000]
        claude.weekly = totals.enumerated().map { offset, total in
            let day = calendar.date(byAdding: .day, value: offset - 6, to: today) ?? today
            return ClaudeDailyUsage(day: day, input: total / 10, output: total / 5, cacheWrite: total - total / 10 - total / 5,
                                    cacheRead: total * 8)
        }
    }

    static func shortcuts(_ app: AppState) {
        app.shortcuts.favorites = ["Modo estudio", "Enviar ETA a casa", "Texto de la captura"]
        app.shortcuts.apps = [
            FavoriteApp(path: "/System/Applications/Notes.app", name: "Notas"),
            FavoriteApp(path: "/System/Applications/Calculator.app", name: "Calculadora"),
            FavoriteApp(path: "/Applications/Safari.app", name: "Safari"),
        ]
    }

    static func system(_ app: AppState) {
        let system = app.system
        let wave: (Double, Double, Int) -> [Double] = { base, amplitude, seed in
            (0..<SystemMonitorService.historyLength).map { i in
                max(0, base + amplitude * sin(Double(i + seed) / 5) + amplitude * 0.4 * cos(Double(i * 3 + seed) / 7))
            }
        }
        system.cpuHistory = wave(0.24, 0.12, 0)
        system.cpu = system.cpuHistory.last ?? 0.23
        system.coreCount = 10
        system.memoryTotal = 16 * 1_073_741_824
        system.memoryUsed = UInt64(11.2 * 1_073_741_824)
        system.memoryHistory = wave(0.7, 0.03, 4)
        system.gpu = 0.12
        system.gpuHistory = wave(0.12, 0.08, 9)
        system.networkHistory = wave(900_000, 600_000, 2)
        system.networkDown = 1_240_000
        system.networkUp = 86_000
        system.diskTotal = 994_000_000_000
        system.diskFree = 215_000_000_000
        system.diskRead = 2_300_000
        system.diskWrite = 820_000
        system.temperature = 54
        system.thermalState = .nominal
    }

    static func makeState() -> AppState {
        let app = AppState(geometry: .preview)

        // Música
        app.music.track = Track(id: "mock", title: "Nuevo amanecer", artist: "Clara Río", album: "Mareas",
                                duration: 220, source: .music)
        app.music.isPlaying = true
        app.music.positionAnchor = 92
        app.music.anchorDate = Date()

        // Batería
        app.battery.hasBattery = true
        app.battery.level = 82
        app.battery.isCharging = true
        app.battery.isPluggedIn = true
        app.battery.minutesToFull = 38
        app.battery.adapterWatts = 70

        // Dispositivos
        app.bluetooth.macName = "MacBook Pro"
        app.bluetooth.devices = [
            airPods,
            BluetoothDevice(id: "mouse", name: "Magic Mouse", kind: .mouse, main: 45),
            BluetoothDevice(id: "keyboard", name: "Magic Keyboard", kind: .keyboard, main: 18),
        ]

        // Audio
        app.audio.volume = 0.64
        app.audio.brightness = 0.40
        app.audio.brightnessAvailable = true
        app.audio.outputs = [
            AudioOutput(id: 1, name: "AirPods Pro de Ana", kind: .headphones),
            AudioOutput(id: 2, name: "Altavoces del MacBook", kind: .builtIn),
            AudioOutput(id: 3, name: "Salón", kind: .speaker),
        ]
        app.audio.currentOutputID = 1

        // Agenda
        app.calendar.eventsAccess = .granted
        app.calendar.remindersAccess = .granted
        app.calendar.todayEvents = [
            designReview,
            CalendarEvent(id: "lunch", identifier: "lunch", title: "Almuerzo con Leo", start: at(12, 30),
                          end: at(13, 30), isAllDay: false, color: Palette.greenDot),
            CalendarEvent(id: "class", identifier: "class", title: "Clase de Estadística", start: at(16, 0),
                          end: at(17, 30), isAllDay: false, color: Palette.orangeDot),
        ]
        app.calendar.reminders = reminders

        // Clima
        app.weather.cityName = "Madrid"
        app.weather.state = .loaded
        app.weather.current = WeatherNow(temperature: 18, code: 2, isDay: true, high: 22, low: 12)
        app.weather.hours = [
            HourForecast(label: "Ahora", temperature: 18, code: 2, isDay: true),
            HourForecast(label: "11", temperature: 20, code: 0, isDay: true),
            HourForecast(label: "12", temperature: 21, code: 0, isDay: true),
            HourForecast(label: "13", temperature: 22, code: 2, isDay: true),
            HourForecast(label: "14", temperature: 21, code: 3, isDay: true),
            HourForecast(label: "15", temperature: 19, code: 61, isDay: true),
        ]
        app.weather.updatedAt = now.addingTimeInterval(-5 * 60)

        // Portapapeles
        var items: [ClipItem] = [
            ClipItem(kind: .link, title: "https://lagoon.app/descargar", text: "https://lagoon.app/descargar",
                     date: now.addingTimeInterval(-60), pinned: true),
            ClipItem(kind: .text, title: "Nos vemos a las 10 en la sala 3B", text: "Nos vemos a las 10 en la sala 3B",
                     date: now.addingTimeInterval(-8 * 60)),
            ClipItem(kind: .color, title: "#1F8FA0", text: "#1F8FA0", date: now.addingTimeInterval(-15 * 60)),
            ClipItem(kind: .image, title: "Captura 2026-09-27 a las 9.12", date: now.addingTimeInterval(-25 * 60)),
        ]
        for i in 0..<20 {
            items.append(ClipItem(kind: .text, title: "Elemento \(i)", text: "Elemento \(i)",
                                  date: now.addingTimeInterval(TimeInterval(-3600 - i * 60))))
        }
        app.clipboard.items = items
        app.clipboard.selectedID = items.first?.id

        // Bandeja
        app.tray.items = [
            TrayItem(url: URL(fileURLWithPath: "/tmp/Propuesta.pdf"), name: "Propuesta.pdf", size: 2_400_000, added: now),
            TrayItem(url: URL(fileURLWithPath: "/tmp/foto-01.heic"), name: "foto-01.heic", size: 3_100_000, added: now),
            TrayItem(url: URL(fileURLWithPath: "/tmp/Contrato.docx"), name: "Contrato.docx", size: 88_000, added: now),
        ]
        app.tray.expiresAt = now.addingTimeInterval(58 * 60)

        // Timer (Pomodoro 2 de 4)
        app.timers.mode = .pomodoro
        app.timers.pomodoroCycle = 2
        app.timers.focusMinutes = 25
        app.timers.breakMinutes = 5

        app.camera.authorization = .authorized
        return app
    }
}
