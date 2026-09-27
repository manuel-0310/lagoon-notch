import Foundation

/// Pestañas en las alas (3a): 4 a la izquierda, 3 a la derecha.
enum PanelTab: Int, CaseIterable, Identifiable {
    case home, music, tray, calendar, timer, clipboard, mirror

    var id: Int { rawValue }

    var icon: MS {
        switch self {
        case .home: return .home
        case .music: return .musicNote
        case .tray: return .inventory2
        case .calendar: return .calendarMonth
        case .timer: return .timer
        case .clipboard: return .contentPaste
        case .mirror: return .photoCameraFront
        }
    }

    var title: String {
        switch self {
        case .home: return "Inicio"
        case .music: return "Música"
        case .tray: return "Bandeja"
        case .calendar: return "Agenda"
        case .timer: return "Timer"
        case .clipboard: return "Portapapeles"
        case .mirror: return "Espejo"
        }
    }

    static let left: [PanelTab] = [.home, .music, .tray, .calendar]
    static let right: [PanelTab] = [.timer, .clipboard, .mirror]
}

/// Funciones sin pestaña propia: se abren tocando su widget en Inicio.
enum HomeSubpage: String {
    case clock, weather, battery, sound
}
