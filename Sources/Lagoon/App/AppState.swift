import AppKit
import Observation

/// Contenedor de todos los servicios y del estado del notch.
/// Solo se usa desde el hilo principal.
@Observable
final class AppState: @unchecked Sendable {
    let notch: NotchViewModel
    let music = NowPlayingService()
    let battery = BatteryService()
    let bluetooth = BluetoothService()
    let audio = AudioService()
    let calendar = CalendarService()
    let weather = WeatherService()
    let clipboard = ClipboardService()
    let tray = TrayService()
    let timers = TimerService()
    let camera = CameraService()
    let privacy = PrivacyService()
    let focus = FocusService()
    let system = SystemMonitorService()
    let shortcuts = ShortcutsService()
    let claude = ClaudeService()

    @ObservationIgnored let mediaKeys = MediaKeyTap()
    @ObservationIgnored var openSettings: () -> Void = {}
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?

    init(geometry: NotchGeometry = .preview) {
        notch = NotchViewModel(geometry: geometry)
        music.notch = notch
        battery.notch = notch
        bluetooth.notch = notch
        audio.notch = notch
        calendar.notch = notch
        clipboard.notch = notch
        tray.notch = notch
        timers.notch = notch
        privacy.notch = notch
        focus.notch = notch
        shortcuts.notch = notch
        claude.notch = notch
        privacy.ownCameraActive = { [unowned self] in self.camera.session.isRunning }
        notch.wingsProvider = { [unowned self] in self.computeWings() }
    }

    func startServices() {
        battery.start()
        music.start()
        audio.start()
        timers.start()
        tray.start()
        clipboard.start()
        calendar.start()
        bluetooth.start()
        privacy.start()
        focus.start()
        claude.start()
        configureMediaKeys()
        observeWings()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.configureMediaKeys()
            self?.privacy.applyScreenPreference()
            self?.notch.refresh()
        }
        notch.refresh(animated: false)
    }

    // MARK: - Alas en estado continuo

    /// Izquierda música; derecha la actividad de mayor prioridad
    /// (timer > cronómetro > Claude Code trabajando > carga). Los puntos de privacidad se dibujan
    /// encima de cualquier ala; si no hay nada más, tienen su propia ala.
    func computeWings() -> WingContent? {
        let musicOn = Prefs.bool(Prefs.showMusicWings) && music.isPlaying && music.track != nil
        var secondary: WingContent.Secondary?
        if timers.isCountdownRunning {
            secondary = timers.activeKind == .pomodoro ? .pomodoro : .timer
        } else if timers.isStopwatchRunning {
            secondary = .stopwatch
        } else if Prefs.bool(Prefs.claudeWings) && claude.isWorking {
            secondary = .claude
        } else if Prefs.bool(Prefs.showChargingWings) && battery.isCharging {
            secondary = .charging
        }
        switch (musicOn, secondary) {
        case (true, let secondary?): return .musicPlus(secondary)
        case (true, nil): return .music
        case (false, .timer?): return .timer
        case (false, .pomodoro?): return .pomodoro
        case (false, .stopwatch?): return .stopwatch
        case (false, .charging?): return .charging
        case (false, .claude?): return .claude
        case (false, nil): return privacy.activeKinds.isEmpty ? nil : .privacy
        }
    }

    private func observeWings() {
        withObservationTracking {
            _ = computeWings()
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.notch.refresh()
                self.observeWings()
            }
        }
    }

    // MARK: - Teclas de volumen y brillo

    func configureMediaKeys() {
        let wanted = Prefs.bool(Prefs.replaceSystemHUD) && MediaKeyTap.isTrusted
        if wanted, !mediaKeys.isRunning {
            mediaKeys.handler = { [weak self] key, isDown, fine in
                guard let self else { return false }
                switch key {
                case .soundUp, .soundDown, .mute:
                    guard let device = AudioService.defaultOutputDevice(), AudioService.canSetVolume(device) else { return false }
                    if isDown { _ = self.audio.handleVolumeKey(key, fine: fine) }
                    return true
                case .brightnessUp, .brightnessDown:
                    guard self.audio.canControlBrightness else { return false }
                    if isDown { _ = self.audio.handleBrightnessKey(key, fine: fine) }
                    return true
                }
            }
            mediaKeys.start()
        } else if !wanted, mediaKeys.isRunning {
            mediaKeys.stop()
        }
    }
}
