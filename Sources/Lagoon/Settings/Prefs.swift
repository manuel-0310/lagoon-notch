import Foundation

/// Claves de preferencias (UserDefaults). Las vistas usan `@AppStorage` con estas claves.
enum Prefs {
    // General
    static let activityDuration = "activityDuration"
    static let hoverToOpen = "hoverToOpen"
    static let hoverDelay = "hoverDelay"
    static let showOnScreensWithoutNotch = "showOnScreensWithoutNotch"
    static let didShowWelcome = "didShowWelcome"

    // Apariencia
    static let animationIntensity = "animationIntensity"

    // Actividades
    static let showSongChange = "showSongChange"
    static let showMusicWings = "showMusicWings"
    static let showChargingWings = "showChargingWings"
    static let showChargerEvents = "showChargerEvents"
    static let showLowBattery = "showLowBattery"
    static let lowBatteryThreshold = "lowBatteryThreshold"
    static let showAirPods = "showAirPods"
    static let showVolumeHUD = "showVolumeHUD"
    static let replaceSystemHUD = "replaceSystemHUD"
    static let showEvents = "showEvents"
    static let eventLeadMinutes = "eventLeadMinutes"
    static let showReminders = "showReminders"

    // Timer
    static let timerSound = "timerSound"
    static let pomodoroFocusMinutes = "pomodoroFocusMinutes"
    static let pomodoroBreakMinutes = "pomodoroBreakMinutes"
    static let timerMinutes = "timerMinutes"

    // Portapapeles
    static let clipboardEnabled = "clipboardEnabled"
    static let clipboardLimit = "clipboardLimit"

    // Bandeja
    static let trayLifetimeMinutes = "trayLifetimeMinutes"

    // Clima y reloj
    static let weatherCityName = "weatherCityName"
    static let weatherCityLat = "weatherCityLat"
    static let weatherCityLon = "weatherCityLon"
    static let useFahrenheit = "useFahrenheit"
    static let worldClocks = "worldClocks"

    // Espejo
    static let mirrorFlip = "mirrorFlip"
    static let mirrorZoom = "mirrorZoom"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            activityDuration: 4.0,
            hoverToOpen: true,
            hoverDelay: 0.15,
            showOnScreensWithoutNotch: true,
            animationIntensity: AnimationIntensity.normal.rawValue,
            showSongChange: true,
            showMusicWings: true,
            showChargingWings: true,
            showChargerEvents: true,
            showLowBattery: true,
            lowBatteryThreshold: 20,
            showAirPods: true,
            showVolumeHUD: true,
            replaceSystemHUD: false,
            showEvents: true,
            eventLeadMinutes: 5,
            showReminders: true,
            timerSound: true,
            pomodoroFocusMinutes: 25,
            pomodoroBreakMinutes: 5,
            timerMinutes: 25,
            clipboardEnabled: true,
            clipboardLimit: 50,
            trayLifetimeMinutes: 60,
            useFahrenheit: false,
            worldClocks: "America/Mexico_City,America/New_York,Asia/Tokyo",
            mirrorFlip: false,
            mirrorZoom: 1,
        ])
    }

    static var defaults: UserDefaults { .standard }

    static func bool(_ key: String) -> Bool { defaults.bool(forKey: key) }
    static func double(_ key: String) -> Double { defaults.double(forKey: key) }
    static func int(_ key: String) -> Int { defaults.integer(forKey: key) }
    static func string(_ key: String) -> String? { defaults.string(forKey: key) }
}
