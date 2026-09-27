import SwiftUI

/// 4d · Timer / Pomodoro y 4e · Cronómetro.
///
/// Los tres modos comparten la misma estructura (círculo, selector, fila de píldoras y botones).
/// Al cambiar de modo se actualiza lo de dentro en su sitio en vez de reemplazar el panel entero,
/// que es lo que producía el fundido "trabado" al pasar al cronómetro.
struct TimerPanelView: View {
    @Environment(AppState.self) var app

    var body: some View {
        @Bindable var timers = app.timers
        let stopwatch = timers.mode == .stopwatch
        let kind = countdownKind
        HStack(spacing: 18) {
            TimerDial()
                .frame(width: 150, height: 150)
                .stagger(1)

            VStack(alignment: .leading, spacing: 14) {
                ModePicker(mode: $timers.mode)
                // Donde el timer tiene las duraciones, el cronómetro muestra las últimas vueltas.
                ZStack(alignment: .leading) {
                    if stopwatch {
                        LapChipsRow()
                            .transition(.opacity)
                    } else {
                        HStack(spacing: 6) {
                            ForEach([5, 15, 25, 45], id: \.self) { minutes in
                                PresetChip(minutes: minutes, selected: timers.selectedMinutes(for: kind) == minutes) {
                                    timers.selectPreset(minutes, for: kind)
                                }
                            }
                        }
                        .transition(.opacity)
                    }
                }
                HStack(spacing: 10) {
                    CircleIconButton(icon: isRunning ? .pause : .playArrow,
                                     iconSize: 24, background: Palette.orange, foreground: .black) {
                        if stopwatch { timers.toggleStopwatch() } else { timers.toggle(kind) }
                    }
                    secondaryButton
                    Text(stopwatch ? timers.stopwatchFootnote : timers.footnote(for: kind))
                        .lagoonFont(11)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .padding(.leading, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .stagger(2)
        }
    }

    private var countdownKind: TimerService.CountdownKind {
        app.timers.mode == .pomodoro ? .pomodoro : .timer
    }

    private var isRunning: Bool {
        let timers = app.timers
        return timers.mode == .stopwatch ? timers.isStopwatchRunning : timers.isRunning(countdownKind)
    }

    /// Reiniciar (timer y pomodoro); en el cronómetro, vuelta mientras corre y reiniciar si está parado.
    private var secondaryButton: some View {
        let timers = app.timers
        let stopwatch = timers.mode == .stopwatch
        let lap = stopwatch && timers.isStopwatchRunning
        let disabled = stopwatch && !lap && timers.stopwatchAccumulated == 0
        return CircleIconButton(icon: lap ? .flag : .restartAlt, iconSize: 22) {
            if lap {
                timers.lap()
            } else if stopwatch {
                withAnimation(Motion.tab) { timers.resetStopwatch() }
            } else {
                timers.reset(countdownKind)
            }
        }
        .help(lap ? "Vuelta" : "Reiniciar")
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

/// Círculo con el tiempo. En el cronómetro el anillo da una vuelta por minuto, como una manecilla.
struct TimerDial: View {
    @Environment(AppState.self) var app

    private struct Reading {
        var progress: Double
        var time: String
        var caption: String
    }

    var body: some View {
        let timers = app.timers
        let stopwatch = timers.mode == .stopwatch
        let kind: TimerService.CountdownKind = timers.mode == .pomodoro ? .pomodoro : .timer
        let running = stopwatch ? timers.isStopwatchRunning : timers.isRunning(kind)
        let anchor = stopwatch ? (timers.stopwatchStart ?? timers.tickAnchor) : timers.tickAnchor
        TimelineView(.periodic(from: anchor, by: running ? (stopwatch ? 0.1 : 1) : 3600)) { context in
            let reading = currentReading(stopwatch: stopwatch, kind: kind, at: context.date)
            ZStack {
                // Entre timer y pomodoro el anillo es el mismo; al pasar al cronómetro se funde.
                RingProgress(value: reading.progress, color: Palette.orange, lineWidth: 7)
                    .id(stopwatch)
                    .transition(.opacity)
                VStack(spacing: 0) {
                    Text(reading.time)
                        .lagoonFont(32, .semibold)
                        .tracking(-0.64)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 12)
                    Text(reading.caption)
                        .lagoonFont(11)
                        .foregroundStyle(Palette.secondary)
                }
            }
        }
    }

    private func currentReading(stopwatch: Bool, kind: TimerService.CountdownKind, at date: Date) -> Reading {
        let timers = app.timers
        if stopwatch {
            let elapsed = timers.stopwatchElapsed(at: date)
            return Reading(progress: elapsed > 0 ? elapsed.truncatingRemainder(dividingBy: 60) / 60 : 0,
                           time: Formatters.stopwatch(elapsed),
                           caption: timers.stopwatchCaption)
        }
        return Reading(progress: timers.displayProgress(for: kind, at: date),
                       time: Formatters.countdown(timers.displayRemaining(for: kind, at: date)),
                       caption: timers.ringCaption(for: kind))
    }
}

struct ModePicker: View {
    @Binding var mode: TimerService.Mode

    var body: some View {
        SegmentedPill(options: [(TimerService.Mode.timer, "Timer"),
                                (.stopwatch, "Cronómetro"),
                                (.pomodoro, "Pomodoro")],
                      selection: $mode)
    }
}

struct PresetChip: View {
    let minutes: Int
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(minutes) min")
                .lagoonFont(11.5, .semibold)
                .foregroundStyle(selected ? Palette.orange : Color.white(0.7))
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Palette.orange.opacity(0.22) : Color.white(0.08)))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressableStyle())
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

// MARK: - Cronómetro

/// Últimas vueltas, con el mismo aspecto que las píldoras de duración.
struct LapChipsRow: View {
    @Environment(AppState.self) var app

    var body: some View {
        let timers = app.timers
        HStack(spacing: 6) {
            if timers.laps.isEmpty {
                Text("Sin vueltas todavía")
                    .lagoonFont(11.5, .semibold)
                    .foregroundStyle(Color.white(0.35))
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white(0.05)))
            } else {
                ForEach(timers.lapRows.prefix(3)) { row in
                    LapChip(row: row)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
        }
    }
}

/// Vuelta como las píldoras de duración: la mejor en verde y la peor en rojo.
struct LapChip: View {
    let row: LapRow

    var body: some View {
        let color: Color? = row.isBest ? Palette.green : row.isWorst ? Palette.red : nil
        HStack(spacing: 4) {
            Text("V\(row.number)")
                .foregroundStyle(color ?? Color.white(0.45))
            Text(Formatters.stopwatch(row.duration))
                .monospacedDigit()
                .foregroundStyle(color ?? Color.white(0.7))
        }
        .lagoonFont(11.5, .semibold)
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(color?.opacity(0.18) ?? Color.white(0.08)))
    }
}
