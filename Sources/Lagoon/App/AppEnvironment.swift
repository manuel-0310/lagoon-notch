import Foundation

/// Estado global de ejecución (modo capturas, reloj fijo para las capturas).
enum AppEnvironment {
    /// `true` cuando la app se ejecuta con `--snapshots` para renderizar las pantallas a PNG.
    static var isSnapshot = false
    /// En capturas, el reloj se fija a "lunes 27 sep 9:41:27" como en el prototipo.
    static var fixedNow: Date?

    static var now: Date { fixedNow ?? Date() }
}

extension Locale {
    static let lagoon = Locale(identifier: "es_ES")
}

enum Formatters {
    private static var cache: [String: DateFormatter] = [:]

    /// DateFormatter en español, cacheado por formato y zona horaria.
    static func formatter(_ format: String, timeZone: TimeZone = .current) -> DateFormatter {
        let key = format + "|" + timeZone.identifier
        if let f = cache[key] { return f }
        let f = DateFormatter()
        f.locale = .lagoon
        f.timeZone = timeZone
        f.dateFormat = format
        cache[key] = f
        return f
    }

    /// "9:41"
    static func time(_ date: Date, timeZone: TimeZone = .current) -> String {
        formatter("H:mm", timeZone: timeZone).string(from: date)
    }

    /// "lunes, 27 de septiembre"
    static func longDate(_ date: Date) -> String {
        formatter("EEEE, d 'de' MMMM").string(from: date)
    }

    /// "1:32" / "1:02:03"
    static func duration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    /// "24:13" (minutos:segundos, con horas si hace falta)
    static func countdown(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }

    /// "12:48,3" (cronómetro con décimas)
    static func stopwatch(_ seconds: Double) -> String {
        let tenths = Int((max(0, seconds) * 10).rounded(.down))
        let t = tenths % 10
        let s = tenths / 10
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d,%d", h, m, sec, t) }
        return String(format: "%02d:%02d,%d", m, sec, t)
    }

    /// "5 h 12 min" / "42 min"
    static func hoursMinutes(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h > 0 { return "\(h) h \(m) min" }
        return "\(m) min"
    }

    /// "2,4 MB"
    static func fileSize(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        let s = f.string(fromByteCount: bytes)
        return s.replacingOccurrences(of: ".", with: ",")
    }

    /// "hace 8 min"
    static func relative(_ date: Date, now: Date = AppEnvironment.now) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "ahora" }
        let minutes = seconds / 60
        if minutes < 60 { return "hace \(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return "hace \(hours) h" }
        return "hace \(hours / 24) d"
    }

    /// "en 12 min" / "en 1 h 5 min" / "ahora"
    static func until(_ date: Date, now: Date = AppEnvironment.now) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "ahora" }
        if minutes < 60 { return "en \(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "en \(h) h" : "en \(h) h \(m) min"
    }
}
