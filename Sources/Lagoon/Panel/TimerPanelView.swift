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

// MARK: - Cronómetro

struct StopwatchPanel: View {
    @Environment(AppState.self) var app
    let modePicker: ModePicker

    var body: some View {
        let timers = app.timers
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                modePicker
                StopwatchText(size: 56, weight: .thin, tenths: true)
                    .tracking(-1.68)
                    .frame(height: 56)
                HStack(spacing: 8) {
                    if timers.isStopwatchRunning {
                        PillButton(title: "Vuelta") { timers.lap() }
                        PillButton(title: "Detener", style: .tinted(Palette.red)) { timers.toggleStopwatch() }
                    } else if timers.stopwatchAccumulated > 0 {
                        PillButton(title: "Reiniciar") { withAnimation(Motion.tab) { timers.resetStopwatch() } }
                        PillButton(title: "Reanudar", style: .tinted(Palette.green)) { timers.toggleStopwatch() }
                    } else {
                        PillButton(title: "Iniciar", style: .tinted(Palette.green)) { timers.toggleStopwatch() }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .stagger(1)

            VStack(spacing: 0) {
                if timers.laps.isEmpty {
                    Text("Las vueltas aparecerán aquí")
                        .lagoonFont(12)
                        .foregroundStyle(Color.white(0.35))
                } else {
                    LagoonScrollView {
                        VStack(spacing: 0) {
                            ForEach(timers.lapRows) { row in
                                HStack {
                                    Text("Vuelta \(row.number)")
                                        .foregroundStyle(Palette.secondary)
                                    Spacer()
                                    Text(Formatters.stopwatch(row.duration))
                                        .monospacedDigit()
                                        .foregroundStyle(row.isBest ? Palette.green : row.isWorst ? Palette.red : .white)
                                }
                                .lagoonFont(12.5)
                                .padding(.vertical, 7)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(Palette.divider).frame(height: 1)
                                }
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                    }
                    .frame(maxHeight: 132)
                }
            }
            .frame(width: 210)
            .frame(maxHeight: .infinity)
            .stagger(2)
        }
    }
}
