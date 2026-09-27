import Foundation

/// Pestañas en las alas (3a): hasta 5 a cada lado del notch. El orden de los casos es el orden
/// visual de izquierda a derecha (lo usan el deslizamiento y la dirección de la transición).
enum PanelTab: Int, CaseIterable, Identifiable {
    case home, music, tray, calendar, shortcuts, timer, clipboard, mirror, system, claude

    var id: Int { rawValue }

    var icon: MS {
        switch self {
        case .home: return .home
        case .music: return .musicNote
        case .tray: return .inventory2
        case .calendar: return .calendarMonth
        case .shortcuts: return .apps
        case .timer: return .timer
        case .clipboard: return .contentPaste
        case .mirror: return .photoCameraFront
        case .system: return .memory
        case .claude: return .smartToy
        }
    }

    var title: String {
        switch self {
        case .home: return "Inicio"
        case .music: return "Música"
        case .tray: return "Bandeja"
        case .calendar: return "Agenda"
        case .shortcuts: return "Atajos"
        case .timer: return "Timer"
        case .clipboard: return "Portapapeles"
        case .mirror: return "Espejo"
        case .system: return "Sistema"
        case .claude: return "Claude Code"
        }
    }

    /// Inicio siempre está visible (es el destino por defecto).
    var canHide: Bool { self != .home }

    static let allLeft: [PanelTab] = [.home, .music, .tray, .calendar, .shortcuts]
    static let allRight: [PanelTab] = [.timer, .clipboard, .mirror, .system, .claude]

    /// Pestañas ocultas en Ajustes (identificadores separados por comas).
    static var hidden: Set<PanelTab> {
        let raw = Prefs.string(Prefs.hiddenTabs) ?? ""
        return Set(raw.split(separator: ",").compactMap { Int($0).flatMap(PanelTab.init(rawValue:)) })
    }

    static func setHidden(_ tab: PanelTab, _ hide: Bool) {
        guard tab.canHide else { return }
        var set = hidden
        if hide { set.insert(tab) } else { set.remove(tab) }
        let raw = set.map(\.rawValue).sorted().map(String.init).joined(separator: ",")
        Prefs.defaults.set(raw, forKey: Prefs.hiddenTabs)
    }

    static var left: [PanelTab] {
        let hidden = Self.hidden
        return allLeft.filter { !hidden.contains($0) }
    }

    static var right: [PanelTab] {
        let hidden = Self.hidden
        return allRight.filter { !hidden.contains($0) }
    }

    /// Pestañas visibles en orden (izquierda → derecha).
    static var visible: [PanelTab] { left + right }
}

/// Funciones sin pestaña propia: se abren tocando su widget en Inicio.
enum HomeSubpage: String {
    case clock, weather, battery, sound
}
