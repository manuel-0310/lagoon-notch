import AppKit
import SwiftUI

/// `Lagoon --snapshots <carpeta>` renderiza cada estado del prototipo a PNG con datos de ejemplo.
/// Sirve para comparar la app con el diseño sin necesidad de una pantalla con notch.
enum SnapshotRenderer {
    struct Scenario {
        let name: String
        let setup: (AppState) -> Void
    }

    @MainActor
    static func run(outputDirectory: URL) {
        AppEnvironment.isSnapshot = true
        if let madrid = TimeZone(identifier: "Europe/Madrid") { NSTimeZone.default = madrid }
        AppEnvironment.fixedNow = MockData.now
        let suite = UserDefaults.standard
        Prefs.registerDefaults()
        suite.removeObject(forKey: Prefs.weatherCityLat)
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for scenario in scenarios {
            let app = MockData.makeState()
            scenario.setup(app)
            let spec = app.notch.spec(for: app.notch.current)
            let height = max(110, spec.height + 70)
            let canvas = SnapshotCanvas(height: height) {
                NotchRootView().environment(app)
            }
            let renderer = ImageRenderer(content: canvas)
            renderer.scale = 2
            guard let image = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                print("✗ \(scenario.name)")
                continue
            }
            let url = outputDirectory.appendingPathComponent("\(scenario.name).png")
            try? png.write(to: url)
            print("✓ \(scenario.name)")
        }
    }

    // MARK: - Escenarios (los mismos identificadores que el prototipo)

    static let scenarios: [Scenario] = [
        Scenario(name: "1a-inactivo") { app in
            app.music.isPlaying = false
            app.battery.isCharging = false
            app.notch.refresh(animated: false)
        },
        Scenario(name: "1b-musica") { app in
            app.battery.isCharging = false
            app.notch.refresh(animated: false)
        },
        Scenario(name: "1c-timer") { app in
            app.music.isPlaying = false
            MockData.runTimer(app, kind: .timer, remaining: 24 * 60 + 13)
            app.notch.refresh(animated: false)
        },
        Scenario(name: "1d-cargando") { app in
            app.music.isPlaying = false
            app.notch.refresh(animated: false)
        },
        Scenario(name: "1e-hover") { app in
            app.music.isPlaying = false
            app.battery.isCharging = false
            app.notch.isHovering = true
            app.notch.refresh(animated: false)
        },
        Scenario(name: "1f-dos-actividades") { app in
            MockData.runTimer(app, kind: .timer, remaining: 24 * 60 + 13)
            app.notch.refresh(animated: false)
        },
        Scenario(name: "2a-cambio-cancion") { app in
            app.notch.showForSnapshot(.songChange(trackID: "mock"))
        },
        Scenario(name: "2b-cargador-conectado") { app in
            app.notch.showForSnapshot(.chargerConnected)
        },
        Scenario(name: "2c-cargador-desconectado") { app in
            app.battery.isCharging = false
            app.battery.isPluggedIn = false
            app.battery.minutesToEmpty = 312
            app.notch.showForSnapshot(.chargerDisconnected)
        },
        Scenario(name: "2d-bateria-baja") { app in
            app.battery.isCharging = false
            app.battery.isPluggedIn = false
            app.battery.level = 18
            app.battery.minutesToEmpty = 42
            app.notch.showForSnapshot(.lowBattery)
        },
        Scenario(name: "2e-airpods") { app in
            app.notch.showForSnapshot(.airPodsConnected(MockData.airPods))
        },
        Scenario(name: "2f-timer-corriendo") { app in
            app.music.isPlaying = false
            MockData.runTimer(app, kind: .pomodoro, remaining: 18 * 60 + 42)
            app.notch.refresh(animated: false)
        },
        Scenario(name: "2g-timer-terminado") { app in
            app.notch.showForSnapshot(.timerFinished(TimerFinish(kind: .pomodoroFocus, minutes: 25, nextMinutes: 5)))
        },
        Scenario(name: "2h-volumen") { app in
            app.notch.showForSnapshot(.volume)
        },
        Scenario(name: "2i-brillo") { app in
            app.notch.showForSnapshot(.brightness)
        },
        Scenario(name: "2j-proximo-evento") { app in
            var event = MockData.designReview
            event.start = MockData.now.addingTimeInterval(5 * 60)
            app.notch.showForSnapshot(.upcomingEvent(event))
        },
        Scenario(name: "2k-recordatorio") { app in
            app.notch.showForSnapshot(.reminderDue(MockData.reminders[0]))
        },
        Scenario(name: "2l-copiado") { app in
            app.notch.showForSnapshot(.copied(.link))
        },
        Scenario(name: "2m-arrastrando") { app in
            app.notch.isDropMode = true
            app.notch.trayDropTargeted = true
            app.notch.refresh(animated: false)
        },
        Scenario(name: "2n-bandeja") { app in
            app.notch.showForSnapshot(.traySaved)
        },
        Scenario(name: "3a-inicio") { app in expand(app, .home) },
        Scenario(name: "4a-musica") { app in expand(app, .music) },
        Scenario(name: "4b-bandeja") { app in expand(app, .tray) },
        Scenario(name: "4c-agenda") { app in expand(app, .calendar) },
        Scenario(name: "4d-pomodoro") { app in
            MockData.runTimer(app, kind: .pomodoro, remaining: 18 * 60 + 42)
            expand(app, .timer)
        },
        Scenario(name: "4e-cronometro") { app in
            app.timers.mode = .stopwatch
            app.timers.stopwatchAccumulated = 12 * 60 + 48.3
            app.timers.stopwatchStart = Date()
            app.timers.laps = [244.4, 271.8, 252.1]
            expand(app, .timer)
        },
        Scenario(name: "4f-portapapeles") { app in expand(app, .clipboard) },
        Scenario(name: "4g-espejo") { app in
            app.camera.authorization = .authorized
            expand(app, .mirror)
        },
        Scenario(name: "4h-reloj") { app in expand(app, .home, .clock) },
        Scenario(name: "4i-clima") { app in expand(app, .home, .weather) },
        Scenario(name: "4j-bateria") { app in expand(app, .home, .battery) },
        Scenario(name: "4k-volumen") { app in expand(app, .home, .sound) },
        Scenario(name: "5a-musica-vacia") { app in
            app.music.track = nil
            app.music.isPlaying = false
            expand(app, .music)
        },
        Scenario(name: "5b-bandeja-vacia") { app in
            app.tray.items = []
            expand(app, .tray)
        },
        Scenario(name: "5c-agenda-vacia") { app in
            app.calendar.todayEvents = []
            app.calendar.reminders = []
            expand(app, .calendar)
        },
        Scenario(name: "5d-portapapeles-vacio") { app in
            app.clipboard.items = []
            expand(app, .clipboard)
        },
        Scenario(name: "5e-espejo-sin-permiso") { app in
            app.camera.authorization = .denied
            expand(app, .mirror)
        },
        Scenario(name: "5f-clima-sin-ubicacion") { app in
            app.weather.current = nil
            app.weather.state = .noLocation
            expand(app, .home, .weather)
        },
    ]

    private static func expand(_ app: AppState, _ tab: PanelTab, _ subpage: HomeSubpage? = nil) {
        app.notch.tab = tab
        app.notch.subpage = subpage
        app.notch.isExpanded = true
        app.notch.refresh(animated: false)
    }
}

/// Fondo de escritorio y barra de menús como en las tarjetas del prototipo.
struct SnapshotCanvas<Content: View>: View {
    let height: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(stops: [.init(color: Color(hex: 0x7C9FB0), location: 0),
                                   .init(color: Color(hex: 0xB7C7C4), location: 0.55),
                                   .init(color: Color(hex: 0xD8D0C2), location: 1)],
                           startPoint: UnitPoint(x: 0.41, y: 0), endPoint: UnitPoint(x: 0.59, y: 1))
            HStack {
                HStack(spacing: 16) {
                    Text("Finder").fontWeight(.bold)
                    Text("Archivo")
                    Text("Edición")
                }
                Spacer()
                Text("lun 27 sep 9:41")
            }
            .font(.system(size: 13))
            .foregroundStyle(Color(hex: 0x1D1D1F))
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(Color.white.opacity(0.3))
            content
        }
        .frame(width: NotchGeometry.windowSize.width, height: height)
        .clipped()
    }
}
