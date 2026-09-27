import SwiftUI

/// 4d · Timer / Pomodoro y 4e · Cronómetro.
struct TimerPanelView: View {
    @Environment(AppState.self) var app

    var body: some View {
        @Bindable var timers = app.timers
        Group {
            switch timers.mode {
            case .timer, .pomodoro:
                CountdownPanel(modePicker: ModePicker(mode: $timers.mode))
            case .stopwatch:
                StopwatchPanel(modePicker: ModePicker(mode: $timers.mode))
            }
        }
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

// MARK: - Timer y Pomodoro

struct CountdownPanel: View {
    @Environment(AppState.self) var app
    let modePicker: ModePicker

    var body: some View {
        let timers = app.timers
        let kind: TimerService.CountdownKind = timers.mode == .pomodoro ? .pomodoro : .timer
        HStack(spacing: 18) {
            TimelineView(.periodic(from: timers.tickAnchor, by: timers.isRunning(kind) ? 1 : 3600)) { context in
                ZStack {
                    RingProgress(value: timers.displayProgress(for: kind, at: context.date),
                                 color: Palette.orange, lineWidth: 7)
                    VStack(spacing: 0) {
                        Text(Formatters.countdown(timers.displayRemaining(for: kind, at: context.date)))
                            .lagoonFont(32, .semibold)
                            .tracking(-0.64)
                            .monospacedDigit()
                        Text(timers.ringCaption(for: kind))
                            .lagoonFont(11)
                            .foregroundStyle(Palette.secondary)
                    }
                }
                .frame(width: 150, height: 150)
            }
            .stagger(1)

            VStack(alignment: .leading, spacing: 14) {
                modePicker
                HStack(spacing: 6) {
                    ForEach([5, 15, 25, 45], id: \.self) { minutes in
                        PresetChip(minutes: minutes, selected: timers.selectedMinutes(for: kind) == minutes) {
                            timers.selectPreset(minutes, for: kind)
                        }
                    }
                }
                HStack(spacing: 10) {
                    CircleIconButton(icon: timers.isRunning(kind) ? .pause : .playArrow,
                                     iconSize: 24, background: Palette.orange, foreground: .black) {
                        timers.toggle(kind)
                    }
                    CircleIconButton(icon: .restartAlt, iconSize: 22) {
                        timers.reset(kind)
                    }
                    Text(timers.footnote(for: kind))
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

// MARK: - Cronómetro (mismo esquema que Timer y Pomodoro)

struct StopwatchPanel: View {
    @Environment(AppState.self) var app
    let modePicker: ModePicker

    var body: some View {
        let timers = app.timers
        HStack(spacing: 18) {
            // Círculo: el anillo da una vuelta por minuto, como una manecilla.
            TimelineView(.periodic(from: timers.stopwatchStart ?? .now, by: timers.isStopwatchRunning ? 0.1 : 3600)) { context in
                let elapsed = timers.stopwatchElapsed(at: context.date)
                ZStack {
                    RingProgress(value: elapsed > 0 ? elapsed.truncatingRemainder(dividingBy: 60) / 60 : 0,
                                 color: Palette.orange, lineWidth: 7)
                    VStack(spacing: 0) {
                        Text(Formatters.stopwatch(elapsed))
                            .lagoonFont(32, .semibold)
                            .tracking(-0.64)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 12)
                        Text(timers.stopwatchCaption)
                            .lagoonFont(11)
                            .foregroundStyle(Palette.secondary)
                    }
                }
                .frame(width: 150, height: 150)
            }
            .stagger(1)

            VStack(alignment: .leading, spacing: 14) {
                modePicker
                // Donde el timer tiene las duraciones, aquí van las últimas vueltas.
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
                HStack(spacing: 10) {
                    CircleIconButton(icon: timers.isStopwatchRunning ? .pause : .playArrow,
                                     iconSize: 24, background: Palette.orange, foreground: .black) {
                        timers.toggleStopwatch()
                    }
                    if timers.isStopwatchRunning {
                        CircleIconButton(icon: .flag, iconSize: 22) { timers.lap() }
                            .help("Vuelta")
                    } else {
                        CircleIconButton(icon: .restartAlt, iconSize: 22) {
                            withAnimation(Motion.tab) { timers.resetStopwatch() }
                        }
                        .help("Reiniciar")
                        .disabled(timers.stopwatchAccumulated == 0)
                        .opacity(timers.stopwatchAccumulated == 0 ? 0.4 : 1)
                    }
                    Text(timers.stopwatchFootnote)
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
