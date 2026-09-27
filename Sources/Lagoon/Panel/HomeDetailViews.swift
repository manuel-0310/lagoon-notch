import SwiftUI

// MARK: - 4h Reloj y zonas horarias

struct ClockDetailView: View {
    @Environment(AppState.self) var app
    @AppStorage(Prefs.worldClocks) private var worldClocks = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = AppEnvironment.fixedNow ?? context.date
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    BackLink { app.notch.back() }
                        .padding(.bottom, 6)
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(Formatters.time(now))
                            .lagoonFont(72, .thin)
                            .tracking(-2.88)
                        Text(":" + Formatters.formatter("ss").string(from: now))
                            .lagoonFont(24, .light)
                            .foregroundStyle(Palette.secondary)
                    }
                    .monospacedDigit()
                    .frame(height: 72)
                    Text(Formatters.longDate(now) + " · " + app.weather.localCityName)
                        .lagoonFont(13)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .stagger(1)

                VStack(spacing: 0) {
                    ForEach(WorldClock.parse(worldClocks), id: \.identifier) { zone in
                        WorldClockRow(zone: zone, now: now)
                    }
                }
                .frame(width: 240)
                .stagger(2)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

enum WorldClock {
    static func parse(_ raw: String) -> [TimeZone] {
        raw.split(separator: ",").compactMap { TimeZone(identifier: String($0).trimmingCharacters(in: .whitespaces)) }.prefix(3).map { $0 }
    }

    /// "Ciudad de México" a partir del identificador.
    static func cityName(_ zone: TimeZone) -> String {
        let known: [String: String] = [
            "America/Mexico_City": "Ciudad de México", "America/New_York": "Nueva York",
            "Asia/Tokyo": "Tokio", "Europe/London": "Londres", "Europe/Paris": "París",
            "Europe/Madrid": "Madrid", "America/Los_Angeles": "Los Ángeles", "America/Bogota": "Bogotá",
            "America/Argentina/Buenos_Aires": "Buenos Aires", "America/Sao_Paulo": "São Paulo",
            "America/Lima": "Lima", "America/Santiago": "Santiago", "America/Chicago": "Chicago",
            "Europe/Berlin": "Berlín", "Europe/Rome": "Roma", "Asia/Shanghai": "Shanghái",
            "Asia/Singapore": "Singapur", "Asia/Dubai": "Dubái", "Australia/Sydney": "Sídney",
            "America/Caracas": "Caracas", "America/Toronto": "Toronto", "Asia/Seoul": "Seúl",
        ]
        if let name = known[zone.identifier] { return name }
        return zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier
    }
}

struct WorldClockRow: View {
    let zone: TimeZone
    let now: Date

    var body: some View {
        let offsetHours = Double(zone.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)) / 3600
        let hour = Calendar.current.dateComponents(in: zone, from: now).hour ?? 12
        let isNight = hour < 7 || hour >= 20
        HStack(spacing: 10) {
            Icon(isNight ? .darkMode : .lightMode, size: 16, color: Palette.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(WorldClock.cityName(zone)).lagoonFont(13, .medium)
                Text(dayLabel(offsetHours: offsetHours))
                    .lagoonFont(11)
                    .foregroundStyle(Palette.secondary)
            }
            Spacer()
            Text(Formatters.time(now, timeZone: zone))
                .lagoonFont(20, .light)
                .monospacedDigit()
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.divider).frame(height: 1) }
    }

    private func dayLabel(offsetHours: Double) -> String {
        var calendar = Calendar.current
        let localDay = calendar.component(.day, from: now)
        calendar.timeZone = zone
        let zoneDay = calendar.component(.day, from: now)
        let day: String
        if zoneDay == localDay { day = "Hoy" } else if (now.addingTimeInterval(offsetHours * 3600) > now) { day = "Mañana" } else { day = "Ayer" }
        let value = offsetHours.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(abs(offsetHours)))
            : String(format: "%.1f", abs(offsetHours)).replacingOccurrences(of: ".", with: ",")
        let sign = offsetHours < 0 ? "−" : "+"
        return offsetHours == 0 ? "\(day) · misma hora" : "\(day) · \(sign)\(value) h"
    }
}

// MARK: - 4i Clima

struct WeatherDetailView: View {
    @Environment(AppState.self) var app

    var body: some View {
        let weather = app.weather
        Group {
            if let now = weather.current {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 0) {
                        BackLink { app.notch.back() }
                            .padding(.bottom, 6)
                        let symbol = WeatherService.symbol(code: now.code, isDay: now.isDay)
                        Icon(symbol.icon, size: 32, color: symbol.color)
                        Text(weather.format(now.temperature))
                            .lagoonFont(56, .thin)
                            .frame(height: 56)
                            .padding(.top, 4)
                        Text(WeatherService.description(code: now.code))
                            .lagoonFont(13, .medium)
                            .lineLimit(1)
                            .padding(.top, 6)
                        Text("\(weather.cityName) · Máx. \(weather.format(now.high)) Mín. \(weather.format(now.low))")
                            .lagoonFont(11)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                    }
                    .frame(width: 190, alignment: .leading)
                    .stagger(1)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("PRÓXIMAS HORAS").sectionLabel()
                        HStack {
                            ForEach(Array(weather.hours.prefix(6).enumerated()), id: \.offset) { index, hour in
                                if index > 0 { Spacer(minLength: 0) }
                                VStack(spacing: 6) {
                                    Text(index == 0 ? "Ahora" : hour.label)
                                        .lagoonFont(11)
                                        .foregroundStyle(Palette.secondary)
                                    let symbol = WeatherService.symbol(code: hour.code, isDay: hour.isDay)
                                    Icon(symbol.icon, size: 20, color: symbol.color)
                                    Text(weather.format(hour.temperature))
                                        .lagoonFont(13, .medium)
                                }
                            }
                        }
                        TimelineView(.everyMinute) { context in
                            Text("Open-Meteo · actualizado \(weather.updatedDescription(now: AppEnvironment.fixedNow ?? context.date))")
                                .lagoonFont(10)
                                .foregroundStyle(Color.white(0.35))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .stagger(2)
                }
                .frame(maxHeight: .infinity)
            } else if weather.state == .noLocation || weather.state == .choosingCity {
                WeatherNoLocationView()
            } else {
                VStack(spacing: 8) {
                    HStack { BackLink { app.notch.back() }; Spacer() }
                    Spacer()
                    if weather.state == .failed {
                        EmptyStateContent(icon: .cloud, title: "No se pudo cargar el clima",
                                          message: "Revisa tu conexión a internet.") {
                            PillButton(title: "Reintentar") { weather.refresh(force: true) }
                        }
                    } else {
                        ProgressView().controlSize(.small)
                        Text("Cargando clima…").lagoonFont(12).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                }
                .stagger(1)
            }
        }
        .onAppear { weather.refreshIfNeeded() }
    }
}

/// 5f · Clima sin ubicación (con buscador de ciudad).
struct WeatherNoLocationView: View {
    @Environment(AppState.self) var app
    @State private var query = ""
    @State private var results: [CityResult] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        let weather = app.weather
        if weather.state == .choosingCity {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    BackLink { weather.cancelChoosingCity() }
                    HStack(spacing: 6) {
                        Icon(.search, size: 15, color: .white(0.4))
                        TextField("", text: $query, prompt: Text("Busca una ciudad").foregroundStyle(Color.white(0.4)))
                            .textFieldStyle(.plain)
                            .lagoonFont(12)
                            .focused($focused)
                            .onChange(of: query) { _, value in search(value) }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.white(0.08)))
                }
                LagoonScrollView {
                    VStack(spacing: 0) {
                        ForEach(results) { city in
                            Button {
                                weather.choose(city)
                            } label: {
                                HStack {
                                    Icon(.pinDrop, size: 15, color: Palette.secondary)
                                    Text(city.name).lagoonFont(12.5)
                                    Text(city.region).lagoonFont(11).foregroundStyle(Palette.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle())
                            .overlay(alignment: .bottom) { Rectangle().fill(Palette.divider).frame(height: 1) }
                        }
                    }
                }
            }
            .onAppear { focused = true }
            .stagger(1)
        } else {
            EmptyStateContent(icon: .locationOff,
                              title: "Sin ubicación",
                              message: "Activa la ubicación o elige una ciudad para ver el clima.") {
                HStack(spacing: 6) {
                    PillButton(title: "Activar ubicación", style: .filled(Palette.cyan, text: .black)) {
                        weather.enableLocation()
                    }
                    PillButton(title: "Elegir ciudad") { weather.startChoosingCity() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) { BackLink { app.notch.back() } }
            .stagger(1)
        }
    }

    private func search(_ text: String) {
        searchTask?.cancel()
        let term = text.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else { results = []; return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let found = await WeatherService.searchCities(term)
            guard !Task.isCancelled else { return }
            await MainActor.run { results = found }
        }
    }
}

// MARK: - 4j Batería y dispositivos Bluetooth

struct BatteryDetailView: View {
    @Environment(AppState.self) var app

    var body: some View {
        let battery = app.battery
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                BackLink { app.notch.back() }
                    .padding(.bottom, 6)
                Text(battery.hasBattery ? "\(battery.level) %" : "—")
                    .lagoonFont(46, .light)
                    .tracking(-1.38)
                    .monospacedDigit()
                    .frame(height: 46)
                if battery.hasBattery {
                    BatteryGlyph(level: battery.fraction, color: battery.tint, width: 64, height: 28)
                        .padding(.top, 12)
                        .padding(.bottom, 10)
                }
                Text(battery.detailStatus)
                    .lagoonFont(12, .semibold)
                    .foregroundStyle(battery.isCharging || battery.isCharged ? Palette.green : .white)
                    .lineLimit(1)
                if let adapter = battery.adapterDescription {
                    Text(adapter)
                        .lagoonFont(11)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            .frame(width: 200, alignment: .leading)
            .stagger(1)

            VStack(alignment: .leading, spacing: 0) {
                Text("DISPOSITIVOS").sectionLabel()
                DeviceRow(icon: .laptopMac, name: app.bluetooth.macName, subtitle: "Este Mac",
                          level: battery.hasBattery ? battery.level : nil)
                ForEach(app.bluetooth.devices.prefix(3)) { device in
                    DeviceRow(icon: device.kind.icon, name: device.name, subtitle: device.detail, level: device.level)
                }
                if app.bluetooth.devices.isEmpty {
                    Text(app.bluetooth.isLoading ? "Buscando dispositivos…" : "No hay dispositivos Bluetooth con batería conectados.")
                        .lagoonFont(11)
                        .foregroundStyle(Palette.secondary)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .stagger(2)
        }
        .frame(maxHeight: .infinity)
        .onAppear { app.bluetooth.refresh() }
    }
}

struct DeviceRow: View {
    let icon: MS
    let name: String
    let subtitle: String
    let level: Int?

    var body: some View {
        HStack(spacing: 10) {
            Icon(icon, size: 16)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white(0.08)))
            VStack(alignment: .leading, spacing: 0) {
                Text(name).lagoonFont(12.5, .medium).lineLimit(1)
                Text(subtitle).lagoonFont(10.5).foregroundStyle(Palette.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let level {
                let low = level <= 20
                Text("\(level) %")
                    .lagoonFont(12, .semibold)
                    .monospacedDigit()
                    .foregroundStyle(low ? Palette.red : .white)
                ProgressBar(value: Double(level) / 100, color: low ? Palette.red : Palette.green,
                            track: .white(0.16), height: 4)
                    .frame(width: 36)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - 4k Volumen y brillo

struct SoundDetailView: View {
    @Environment(AppState.self) var app

    var body: some View {
        let audio = app.audio
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                BackLink { app.notch.back() }
                    .padding(.bottom, 6)
                LevelSlider(title: "Volumen",
                            icon: audio.isMuted || audio.volume <= 0.001 ? .volumeOff : .volumeUp,
                            value: audio.isMuted ? 0 : audio.volume) { audio.setVolume($0) }
                if audio.brightnessAvailable {
                    LevelSlider(title: "Brillo", icon: .lightMode, value: audio.brightness) { audio.setBrightness($0) }
                }
            }
            .frame(maxWidth: .infinity)
            .stagger(1)

            VStack(alignment: .leading, spacing: 4) {
                Text("SALIDA DE AUDIO").sectionLabel()
                Color.clear.frame(height: 4)
                LagoonScrollView {
                    VStack(spacing: 4) {
                        ForEach(audio.outputs) { output in
                            let selected = output.id == audio.currentOutputID
                            Button { audio.select(output) } label: {
                                HStack(spacing: 10) {
                                    Icon(output.kind.icon, size: 17, color: selected ? .white : Palette.secondary)
                                    Text(output.name).lagoonFont(12.5).lineLimit(1)
                                    Spacer(minLength: 0)
                                    if selected { Icon(.check, size: 16, color: Palette.cyan) }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.white(0.08) : .clear))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .frame(maxHeight: 128)
            }
            .frame(width: 220)
            .frame(maxHeight: .infinity)
            .stagger(2)
        }
        .onAppear { audio.refreshOutputs() }
    }
}

struct LevelSlider: View {
    let title: String
    let icon: MS
    let value: Double
    var onChange: (Double) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value * 100).rounded())) %").monospacedDigit()
            }
            .lagoonFont(12)
            .foregroundStyle(Palette.secondary)
            HStack(spacing: 10) {
                Icon(icon, size: 18)
                SliderBar(value: value, onChange: onChange)
            }
        }
    }
}
