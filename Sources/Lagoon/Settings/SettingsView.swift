import AVFoundation
import CoreLocation
import EventKit
import ServiceManagement
import SwiftUI

/// Ajustes (ventana normal de macOS).
struct SettingsView: View {
    @Environment(AppState.self) var app

    @AppStorage(Prefs.activityDuration) private var activityDuration = 4.0
    @AppStorage(Prefs.hoverToOpen) private var hoverToOpen = true
    @AppStorage(Prefs.hoverDelay) private var hoverDelay = 0.15
    @AppStorage(Prefs.showOnScreensWithoutNotch) private var showWithoutNotch = true
    @AppStorage(Prefs.animationIntensity) private var intensity = AnimationIntensity.normal.rawValue

    @AppStorage(Prefs.showSongChange) private var showSongChange = true
    @AppStorage(Prefs.showMusicWings) private var showMusicWings = true
    @AppStorage(Prefs.showChargingWings) private var showChargingWings = true
    @AppStorage(Prefs.showChargerEvents) private var showChargerEvents = true
    @AppStorage(Prefs.showLowBattery) private var showLowBattery = true
    @AppStorage(Prefs.lowBatteryThreshold) private var lowBatteryThreshold = 20
    @AppStorage(Prefs.showAirPods) private var showAirPods = true
    @AppStorage(Prefs.showVolumeHUD) private var showVolumeHUD = true
    @AppStorage(Prefs.replaceSystemHUD) private var replaceSystemHUD = false
    @AppStorage(Prefs.showEvents) private var showEvents = true
    @AppStorage(Prefs.eventLeadMinutes) private var eventLeadMinutes = 5
    @AppStorage(Prefs.showReminders) private var showReminders = true
    @AppStorage(Prefs.showClipboardCopied) private var showClipboardCopied = true

    @AppStorage(Prefs.timerSound) private var timerSound = true
    @AppStorage(Prefs.pomodoroBreakMinutes) private var breakMinutes = 5
    @AppStorage(Prefs.clipboardEnabled) private var clipboardEnabled = true
    @AppStorage(Prefs.clipboardLimit) private var clipboardLimit = 50
    @AppStorage(Prefs.trayLifetimeMinutes) private var trayLifetime = 60
    @AppStorage(Prefs.useFahrenheit) private var useFahrenheit = false
    @AppStorage(Prefs.worldClocks) private var worldClocks = ""

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var accessibilityTrusted = MediaKeyTap.isTrusted

    var body: some View {
        Form {
            Section("General") {
                Toggle("Abrir al iniciar sesión", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                Toggle("Abrir el panel al pasar el cursor", isOn: $hoverToOpen)
                if hoverToOpen {
                    Picker("Retraso del hover", selection: $hoverDelay) {
                        Text("Inmediato (150 ms)").tag(0.15)
                        Text("Corto (300 ms)").tag(0.3)
                        Text("Largo (600 ms)").tag(0.6)
                    }
                }
                Picker("Duración de los avisos", selection: $activityDuration) {
                    Text("2 s").tag(2.0)
                    Text("4 s").tag(4.0)
                    Text("6 s").tag(6.0)
                    Text("10 s").tag(10.0)
                }
                Toggle("Mostrar en pantallas sin notch", isOn: $showWithoutNotch)
            }

            Section("Apariencia") {
                Picker("Intensidad de animación", selection: $intensity) {
                    ForEach(AnimationIntensity.allCases) { level in
                        Text(level.title).tag(level.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text("“Mínima” cambia los muelles por fundidos de 200 ms, igual que Reducir movimiento.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Actividades en vivo") {
                Toggle("Música en las alas", isOn: $showMusicWings)
                Toggle("Cambio de canción", isOn: $showSongChange)
                Toggle("Carga en las alas mientras carga", isOn: $showChargingWings)
                Toggle("Cargador conectado / desconectado", isOn: $showChargerEvents)
                Toggle("Batería baja", isOn: $showLowBattery)
                if showLowBattery {
                    Stepper("Umbral: \(lowBatteryThreshold) %", value: $lowBatteryThreshold, in: 5...50, step: 5)
                }
                Toggle("AirPods conectados", isOn: $showAirPods)
                Toggle("Próximos eventos", isOn: $showEvents)
                if showEvents {
                    Stepper("Avisar \(eventLeadMinutes) min antes", value: $eventLeadMinutes, in: 1...30)
                }
                Toggle("Recordatorios", isOn: $showReminders)
                Toggle("Copiado al portapapeles", isOn: $showClipboardCopied)
            }

            Section("Volumen y brillo") {
                Toggle("Mostrar indicador de volumen", isOn: $showVolumeHUD)
                Toggle("Reemplazar el indicador de macOS", isOn: $replaceSystemHUD)
                    .onChange(of: replaceSystemHUD) { _, enabled in
                        if enabled, !MediaKeyTap.isTrusted { MediaKeyTap.requestTrust() }
                        app.configureMediaKeys()
                    }
                if replaceSystemHUD && !accessibilityTrusted {
                    HStack {
                        Text("Necesita permiso de Accesibilidad.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Abrir Ajustes") { SystemLinks.open(.accessibility) }
                    }
                }
            }

            Section("Timer y Pomodoro") {
                Toggle("Sonido al terminar", isOn: $timerSound)
                Stepper("Descanso corto: \(breakMinutes) min", value: $breakMinutes, in: 1...30)
                    .onChange(of: breakMinutes) { _, value in app.timers.breakMinutes = value }
            }

            Section("Portapapeles y bandeja") {
                Toggle("Guardar historial del portapapeles", isOn: $clipboardEnabled)
                Stepper("Elementos: \(clipboardLimit)", value: $clipboardLimit, in: 10...200, step: 10)
                Button("Borrar historial") { app.clipboard.clear() }
                Picker("La bandeja se vacía tras", selection: $trayLifetime) {
                    Text("30 min").tag(30)
                    Text("1 hora").tag(60)
                    Text("3 horas").tag(180)
                    Text("1 día").tag(1440)
                }
            }

            Section("Clima y reloj") {
                Toggle("Grados Fahrenheit", isOn: $useFahrenheit)
                    .onChange(of: useFahrenheit) { _, _ in app.weather.refresh(force: true) }
                TextField("Zonas horarias (identificadores separados por comas)", text: $worldClocks)
                Text("Por ejemplo: America/Mexico_City, America/New_York, Asia/Tokyo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permisos") {
                PermissionRow(title: "Calendario y Recordatorios", granted: app.calendar.eventsAccess == .granted) {
                    app.calendar.requestAccess(openSettingsIfDenied: true)
                }
                PermissionRow(title: "Cámara (espejo)", granted: app.camera.authorization == .authorized) {
                    app.camera.requestAccess()
                }
                PermissionRow(title: "Accesibilidad (pegar y teclas)", granted: accessibilityTrusted) {
                    MediaKeyTap.requestTrust()
                    SystemLinks.open(.accessibility)
                }
                PermissionRow(title: "Automatización (Música y Spotify)", granted: nil) {
                    SystemLinks.open(.automation)
                }
                PermissionRow(title: "Ubicación (clima)", granted: nil) {
                    SystemLinks.open(.location)
                }
            }

            Section {
                HStack {
                    Text("Lagoon \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1")")
                    Spacer()
                    Button("Salir de Lagoon") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 520)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            accessibilityTrusted = MediaKeyTap.isTrusted
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct PermissionRow: View {
    let title: String
    /// nil = macOS no permite consultarlo sin preguntar.
    let granted: Bool?
    var action: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if granted == true {
                Label("Concedido", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                Button(granted == false ? "Permitir…" : "Abrir Ajustes", action: action)
            }
        }
    }
}
