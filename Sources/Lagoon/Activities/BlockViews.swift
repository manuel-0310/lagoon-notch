import AppKit
import SwiftUI

/// Alturas de la onda en el bloque "Cambio de canción" (2a).
private let blockWaveHeights: [CGFloat] = [10, 18, 24, 14, 8, 16]

/// Actividades que piden atención: bajan en bloque (radio 26, padding 40 16 14).
struct BlockActivityView: View {
    @Environment(AppState.self) var app
    let activity: LiveActivity

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: app.notch.geometry.notchHeight + 8)
            HStack(alignment: .center, spacing: 12) {
                content
            }
            .frame(height: activity.blockContentHeight)
            Color.clear.frame(height: 14)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var content: some View {
        switch activity {
        case .songChange:
            SongChangeBlock()
        case .lowBattery:
            LowBatteryBlock()
        case let .airPodsConnected(device):
            AirPodsBlock(device: device)
        case let .timerFinished(finish):
            TimerFinishedBlock(finish: finish)
        case .volume:
            LevelBlock(icon: app.audio.isMuted || app.audio.volume <= 0.001 ? .volumeOff : .volumeUp,
                       value: app.audio.isMuted ? 0 : app.audio.volume)
        case .brightness:
            LevelBlock(icon: .lightMode, value: app.audio.brightness)
        case let .upcomingEvent(event):
            UpcomingEventBlock(event: event)
        case let .reminderDue(reminder):
            ReminderBlock(reminder: reminder)
        case .welcome:
            WelcomeBlock()
        case let .focusChanged(mode, active):
            FocusBlock(mode: mode, active: active)
        case let .privacyStarted(alert):
            PrivacyBlock(alert: alert)
        case let .claudePermission(request):
            ClaudePermissionBlock(request: request)
        case let .claudeNotice(notice):
            ClaudeNoticeBlock(notice: notice)
        default:
            EmptyView()
        }
    }
}

/// Título + subtítulo de las actividades en bloque.
struct BlockText: View {
    var eyebrow: String? = nil
    var eyebrowColor: Color = Palette.pink
    var title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let eyebrow {
                Text(eyebrow)
                    .lagoonFont(11, .semibold)
                    .foregroundStyle(eyebrowColor)
                    .lineLimit(1)
            }
            Text(title)
                .lagoonFont(14, .semibold)
                .lineLimit(1)
                .truncationMode(.tail)
            if let subtitle {
                Text(subtitle)
                    .lagoonFont(12)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 2a Cambio de canción

struct SongChangeBlock: View {
    @Environment(AppState.self) var app

    var body: some View {
        let music = app.music
        ArtworkView(image: music.artwork, size: 44, radius: 10)
            .id(music.track?.id ?? "")
            .transition(.artworkFlip)
        BlockText(eyebrow: "Ahora suena", eyebrowColor: music.accent,
                  title: music.track?.title ?? "—", subtitle: music.track?.artist)
        Waveform(heights: blockWaveHeights, barWidth: 3.5, color: music.accentNS, animating: music.isPlaying)
    }
}

// MARK: - 2d Batería baja

struct LowBatteryBlock: View {
    @Environment(AppState.self) var app
    @State private var pulse = false

    var body: some View {
        let battery = app.battery
        ZStack {
            Circle().fill(Palette.red.opacity(0.22))
            Icon(.batteryAlert, size: 20, color: Palette.red)
                .scaleEffect(pulse ? 1.18 : 1)
        }
        .frame(width: 36, height: 36)
        .onAppear(perform: pulseTwice)
        BlockText(title: "Batería baja", subtitle: battery.lowBatterySubtitle)
        PillButton(title: "Ahorro de energía") { SystemLinks.open(.battery) }
    }

    /// Dos pulsos rojos (2 × 400 ms) y un toque háptico.
    private func pulseTwice() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        guard !Motion.reduced else { return }
        for i in 0..<2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.4 + 0.2) {
                withAnimation(.easeOut(duration: 0.2)) { pulse = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.easeIn(duration: 0.2)) { pulse = false }
                }
            }
        }
    }
}

// MARK: - 2e AirPods conectados

struct AirPodsBlock: View {
    let device: BluetoothDevice
    @State var filled = false

    var body: some View {
        ZStack {
            StripedFill(a: Color(hex: 0x2A2A2E), b: Color(hex: 0x34343A), stripe: 6)
            Icon(device.kind.icon, size: 22, color: .white(0.7))
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        BlockText(title: device.name, subtitle: "Conectados")
        HStack(spacing: 10) {
            let rings = device.batteryRings
            ForEach(Array(rings.enumerated()), id: \.offset) { index, ring in
                VStack(spacing: 4) {
                    ZStack {
                        RingProgress(value: filled ? Double(ring.level) / 100 : 0,
                                     color: ring.level <= 20 ? Palette.red : Palette.green,
                                     lineWidth: 3)
                            .animation(Motion.reduced ? Motion.fade : .easeOut(duration: 0.5).delay(Double(index) * 0.08),
                                       value: filled)
                        Text("\(ring.level)")
                            .lagoonFont(10, .semibold)
                            .monospacedDigit()
                    }
                    .frame(width: 30, height: 30)
                    Text(ring.label)
                        .lagoonFont(10)
                        .foregroundStyle(Palette.secondary)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { filled = true }
        }
    }
}

// MARK: - 2g Timer terminado

struct TimerFinishedBlock: View {
    @Environment(AppState.self) var app
    let finish: TimerFinish

    var body: some View {
        Text("00:00")
            .lagoonFont(30, .semibold)
            .monospacedDigit()
            .tracking(-0.6)
            .foregroundStyle(Palette.orange)
            .fixedSize()
        BlockText(title: finish.title, subtitle: finish.subtitle)
        PillButton(title: finish.secondaryAction) {
            app.timers.handleFinish(finish, primary: false)
        }
        PillButton(title: finish.primaryAction, style: .filled(Palette.orange, text: .black)) {
            app.timers.handleFinish(finish, primary: true)
        }
    }
}

// MARK: - 2h/2i Volumen y brillo

struct LevelBlock: View {
    @Environment(AppState.self) var app
    let icon: MS
    let value: Double

    var body: some View {
        Icon(icon, size: 20)
        ProgressBar(value: value, color: .white, track: .white(0.16), height: 6)
            .animation(Motion.hudStep, value: value)
        Text("\(Int((value * 100).rounded()))")
            .lagoonFont(12, .semibold)
            .monospacedDigit()
            .frame(width: 22, alignment: .trailing)
    }
}

// MARK: - 2j Próximo evento

struct UpcomingEventBlock: View {
    @Environment(AppState.self) var app
    let event: CalendarEvent

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Palette.blue)
            .frame(width: 4, height: 38)
        TimelineView(.everyMinute) { context in
            BlockText(eyebrow: Formatters.until(event.start, now: AppEnvironment.fixedNow ?? context.date).capitalizedFirst,
                      eyebrowColor: Palette.blue,
                      title: event.title,
                      subtitle: event.subtitle)
        }
        if event.meetingURL != nil {
            PillButton(title: "Unirse", icon: .videocam, style: .filled(Palette.blueButton, text: .white)) {
                app.calendar.join(event)
                app.notch.dismissTransient()
            }
        }
    }
}

// MARK: - 2k Recordatorio

struct ReminderBlock: View {
    @Environment(AppState.self) var app
    let reminder: ReminderItem

    var body: some View {
        IconButton(icon: .radioButtonUnchecked, size: 22, color: .white(0.45)) {
            app.calendar.complete(reminder)
            app.notch.dismissTransient()
        }
        BlockText(eyebrow: reminder.eyebrow, eyebrowColor: Palette.cyan, title: reminder.title)
        PillButton(title: "Hecho") {
            app.calendar.complete(reminder)
            app.notch.dismissTransient()
        }
        PillButton(icon: .snooze) {
            app.calendar.snooze(reminder)
            app.notch.dismissTransient()
        }
    }
}

// MARK: - Concentración

struct FocusBlock: View {
    let mode: FocusMode
    let active: Bool

    var body: some View {
        ZStack {
            Circle().fill(mode.tint.opacity(active ? 0.22 : 0.1))
            Icon(mode.icon, size: 19, color: active ? mode.tint : .white(0.5))
        }
        .frame(width: 36, height: 36)
        BlockText(title: mode.name, subtitle: active ? "Activado" : "Desactivado")
        if active {
            Text("Concentración")
                .lagoonFont(11, .semibold)
                .foregroundStyle(mode.tint)
        }
    }
}

// MARK: - Privacidad

struct PrivacyBlock: View {
    let alert: PrivacyAlert

    var body: some View {
        ZStack {
            Circle().fill(alert.kind.color.opacity(0.2))
            Icon(alert.kind.icon, size: 19, color: alert.kind.color)
        }
        .frame(width: 36, height: 36)
        BlockText(title: alert.title, subtitle: alert.subtitle)
        Circle()
            .fill(alert.kind.color)
            .frame(width: 8, height: 8)
    }
}

// MARK: - Bienvenida (primer arranque)

struct WelcomeBlock: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x3FC0C0), Color(hex: 0x006F8C)],
                           startPoint: .top, endPoint: .bottom)
            RoundedRectangle(cornerRadius: 4).fill(.black).frame(width: 22, height: 8).offset(y: -9)
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        BlockText(eyebrow: "Lagoon está listo", eyebrowColor: Palette.cyan,
                  title: "Pasa el cursor por el notch",
                  subtitle: "Clic derecho para Ajustes")
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
