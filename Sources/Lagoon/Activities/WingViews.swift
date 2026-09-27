import AppKit
import SwiftUI

/// Alturas de las barras de la onda en las alas (1b).
private let wingWaveHeights: [CGFloat] = [7, 13, 17, 10, 6]

/// Estado continuo en las alas (sección 1): nunca hay contenido en los 200 pt centrales.
struct WingsView: View {
    @Environment(AppState.self) var app
    let content: WingContent

    var body: some View {
        HStack(spacing: 0) {
            left
            Spacer(minLength: 0)
            right
        }
        .padding(.horizontal, 12)
        .frame(height: app.notch.geometry.notchHeight)
    }

    @ViewBuilder
    private var left: some View {
        switch content {
        case .music, .musicPlus:
            ArtworkView(image: app.music.artwork, size: 20, radius: 5)
                .id(app.music.track?.id ?? "")
                .transition(.artworkFlip)
        case .timer, .stopwatch:
            Icon(.timer, size: 16, color: Palette.orange)
        case .pomodoro:
            HStack(spacing: 6) {
                Icon(.timer, size: 16, color: Palette.orange)
                Text(app.timers.pomodoroPhase == .focus ? "Pomodoro" : "Descanso")
                    .lagoonFont(12)
                    .foregroundStyle(Palette.secondary)
            }
        case .charging:
            Icon(.bolt, size: 17, color: Palette.green)
        }
    }

    @ViewBuilder
    private var right: some View {
        switch content {
        case .music:
            Waveform(heights: wingWaveHeights, color: app.music.accentNS, animating: app.music.isPlaying)
        case .timer:
            CountdownText(size: 13)
        case .stopwatch:
            StopwatchText(size: 13, tenths: false)
                .foregroundStyle(Palette.orange)
        case .pomodoro:
            HStack(spacing: 7) {
                CountdownRing(size: 16, lineWidth: 2.5)
                CountdownText(size: 13)
            }
        case .charging:
            ChargingLevel(fontSize: 12, glyph: CGSize(width: 20, height: 10), spacing: 6)
        case let .musicPlus(secondary):
            switch secondary {
            case .timer, .pomodoro:
                HStack(spacing: 5) {
                    Icon(.timer, size: 15, color: Palette.orange)
                    CountdownText(size: 13)
                }
            case .stopwatch:
                HStack(spacing: 5) {
                    Icon(.timer, size: 15, color: Palette.orange)
                    StopwatchText(size: 13, tenths: false).foregroundStyle(Palette.orange)
                }
            case .charging:
                HStack(spacing: 5) {
                    Icon(.bolt, size: 15, color: Palette.green)
                    Text("\(app.battery.level) %")
                        .lagoonFont(12, .semibold)
                        .monospacedDigit()
                        .foregroundStyle(Palette.green)
                }
            }
        }
    }
}

/// "82 %" + pila, en verde.
struct ChargingLevel: View {
    @Environment(AppState.self) var app
    var fontSize: CGFloat
    var glyph: CGSize
    var spacing: CGFloat
    var color: Color = Palette.green

    var body: some View {
        HStack(spacing: spacing) {
            Text("\(app.battery.level) %")
                .lagoonFont(fontSize, .semibold)
                .monospacedDigit()
            BatteryGlyph(level: app.battery.fraction, color: color, width: glyph.width, height: glyph.height)
        }
        .foregroundStyle(color)
    }
}

/// Tiempo restante del timer/pomodoro, actualizado una vez por segundo.
struct CountdownText: View {
    @Environment(AppState.self) var app
    var size: CGFloat
    var weight: Font.Weight = .semibold
    var color: Color = Palette.orange

    var body: some View {
        let timers = app.timers
        TimelineView(.periodic(from: timers.tickAnchor, by: 1)) { context in
            Text(Formatters.countdown(timers.remaining(at: context.date)))
                .lagoonFont(size, weight)
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }
}

/// Anillo de progreso del timer.
struct CountdownRing: View {
    @Environment(AppState.self) var app
    var size: CGFloat
    var lineWidth: CGFloat

    var body: some View {
        let timers = app.timers
        TimelineView(.periodic(from: timers.tickAnchor, by: 1)) { context in
            RingProgress(value: timers.progress(at: context.date), color: Palette.orange, lineWidth: lineWidth)
                .frame(width: size, height: size)
        }
    }
}

/// Cronómetro ("12:48" o "12:48,3").
struct StopwatchText: View {
    @Environment(AppState.self) var app
    var size: CGFloat
    var weight: Font.Weight = .semibold
    var tenths: Bool

    var body: some View {
        let timers = app.timers
        TimelineView(.periodic(from: timers.stopwatchStart ?? .now, by: tenths ? 0.1 : 1)) { context in
            let elapsed = timers.stopwatchElapsed(at: context.date)
            Text(tenths ? Formatters.stopwatch(elapsed) : Formatters.countdown(elapsed.rounded(.down)))
                .lagoonFont(size, weight)
                .monospacedDigit()
        }
    }
}

// MARK: - Actividades breves en las alas

struct WingActivityView: View {
    @Environment(AppState.self) var app
    let activity: LiveActivity

    var body: some View {
        HStack(spacing: 0) {
            left
            Spacer(minLength: 0)
            right
        }
        .padding(.horizontal, 12)
        .frame(height: app.notch.geometry.notchHeight)
        .overlay(alignment: .bottom) {
            if activity == .chargerConnected { ChargeFlash() }
        }
    }

    @ViewBuilder
    private var left: some View {
        switch activity {
        case .chargerConnected:
            HStack(spacing: 6) {
                PopIn { Icon(.bolt, size: 17) }
                Text("Cargando").lagoonFont(13, .semibold)
            }
            .foregroundStyle(Palette.green)
        case .chargerDisconnected:
            HStack(spacing: 6) {
                Icon(.powerOff, size: 16)
                Text("En batería").lagoonFont(13, .semibold)
            }
        case .copied:
            HStack(spacing: 6) {
                Icon(.contentPaste, size: 15)
                Text("Copiado").lagoonFont(12, .semibold)
            }
        case .traySaved:
            HStack(spacing: 6) {
                Icon(.inventory2, size: 15)
                Text("Bandeja").lagoonFont(12, .semibold)
            }
            .foregroundStyle(Palette.cyan)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var right: some View {
        switch activity {
        case .chargerConnected:
            ChargingLevel(fontSize: 13, glyph: CGSize(width: 24, height: 12), spacing: 7)
        case .chargerDisconnected:
            HStack(spacing: 7) {
                Text(app.battery.remainingDescription)
                    .lagoonFont(13, .medium)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondary)
                BatteryGlyph(level: app.battery.fraction, color: .white, width: 24, height: 12)
            }
        case let .copied(kind):
            HStack(spacing: 5) {
                Icon(kind.icon, size: 15)
                Text(kind.label).lagoonFont(12)
            }
            .foregroundStyle(Palette.secondary)
        case .traySaved:
            Text(app.tray.countDescription)
                .lagoonFont(12)
                .foregroundStyle(Palette.secondary)
        default:
            EmptyView()
        }
    }
}

/// El rayo escala 0,6 → 1,1 → 1.
struct PopIn<Content: View>: View {
    @ViewBuilder var content: Content
    @State var scale: CGFloat = 0.6

    var body: some View {
        content
            .scaleEffect(scale)
            .onAppear {
                guard !Motion.reduced else { scale = 1; return }
                withAnimation(.easeOut(duration: 0.3)) { scale = 1.1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeInOut(duration: 0.3)) { scale = 1 }
                }
            }
    }
}

/// Destello verde que recorre el borde inferior de izquierda a derecha (600 ms).
struct ChargeFlash: View {
    @State private var progress: CGFloat = 0
    @State private var visible = true

    var body: some View {
        GeometryReader { proxy in
            let width: CGFloat = 90
            LinearGradient(colors: [Palette.green.opacity(0), Palette.green, Palette.green.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: width, height: 2)
                .offset(x: -width + (proxy.size.width + width) * progress, y: proxy.size.height - 2)
                .opacity(visible ? 1 : 0)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !Motion.reduced else { visible = false; return }
            withAnimation(.easeInOut(duration: 0.6).delay(0.1)) { progress = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                withAnimation(.easeOut(duration: 0.2)) { visible = false }
            }
        }
    }
}
