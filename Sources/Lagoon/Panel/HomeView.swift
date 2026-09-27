import SwiftUI

/// 3a · Inicio: música, reloj, clima, próximo evento y batería.
struct HomeView: View {
    @Environment(AppState.self) var app

    var body: some View {
        HStack(spacing: 18) {
            HomeMusicCard()
                .frame(width: 200)
                .stagger(1)
            ClockWeatherColumn()
                .frame(maxWidth: .infinity, alignment: .leading)
                .stagger(2)
            VStack(spacing: 8) {
                NextEventCard()
                    .frame(maxHeight: .infinity)
                HomeBatteryCard()
            }
            .frame(width: 150)
            .stagger(3)
        }
        .onAppear {
            app.weather.refreshIfNeeded()
            app.calendar.requestAccessIfNeeded()
        }
    }
}

// MARK: - Música

struct HomeMusicCard: View {
    @Environment(AppState.self) var app

    var body: some View {
        let music = app.music
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ArtworkView(image: music.artwork, size: 46, radius: 10)
                    .id(music.track?.id ?? "")
                    .transition(.artworkFlip)
                VStack(alignment: .leading, spacing: 0) {
                    Text(music.track?.title ?? "Nada sonando")
                        .lagoonFont(13, .semibold)
                    Text(music.track?.artist ?? "Abre Música o Spotify")
                        .lagoonFont(12)
                        .foregroundStyle(Palette.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { app.notch.select(.music) }
            Spacer(minLength: 0)
            MusicProgressLine()
                .padding(.top, 14)
            Spacer(minLength: 0)
            HStack(spacing: 18) {
                IconButton(icon: .skipPrevious, size: 22) { music.previous() }
                IconButton(icon: music.isPlaying ? .pause : .playArrow, size: 28) { music.playPause() }
                IconButton(icon: .skipNext, size: 22) { music.next() }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .disabled(music.track == nil)
            .opacity(music.track == nil ? 0.35 : 1)
        }
        .frame(maxHeight: .infinity)
        .card()
    }
}

/// Barra de progreso fina (4 pt) con el acento de la portada.
struct MusicProgressLine: View {
    @Environment(AppState.self) var app

    var body: some View {
        let music = app.music
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ProgressBar(value: music.progress(at: context.date), color: music.accent, track: .white(0.16), height: 4)
        }
    }
}

// MARK: - Reloj y clima

struct ClockWeatherColumn: View {
    @Environment(AppState.self) var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { app.notch.open(.clock) } label: {
                TimelineView(.everyMinute) { context in
                    let now = AppEnvironment.fixedNow ?? context.date
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Formatters.time(now))
                            .lagoonFont(50, .light)
                            .tracking(-1.5)
                            .monospacedDigit()
                            .frame(height: 50)
                        Text(Formatters.longDate(now))
                            .lagoonFont(12)
                            .foregroundStyle(Palette.secondary)
                            .padding(.top, 6)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())

            Spacer(minLength: 0)

            Button { app.notch.open(.weather) } label: {
                HomeWeatherRow()
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.vertical, 4)
        .frame(maxHeight: .infinity, alignment: .leading)
    }
}

struct HomeWeatherRow: View {
    @Environment(AppState.self) var app

    var body: some View {
        let weather = app.weather
        HStack(spacing: 8) {
            if let now = weather.current {
                let symbol = WeatherService.symbol(code: now.code, isDay: now.isDay)
                Icon(symbol.icon, size: 24, color: symbol.color)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(weather.format(now.temperature)) \(weather.cityName)")
                        .lagoonFont(13, .semibold)
                        .lineLimit(1)
                    Text("Máx. \(weather.format(now.high)) · Mín. \(weather.format(now.low))")
                        .lagoonFont(11)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
            } else {
                Icon(weather.state == .noLocation ? .locationOff : .cloud, size: 24, color: .white(0.35))
                VStack(alignment: .leading, spacing: 0) {
                    Text(weather.state == .loading ? "Cargando clima…" : "Clima")
                        .lagoonFont(13, .semibold)
                    Text(weather.state == .noLocation ? "Elige una ciudad" : "Toca para ver")
                        .lagoonFont(11)
                        .foregroundStyle(Palette.secondary)
                }
            }
        }
    }
}

// MARK: - Próximo evento

struct NextEventCard: View {
    @Environment(AppState.self) var app

    var body: some View {
        let calendar = app.calendar
        VStack(alignment: .leading, spacing: 0) {
            Text("PRÓXIMO").sectionLabel()
            if let event = calendar.nextEvent {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.blue)
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(event.title)
                            .lagoonFont(12, .semibold)
                            .lineLimit(1)
                        TimelineView(.everyMinute) { context in
                            Text(event.relativeDescription(now: AppEnvironment.fixedNow ?? context.date))
                                .lagoonFont(11)
                                .foregroundStyle(Palette.blue)
                                .padding(.top, 2)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            } else {
                Text(calendar.eventsAccess == .granted ? "Nada más hoy" : "Conecta tu calendario")
                    .lagoonFont(12, .semibold)
                    .padding(.top, 6)
                Text(calendar.eventsAccess == .granted ? "Día libre" : "Toca para permitir")
                    .lagoonFont(11)
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: 10)
        .contentShape(Rectangle())
        .onTapGesture { app.notch.select(.calendar) }
    }
}

// MARK: - Batería

struct HomeBatteryCard: View {
    @Environment(AppState.self) var app

    var body: some View {
        let battery = app.battery
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(battery.hasBattery ? "\(battery.level) %" : "Corriente")
                    .lagoonFont(15, .semibold)
                    .monospacedDigit()
                Text(battery.shortStatus)
                    .lagoonFont(11)
                    .foregroundStyle(battery.isCharging || battery.isCharged ? Palette.green : Palette.secondary)
            }
            Spacer(minLength: 0)
            if battery.hasBattery {
                BatteryGlyph(level: battery.fraction, color: battery.tint, width: 26, height: 13)
            }
        }
        .card(padding: 10)
        .contentShape(Rectangle())
        .onTapGesture { app.notch.open(.battery) }
    }
}
