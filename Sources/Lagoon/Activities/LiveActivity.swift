import SwiftUI

/// Actividad en vivo breve (sección 2 del prototipo).
/// Las de estado continuo usan las alas; las que piden atención bajan en bloque.
enum LiveActivity: Equatable {
    case songChange(trackID: String)
    case chargerConnected
    case chargerDisconnected
    case lowBattery
    case airPodsConnected(BluetoothDevice)
    case timerFinished(TimerFinish)
    case volume
    case brightness
    case upcomingEvent(CalendarEvent)
    case reminderDue(ReminderItem)
    case copied(ClipKind)
    case traySaved
    case welcome

    enum Style { case wing, block }

    var style: Style {
        switch self {
        case .chargerConnected, .chargerDisconnected, .copied, .traySaved: return .wing
        default: return .block
        }
    }

    /// Identidad para las transiciones de contenido.
    var key: String {
        switch self {
        case let .songChange(id): return "song-\(id)"
        case .chargerConnected: return "charger-on"
        case .chargerDisconnected: return "charger-off"
        case .lowBattery: return "low-battery"
        case let .airPodsConnected(d): return "airpods-\(d.id)"
        case let .timerFinished(f): return "timer-finished-\(f.kind)"
        case .volume: return "volume"
        case .brightness: return "brightness"
        case let .upcomingEvent(e): return "event-\(e.id)"
        case let .reminderDue(r): return "reminder-\(r.id)"
        case let .copied(k): return "copied-\(k.rawValue)"
        case .traySaved: return "tray-saved"
        case .welcome: return "welcome"
        }
    }

    var isHUD: Bool { self == .volume || self == .brightness }

    /// Se queda hasta que el usuario actúa.
    var isSticky: Bool {
        if case .timerFinished = self { return true }
        return false
    }

    /// Tiene botones: el hover no abre el panel para no estorbar.
    var isInteractive: Bool {
        switch self {
        case .lowBattery, .timerFinished, .upcomingEvent, .reminderDue: return true
        default: return false
        }
    }

    var priority: Int {
        switch self {
        case .timerFinished: return 90
        case .volume, .brightness: return 80
        case .lowBattery: return 70
        case .upcomingEvent, .reminderDue: return 60
        case .airPodsConnected: return 50
        case .chargerConnected, .chargerDisconnected: return 40
        case .songChange: return 30
        case .traySaved, .copied: return 20
        case .welcome: return 10
        }
    }

    func duration(base: TimeInterval) -> TimeInterval? {
        switch self {
        case .timerFinished: return nil
        case .volume, .brightness: return 1.5
        case .lowBattery, .upcomingEvent, .reminderDue: return max(base, 8)
        case .welcome: return max(base, 6)
        default: return base
        }
    }

    /// Ancho de cada ala (actividades en alas).
    var wingWidth: CGFloat {
        switch self {
        case .chargerConnected, .chargerDisconnected: return 70
        default: return 60
        }
    }

    /// Ancho total del bloque (actividades en bloque).
    var blockWidth: CGFloat {
        switch self {
        case .songChange, .lowBattery, .welcome: return 400
        case .airPodsConnected, .upcomingEvent: return 440
        case .timerFinished: return 470
        case .volume, .brightness: return 320
        case .reminderDue: return 420
        default: return 400
        }
    }

    /// Alto del contenido del bloque (sin el margen superior de notch + 8 ni el inferior de 14).
    var blockContentHeight: CGFloat {
        switch self {
        case .songChange, .welcome: return 44
        case .lowBattery, .timerFinished: return 36
        case .airPodsConnected: return 46
        case .volume, .brightness: return 20
        case .upcomingEvent: return 45
        case .reminderDue: return 30
        default: return 44
        }
    }

    /// Anillo de color alrededor de la forma (carga, batería baja, timer terminado).
    var ring: Color? {
        switch self {
        case .chargerConnected: return Palette.green.opacity(0.55)
        case .lowBattery: return Palette.red.opacity(0.5)
        case .timerFinished: return Palette.orange.opacity(0.6)
        default: return nil
        }
    }

    /// Resplandor exterior.
    var glow: (color: Color, radius: CGFloat)? {
        switch self {
        case .chargerConnected: return (Palette.green.opacity(0.45), 11)
        case .timerFinished: return (Palette.orange.opacity(0.4), 13)
        default: return nil
        }
    }
}

/// Qué muestran las alas en estado continuo (sección 1).
enum WingContent: Equatable {
    /// Música: portada a la izquierda, onda a la derecha.
    case music
    /// Timer en curso (icono + tiempo).
    case timer
    /// Pomodoro corriendo (icono + etiqueta, anillo + tiempo).
    case pomodoro
    /// Cronómetro corriendo.
    case stopwatch
    /// Cargando (rayo + porcentaje + pila).
    case charging
    /// Dos actividades: portada a la izquierda, la de mayor prioridad a la derecha.
    case musicPlus(Secondary)

    enum Secondary: Equatable { case timer, pomodoro, stopwatch, charging }

    var wingWidth: CGFloat {
        switch self {
        case .music: return 50
        case .timer, .stopwatch, .charging: return 45
        case .pomodoro, .musicPlus: return 60
        }
    }
}

/// Lo que ocupa la forma negra en cada momento.
enum Presentation: Equatable {
    case idle
    case wings(WingContent)
    case activity(LiveActivity)
    case expanded
    case drop

    var key: String {
        switch self {
        case .idle: return "idle"
        case let .wings(w): return "wings-\(w)"
        case let .activity(a): return "activity-\(a.key)"
        case .expanded: return "expanded"
        case .drop: return "drop"
        }
    }
}

/// Tamaño, radio y sombra de la forma para una presentación.
struct ShapeSpec: Equatable {
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat
    var shadow: ShadowKind

    enum ShadowKind: Equatable { case none, hover, block, expanded }

    var size: CGSize { CGSize(width: width, height: height) }
}
