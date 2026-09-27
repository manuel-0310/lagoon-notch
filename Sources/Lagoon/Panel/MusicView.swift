import SwiftUI

/// 4a · Música: el acento y el resplandor salen de la portada.
struct MusicView: View {
    @Environment(AppState.self) var app

    var body: some View {
        if app.music.track == nil {
            MusicEmptyView()
        } else {
            MusicPlayerView()
        }
    }
}

struct MusicPlayerView: View {
    @Environment(AppState.self) var app

    var body: some View {
        let music = app.music
        HStack(spacing: 18) {
            ArtworkView(image: music.artwork, size: 150, radius: 16, label: music.artwork == nil ? "portada" : nil)
                .id(music.track?.id ?? "")
                .transition(.artworkFlip)
                .stagger(1)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(music.track?.title ?? "")
                        .lagoonFont(18, .semibold)
                        .tracking(-0.18)
                        .lineLimit(1)
                    Text(music.subtitle)
                        .lagoonFont(13)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
                .stagger(2)

                MusicScrubber()
                    .stagger(3)

                HStack {
                    IconButton(icon: .shuffle, size: 18, color: music.shuffle ? music.accent : .white(0.55)) {
                        music.toggleShuffle()
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 20) {
                        IconButton(icon: .skipPrevious, size: 30) { music.previous() }
                        IconButton(icon: music.isPlaying ? .pause : .playArrow, size: 40) { music.playPause() }
                            .contentTransition(.opacity)
                        IconButton(icon: .skipNext, size: 30) { music.next() }
                    }
                    Spacer(minLength: 0)
                    IconButton(icon: .airplay, size: 18, color: .white(0.55)) {
                        app.notch.open(.sound)
                    }
                    .help("Salida de audio")
                }
                .stagger(4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Barra de progreso con pomo (arrastrable) y tiempos transcurrido/restante.
struct MusicScrubber: View {
    @Environment(AppState.self) var app
    @State private var dragValue: Double?

    var body: some View {
        let music = app.music
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let duration = music.track?.duration ?? 0
            let progress = dragValue ?? music.progress(at: context.date)
            let elapsed = progress * duration
            VStack(spacing: 7) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        ProgressBar(value: progress, color: music.accent, track: .white(0.16), height: 4)
                        Circle()
                            .fill(.white)
                            .frame(width: 12, height: 12)
                            .offset(x: proxy.size.width * progress - 6)
                    }
                    .frame(height: 12)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in dragValue = max(0, min(1, g.location.x / max(1, proxy.size.width))) }
                            .onEnded { _ in
                                if let value = dragValue { music.seek(to: value * duration) }
                                dragValue = nil
                            }
                    )
                }
                .frame(height: 12)
                HStack {
                    Text(Formatters.duration(elapsed))
                    Spacer()
                    Text("−" + Formatters.duration(max(0, duration - elapsed)))
                }
                .lagoonFont(11)
                .monospacedDigit()
                .foregroundStyle(Palette.secondary)
            }
        }
    }
}

/// 5a · Música · nada sonando.
struct MusicEmptyView: View {
    @Environment(AppState.self) var app

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                DashedBorder(radius: 16, color: .white(0.2))
                Icon(.musicNote, size: 40, color: .white(0.25))
            }
            .frame(width: 150, height: 150)
            .stagger(1)

            VStack(alignment: .leading, spacing: 6) {
                Text("Nada sonando").lagoonFont(18, .semibold)
                Text("Reproduce algo en Música o Spotify y aparecerá aquí con sus controles.")
                    .lagoonFont(13)
                    .foregroundStyle(Palette.secondary)
                    .lineSpacing(3)
                    .frame(maxWidth: 280, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    PillButton(title: "Abrir Música") { app.music.open(.music) }
                    PillButton(title: "Abrir Spotify") { app.music.open(.spotify) }
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .stagger(2)
        }
    }
}
