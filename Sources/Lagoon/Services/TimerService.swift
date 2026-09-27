import AppKit
import Observation
import SwiftUI

/// Datos del aviso "Timer terminado" (2g).
struct TimerFinish: Equatable {
    enum Kind: String { case timer, pomodoroFocus, pomodoroBreak }

    var kind: Kind
    var minutes: Int
    var nextMinutes: Int

    var title: String {
        switch kind {
        case .timer: return "Timer terminado"
        case .pomodoroFocus: return "Pomodoro terminado"
        case .pomodoroBreak: return "Descanso terminado"
        }
    }

    var subtitle: String {
        switch kind {
        case .timer: return "\(minutes) min completados"
        case .pomodoroFocus: return "Sigue un descanso de \(nextMinutes) min"
        case .pomodoroBreak: return "¿Otro pomodoro de \(nextMinutes) min?"
        }
    }

    var secondaryAction: String {
        switch kind {
        case .timer, .pomodoroFocus: return "Repetir"
        case .pomodoroBreak: return "Listo"
        }
    }

    var primaryAction: String {
        switch kind {
        case .timer: return "Listo"
        case .pomodoroFocus: return "Descanso"
        case .pomodoroBreak: return "Empezar"
        }
    }
}

struct LapRow: Identifiable {
    var id: Int { number }
    var number: Int
    var duration: TimeInterval
    var isBest: Bool
    var isWorst: Bool
}

/// Timer, Pomodoro y cronómetro. Solo guarda fechas: la interfaz calcula el tiempo
/// restante al dibujar, y un único temporizador avisa al terminar.
@Observable
final class TimerService {
    enum Mode: String, CaseIterable { case timer, stopwatch, pomodoro }
    enum CountdownKind: Equatable { case timer, pomodoro }
    enum PomodoroPhase: Equatable { case focus, shortBreak, longBreak }

    var mode: Mode = .pomodoro

    // Cuenta atrás (timer o pomodoro)
    var activeKind: CountdownKind?
    var duration: TimeInterval = 25 * 60
    var endDate: Date?
    var pausedRemaining: TimeInterval?
    var timerMinutes = 25
    var focusMinutes = 25
    var breakMinutes = 5
    var pomodoroPhase: PomodoroPhase = .focus
    var pomodoroCycle = 1
    let pomodoroCycles = 4

    // Cronómetro
    var stopwatchStart: Date?
    var stopwatchAccumulated: TimeInterval = 0
    var laps: [TimeInterval] = []

    @ObservationIgnored weak var notch: NotchViewModel?
    @ObservationIgnored private var finishTimer: Timer?

    func start() {
        timerMinutes = max(1, Prefs.int(Prefs.timerMinutes))
        focusMinutes = max(1, Prefs.int(Prefs.pomodoroFocusMinutes))
        breakMinutes = max(1, Prefs.int(Prefs.pomodoroBreakMinutes))
    }

    // MARK: - Estado

    var isCountdownRunning: Bool { endDate != nil }
    var isStopwatchRunning: Bool { stopwatchStart != nil }

    func isRunning(_ kind: CountdownKind) -> Bool { activeKind == kind && endDate != nil }

    /// Ancla para que los TimelineView cambien justo en cada segundo de la cuenta atrás.
    var tickAnchor: Date {
        guard let endDate else { return Date(timeIntervalSinceReferenceDate: 0) }
        return endDate.addingTimeInterval(-(ceil(endDate.timeIntervalSinceNow) + 1))
    }

    func remaining(at date: Date) -> TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(date)) }
        return pausedRemaining ?? duration
    }

    /// Fracción restante (el anillo se vacía).
    func progress(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return remaining(at: date) / duration
    }

    private var phaseMinutes: Int {
        switch pomodoroPhase {
        case .focus: return focusMinutes
        case .shortBreak: return breakMinutes
        case .longBreak: return max(15, breakMinutes * 3)
        }
    }

    func displayRemaining(for kind: CountdownKind, at date: Date) -> TimeInterval {
        if activeKind == kind { return remaining(at: date) }
        return TimeInterval((kind == .timer ? timerMinutes : phaseMinutes) * 60)
    }

    func displayProgress(for kind: CountdownKind, at date: Date) -> Double {
        activeKind == kind ? progress(at: date) : 1
    }

    func selectedMinutes(for kind: CountdownKind) -> Int {
        kind == .timer ? timerMinutes : focusMinutes
    }

    /// "Pomodoro 2 de 4" / "Descanso" / "Timer"
    func ringCaption(for kind: CountdownKind) -> String {
        switch kind {
        case .timer:
            return activeKind == .timer && endDate == nil && pausedRemaining != nil ? "En pausa" : "Timer"
        case .pomodoro:
            switch pomodoroPhase {
            case .focus: return "Pomodoro \(pomodoroCycle) de \(pomodoroCycles)"
            case .shortBreak: return "Descanso"
            case .longBreak: return "Descanso largo"
            }
        }
    }

    /// "Después: descanso de 5 min" / "Termina a las 10:24"
    func footnote(for kind: CountdownKind) -> String {
        switch kind {
        case .timer:
            if activeKind == .timer, let endDate { return "Termina a las \(Formatters.time(endDate))" }
            return "Elige una duración"
        case .pomodoro:
            if pomodoroPhase == .focus {
                let next = pomodoroCycle >= pomodoroCycles ? max(15, breakMinutes * 3) : breakMinutes
                return "Después: descanso de \(next) min"
            }
            return "Después: pomodoro de \(focusMinutes) min"
        }
    }

    // MARK: - Acciones de cuenta atrás

    func toggle(_ kind: CountdownKind) {
        if activeKind == kind {
            if endDate != nil { pause() } else if let paused = pausedRemaining, paused > 0 { resume() } else { begin(kind) }
        } else {
            begin(kind)
        }
    }

    func reset(_ kind: CountdownKind) {
        guard activeKind == kind || kind == .pomodoro else { return }
        if activeKind == kind {
            cancelFinishTimer()
            activeKind = nil
            endDate = nil
            pausedRemaining = nil
        }
        if kind == .pomodoro {
            pomodoroPhase = .focus
            pomodoroCycle = 1
        }
        duration = TimeInterval(selectedMinutes(for: kind) * 60)
        notch?.dismiss { if case .timerFinished = $0 { return true } else { return false } }
    }

    func selectPreset(_ minutes: Int, for kind: CountdownKind) {
        if kind == .timer {
            timerMinutes = minutes
            Prefs.defaults.set(minutes, forKey: Prefs.timerMinutes)
        } else {
            focusMinutes = minutes
            Prefs.defaults.set(minutes, forKey: Prefs.pomodoroFocusMinutes)
        }
        // Si esa cuenta atrás estaba cargada, se reinicia con la nueva duración.
        if activeKind == kind, kind == .timer || pomodoroPhase == .focus {
            let wasRunning = endDate != nil
            begin(kind)
            if !wasRunning { pause() }
        }
    }

    private func begin(_ kind: CountdownKind) {
        if activeKind != kind, kind == .pomodoro, activeKind == nil {
            pomodoroPhase = .focus
        }
        activeKind = kind
        duration = TimeInterval((kind == .timer ? timerMinutes : phaseMinutes) * 60)
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(duration)
        scheduleFinish()
        notch?.dismiss { if case .timerFinished = $0 { return true } else { return false } }
    }

    private func pause() {
        guard let endDate else { return }
        pausedRemaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
        cancelFinishTimer()
    }

    private func resume() {
        guard let paused = pausedRemaining else { return }
        endDate = Date().addingTimeInterval(paused)
        pausedRemaining = nil
        scheduleFinish()
    }

    private func scheduleFinish() {
        cancelFinishTimer()
        guard let endDate else { return }
        let timer = Timer(fire: endDate, interval: 0, repeats: false) { [weak self] _ in self?.finish() }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        finishTimer = timer
    }

    private func cancelFinishTimer() {
        finishTimer?.invalidate()
        finishTimer = nil
    }

    private func finish() {
        guard let kind = activeKind else { return }
        endDate = nil
        pausedRemaining = 0
        let info: TimerFinish
        switch kind {
        case .timer:
            info = TimerFinish(kind: .timer, minutes: timerMinutes, nextMinutes: timerMinutes)
        case .pomodoro:
            if pomodoroPhase == .focus {
                let next = pomodoroCycle >= pomodoroCycles ? max(15, breakMinutes * 3) : breakMinutes
                info = TimerFinish(kind: .pomodoroFocus, minutes: focusMinutes, nextMinutes: next)
            } else {
                info = TimerFinish(kind: .pomodoroBreak, minutes: phaseMinutes, nextMinutes: focusMinutes)
            }
        }
        if Prefs.bool(Prefs.timerSound) { NSSound(named: "Glass")?.play() }
        notch?.post(.timerFinished(info))
    }

    /// Botones del aviso "Timer terminado".
    func handleFinish(_ finish: TimerFinish, primary: Bool) {
        notch?.dismiss { if case .timerFinished = $0 { return true } else { return false } }
        switch (finish.kind, primary) {
        case (.timer, true):
            activeKind = nil
            pausedRemaining = nil
        case (.timer, false):
            begin(.timer)
        case (.pomodoroFocus, true):
            pomodoroPhase = pomodoroCycle >= pomodoroCycles ? .longBreak : .shortBreak
            begin(.pomodoro)
        case (.pomodoroFocus, false):
            pomodoroPhase = .focus
            begin(.pomodoro)
        case (.pomodoroBreak, true):
            pomodoroCycle = pomodoroCycle >= pomodoroCycles ? 1 : pomodoroCycle + 1
            pomodoroPhase = .focus
            begin(.pomodoro)
        case (.pomodoroBreak, false):
            pomodoroCycle = pomodoroCycle >= pomodoroCycles ? 1 : pomodoroCycle + 1
            pomodoroPhase = .focus
            activeKind = nil
            pausedRemaining = nil
        }
    }

    // MARK: - Cronómetro

    func stopwatchElapsed(at date: Date) -> TimeInterval {
        stopwatchAccumulated + (stopwatchStart.map { date.timeIntervalSince($0) } ?? 0)
    }

    func toggleStopwatch() {
        if let start = stopwatchStart {
            stopwatchAccumulated += Date().timeIntervalSince(start)
            stopwatchStart = nil
        } else {
            stopwatchStart = Date()
        }
    }

    func lap() {
        let total = stopwatchElapsed(at: Date())
        let previous = laps.reduce(0, +)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            laps.append(total - previous)
        }
    }

    func resetStopwatch() {
        stopwatchStart = nil
        stopwatchAccumulated = 0
        laps = []
    }

    /// "Vuelta 4" mientras corre, "En pausa" o "Cronómetro".
    var stopwatchCaption: String {
        if isStopwatchRunning { return "Vuelta \(laps.count + 1)" }
        return stopwatchAccumulated > 0 ? "En pausa" : "Cronómetro"
    }

    /// "Mejor vuelta 04:04,4" / "Pulsa ▶ para empezar"
    var stopwatchFootnote: String {
        if let best = laps.min(), laps.count > 1 { return "Mejor vuelta \(Formatters.stopwatch(best))" }
        if let last = laps.last { return "Última vuelta \(Formatters.stopwatch(last))" }
        if isStopwatchRunning { return "Marca vueltas con la bandera" }
        return stopwatchAccumulated > 0 ? "Pulsa ▶ para seguir" : "Pulsa ▶ para empezar"
    }

    /// Vueltas más recientes primero; la mejor en verde y la peor en rojo.
    var lapRows: [LapRow] {
        let best = laps.count > 1 ? laps.min() : nil
        let worst = laps.count > 1 ? laps.max() : nil
        return laps.enumerated().reversed().map { index, duration in
            LapRow(number: index + 1, duration: duration, isBest: duration == best, isWorst: duration == worst)
        }
    }
}
