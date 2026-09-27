import AppKit
import SwiftUI

/// Muestra música, timer, carga y clima en la pantalla de bloqueo.
///
/// Escucha `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` (sin sondeo). Al bloquear,
/// coloca una ventana transparente bajo el notch y la mueve al espacio de la pantalla de bloqueo
/// con SkyLight (API privada; ver `SkyLight`).
final class LockScreenController {
    private let app: AppState
    private var window: NSPanel?
    private var observers: [NSObjectProtocol] = []
    private(set) var isLocked = false

    /// Zona de la ventana: cabe el bloque desplegado con su sombra.
    static let size = CGSize(width: 480, height: 190)

    init(app: AppState) {
        self.app = app
    }

    func start() {
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"),
                                            object: nil, queue: .main) { [weak self] _ in self?.locked() })
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"),
                                            object: nil, queue: .main) { [weak self] _ in self?.unlocked() })
    }

    func stop() {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll()
        window?.orderOut(nil)
    }

    private func locked() {
        isLocked = true
        guard Prefs.bool(Prefs.lockScreenEnabled), SkyLight.isAvailable,
              let screen = NotchGeometry.preferredScreen() else { return }
        let window = self.window ?? makeWindow()
        let geometry = NotchGeometry.detect(on: screen)
        let frame = CGRect(x: screen.frame.midX - Self.size.width / 2,
                           y: screen.frame.maxY - Self.size.height,
                           width: Self.size.width, height: Self.size.height)
        window.setFrame(frame, display: false)
        window.contentView = NSHostingView(rootView: LockScreenView(geometry: geometry).environment(app))
        window.orderFrontRegardless()
        SkyLight.moveToLockScreen(window)
    }

    private func unlocked() {
        isLocked = false
        window?.orderOut(nil)
        window?.contentView = nil
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(Int32.max - 2))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.canBecomeVisibleWithoutLogin = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none
        window = panel
        return panel
    }
}

/// Lo que se ve en la pantalla de bloqueo: alas junto al notch; al pasar el cursor, un bloque
/// con los controles. Así no tapa la fecha y la hora de macOS.
struct LockScreenView: View {
    @Environment(AppState.self) var app
    let geometry: NotchGeometry
    @State private var expanded = false

    private var showMusic: Bool { Prefs.bool(Prefs.lockScreenMusic) && app.music.track != nil }
    private var showTimer: Bool {
        Prefs.bool(Prefs.lockScreenTimer) && (app.timers.isCountdownRunning || app.timers.isStopwatchRunning)
    }
    private var showCharging: Bool { Prefs.bool(Prefs.lockScreenCharging) && app.battery.isCharging }
    private var showWeather: Bool { Prefs.bool(Prefs.lockScreenWeather) && app.weather.current != nil }
    private var hasContent: Bool { showMusic || showTimer || showCharging || showWeather }

    var body: some View {
        let width: CGFloat = expanded ? 420 : geometry.notchWidth + 2 * 58
        let height: CGFloat = expanded ? geometry.notchHeight + 8 + expandedHeight + 14 : geometry.notchHeight
        ZStack(alignment: .top) {
            if hasContent {
                NotchShape(radius: expanded ? 26 : 14)
                    .fill(Color.black)
                    .frame(width: width, height: height)
                    .shadow(color: .black.opacity(expanded ? 0.3 : 0), radius: 16, y: 12)
                Group {
                    if expanded { expandedContent } else { wings }
                }
                .frame(width: width, height: height, alignment: .top)
                .clipShape(NotchShape(radius: expanded ? 26 : 14))
                .transition(.opacity)
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(Motion.reduced ? Motion.fade : Motion.expand) { expanded = hovering }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }

    private var expandedHeight: CGFloat { showMusic ? 88 : 36 }

    // MARK: Alas

    private var wings: some View {
        HStack(spacing: 0) {
            Group {
                if showMusic {
                    ArtworkView(image: app.music.artwork, size: 20, radius: 5)
                } else if showTimer {
                    Icon(.timer, size: 16, color: Palette.orange)
                } else if showCharging {
                    Icon(.bolt, size: 17, color: Palette.green)
                } else if let now = app.weather.current {
                    Icon(WeatherService.symbol(code: now.code, isDay: now.isDay).icon, size: 17,
                         color: WeatherService.symbol(code: now.code, isDay: now.isDay).color)
                }
            }
            Spacer(minLength: 0)
            Group {
                if showTimer {
                    if app.timers.isCountdownRunning { CountdownText(size: 13) } else { StopwatchText(size: 13, tenths: false) }
                } else if showMusic {
                    Waveform(heights: [7, 13, 17, 10, 6], color: app.music.accentNS, animating: app.music.isPlaying)
                } else if showCharging {
                    ChargingLevel(fontSize: 12, glyph: CGSize(width: 20, height: 10), spacing: 6)
                } else if let now = app.weather.current {
                    Text(app.weather.format(now.temperature)).lagoonFont(12, .semibold)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: geometry.notchHeight)
    }

    // MARK: Bloque desplegado

    private var expandedContent: some View {
        VStack(spacing: 10) {
            Color.clear.frame(height: geometry.notchHeight - 2)
            if showMusic {
                HStack(spacing: 12) {
                    ArtworkView(image: app.music.artwork, size: 44, radius: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.music.track?.title ?? "").lagoonFont(14, .semibold).lineLimit(1)
                        Text(app.music.track?.artist ?? "")
                            .lagoonFont(12)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 14) {
                        IconButton(icon: .skipPrevious, size: 22) { app.music.previous() }
                        IconButton(icon: app.music.isPlaying ? .pause : .playArrow, size: 26) { app.music.playPause() }
                        IconButton(icon: .skipNext, size: 22) { app.music.next() }
                    }
                }
            }
            HStack(spacing: 14) {
                if showTimer {
                    HStack(spacing: 5) {
                        Icon(.timer, size: 14, color: Palette.orange)
                        if app.timers.isCountdownRunning { CountdownText(size: 12) } else {
                            StopwatchText(size: 12, tenths: false).foregroundStyle(Palette.orange)
                        }
                    }
                }
                if app.battery.hasBattery, Prefs.bool(Prefs.lockScreenCharging) {
                    HStack(spacing: 5) {
                        if app.battery.isCharging { Icon(.bolt, size: 14, color: Palette.green) }
                        Text("\(app.battery.level) %")
                            .lagoonFont(12, .semibold)
                            .monospacedDigit()
                            .foregroundStyle(app.battery.isCharging ? Palette.green : .white)
                    }
                }
                Spacer(minLength: 0)
                if showWeather, let now = app.weather.current {
                    let symbol = WeatherService.symbol(code: now.code, isDay: now.isDay)
                    HStack(spacing: 5) {
                        Icon(symbol.icon, size: 15, color: symbol.color)
                        Text("\(app.weather.format(now.temperature)) \(app.weather.cityName)")
                            .lagoonFont(12, .semibold)
                            .lineLimit(1)
                    }
                }
            }
            .frame(height: 20)
        }
        .padding(.horizontal, 16)
    }
}
