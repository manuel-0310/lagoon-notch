import AppKit
import ImageIO
import Observation
import SwiftUI

/// App que está sonando (Música, Spotify, Chrome, Podcasts…).
struct MusicSource: Equatable, Hashable {
    var bundleID: String

    static let music = MusicSource(bundleID: "com.apple.Music")
    static let spotify = MusicSource(bundleID: "com.spotify.client")

    /// Identificador corto para los IDs de pista.
    var rawValue: String { bundleID }

    /// Nombre para AppleScript (solo Música y Spotify se controlan así).
    var scriptName: String {
        switch self {
        case .music: return "Music"
        case .spotify: return "Spotify"
        default: return ""
        }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static var names: [String: String] = [:]
    private static var icons: [String: NSImage] = [:]

    /// Nombre visible de la app ("Google Chrome").
    var displayName: String {
        if let cached = Self.names[bundleID] { return cached }
        var name = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        Self.names[bundleID] = name
        return name
    }

    var icon: NSImage? {
        if let cached = Self.icons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        Self.icons[bundleID] = image
        return image
    }
}

struct Track: Equatable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var source: MusicSource
}

/// Canción actual de cualquier app (Música, Spotify, navegadores, Podcasts…).
///
/// Camino principal: `MediaRemoteBridge`, que recibe los cambios del sistema en un proceso vivo.
/// Respaldo (si el adaptador no funciona o se eligió "solo Música y Spotify"): las notificaciones
/// distribuidas de Música y Spotify, con AppleScript para la portada, la posición y los controles.
/// En ningún caso hay sondeo.
@Observable
final class NowPlayingService {
    var track: Track?
    var artwork: NSImage?
    var isPlaying = false
    var shuffle = false
    /// Acento que sale de la portada (rosa por defecto).
    var accent: Color = Palette.pink
    var accentNS: NSColor = .lagoonPink
    var glow: Color = Palette.pinkGlow
    var positionAnchor: Double = 0
    var anchorDate = Date()

    @ObservationIgnored weak var notch: NotchViewModel?
    @ObservationIgnored private let scriptQueue = DispatchQueue(label: "app.lagoon.applescript", qos: .userInitiated)
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var pendingTrackID: String?
    /// "Ahora suena" solo aparece la primera vez que suena música en la sesión.
    @ObservationIgnored private var announcedThisSession = false
    @ObservationIgnored private let bridge = MediaRemoteBridge()
    /// true mientras el adaptador de MediaRemote es la fuente de datos.
    @ObservationIgnored private(set) var usingAdapter = false
    @ObservationIgnored private var legacyStarted = false
    @ObservationIgnored private var adapterArtworkKey: String?
    @ObservationIgnored private var adapterFirstUpdate = true

    var subtitle: String {
        guard let track else { return "" }
        return [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    func position(at date: Date) -> Double {
        guard let track else { return 0 }
        let raw = isPlaying ? positionAnchor + date.timeIntervalSince(anchorDate) : positionAnchor
        if track.duration > 0 { return min(max(0, raw), track.duration) }
        return max(0, raw)
    }

    func progress(at date: Date) -> Double {
        guard let duration = track?.duration, duration > 0 else { return 0 }
        return position(at: date) / duration
    }

    // MARK: - Ciclo de vida

    func start() {
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == self.track?.source.bundleID else { return }
            self.clear()
        })

        guard Prefs.bool(Prefs.musicAllApps), MediaRemoteBridge.paths != nil else {
            startLegacy()
            return
        }
        bridge.onUpdate = { [weak self] info in self?.applyAdapter(info) }
        bridge.onFailure = { [weak self] in self?.fallBackToLegacy() }
        MediaRemoteBridge.test { [weak self] works in
            guard let self else { return }
            if works {
                self.usingAdapter = true
                self.bridge.start()
            } else {
                self.startLegacy()
            }
        }
    }

    func stop() {
        bridge.stop()
    }

    private func fallBackToLegacy() {
        usingAdapter = false
        bridge.stop()
        startLegacy()
    }

    /// Solo Música y Spotify, por notificaciones distribuidas y AppleScript.
    private func startLegacy() {
        guard !legacyStarted else { return }
        legacyStarted = true
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: Notification.Name("com.apple.Music.playerInfo"),
                                            object: nil, queue: .main) { [weak self] note in
            self?.handleMusic(note.userInfo ?? [:])
        })
        observers.append(center.addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
                                            object: nil, queue: .main) { [weak self] note in
            self?.handleSpotify(note.userInfo ?? [:])
        })

        // Estado inicial si alguna app ya está sonando.
        for source in [MusicSource.spotify, .music] where source.isRunning {
            queryState(source)
        }
    }

    // MARK: - Notificaciones

    private func handleMusic(_ info: [AnyHashable: Any]) {
        let state = info["Player State"] as? String ?? ""
        let totalMs = (info["Total Time"] as? NSNumber)?.doubleValue ?? 0
        let persistent = (info["PersistentID"] as? NSNumber)?.stringValue
        apply(source: .music,
              state: state,
              title: info["Name"] as? String,
              artist: info["Artist"] as? String ?? "",
              album: info["Album"] as? String ?? "",
              duration: totalMs / 1000,
              position: nil,
              id: persistent.map { "music-\($0)" })
    }

    private func handleSpotify(_ info: [AnyHashable: Any]) {
        let state = info["Player State"] as? String ?? ""
        let durationMs = (info["Duration"] as? NSNumber)?.doubleValue ?? 0
        let position = (info["Playback Position"] as? NSNumber)?.doubleValue
        apply(source: .spotify,
              state: state,
              title: info["Name"] as? String,
              artist: info["Artist"] as? String ?? "",
              album: info["Album"] as? String ?? "",
              duration: durationMs / 1000,
              position: position,
              id: info["Track ID"] as? String)
    }

    private func apply(source: MusicSource, state: String, title: String?, artist: String, album: String,
                       duration: Double, position: Double?, id: String?) {
        let playing = state == "Playing"
        if state == "Stopped" {
            if track == nil || track?.source == source { clear() }
            return
        }
        guard let title, !title.isEmpty else { return }
        // Si otra app está sonando y esta solo se pausó, no le quitamos el sitio.
        if let current = track, current.source != source, isPlaying, !playing { return }

        let trackID = id ?? "\(source.rawValue)|\(title)|\(artist)|\(album)"
        let newTrack = Track(id: trackID, title: title, artist: artist, album: album,
                             duration: duration, source: source)

        if track?.id == trackID {
            if track != newTrack { track = newTrack }
            isPlaying = playing
            if playing { announceIfFirstPlay(trackID) }
            if let position {
                positionAnchor = position
                anchorDate = Date()
            } else {
                positionAnchor = self.position(at: Date())
                anchorDate = Date()
                requestPosition(source)
            }
            return
        }

        // Pista nueva: primero la portada (para girarla ya con la imagen), con un tope de 1 s.
        pendingTrackID = trackID
        var committed = false
        let commit: (NSImage?) -> Void = { [weak self] image in
            guard let self, !committed, self.pendingTrackID == trackID else { return }
            committed = true
            self.commitTrack(newTrack, artwork: image, playing: playing, position: position ?? 0)
        }
        fetchArtwork(source) { image in commit(image) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { commit(nil) }
    }

    private func commitTrack(_ newTrack: Track, artwork image: NSImage?, playing: Bool, position: Double) {
        let colors = image.flatMap(ArtworkColors.extract) ?? ArtworkColors.default
        withAnimation(Motion.songChange) {
            track = newTrack
            artwork = image
            accent = Color(nsColor: colors.accent)
            glow = Color(nsColor: colors.glow)
        }
        accentNS = colors.accent
        isPlaying = playing
        positionAnchor = position
        anchorDate = Date()
        if playing { announceIfFirstPlay(newTrack.id) }
        guard !usingAdapter else { return }
        if position == 0 { requestPosition(newTrack.source) }
        requestShuffle(newTrack.source)
        // Si la portada no llegó a tiempo, se reintenta en segundo plano.
        if image == nil {
            fetchArtwork(newTrack.source) { [weak self] late in
                guard let self, let late, self.track?.id == newTrack.id else { return }
                let colors = ArtworkColors.extract(late) ?? ArtworkColors.default
                withAnimation(Motion.songChange) {
                    self.artwork = late
                    self.accent = Color(nsColor: colors.accent)
                    self.glow = Color(nsColor: colors.glow)
                }
                self.accentNS = colors.accent
            }
        }
    }

    // MARK: - Adaptador de MediaRemote

    private func applyAdapter(_ info: [String: Any]) {
        guard let title = info["title"] as? String, !title.isEmpty,
              let bundle = (info["parentApplicationBundleIdentifier"] as? String)
                ?? (info["bundleIdentifier"] as? String) else {
            if track != nil { clear() }
            return
        }
        let source = MusicSource(bundleID: bundle)
        defer { adapterFirstUpdate = false }
        let playing = (info["playing"] as? Bool) ?? ((info["playbackRate"] as? NSNumber)?.doubleValue ?? 0 > 0)
        let artist = info["artist"] as? String ?? ""
        let album = info["album"] as? String ?? ""
        let duration = ((info["durationMicros"] as? NSNumber)?.doubleValue ?? 0) / 1_000_000
        let elapsed = ((info["elapsedTimeMicros"] as? NSNumber)?.doubleValue).map { $0 / 1_000_000 }
        let stamp = ((info["timestampEpochMicros"] as? NSNumber)?.doubleValue).map { Date(timeIntervalSince1970: $0 / 1_000_000) }
        let uniqueID = (info["uniqueIdentifier"] as? NSNumber)?.stringValue
            ?? (info["uniqueIdentifier"] as? String)
            ?? (info["contentItemIdentifier"] as? String)
        let trackID = "\(bundle)|" + (uniqueID ?? "\(title)|\(artist)|\(album)")
        let newTrack = Track(id: trackID, title: title, artist: artist, album: album,
                             duration: duration, source: source)
        if let mode = (info["shuffleMode"] as? NSNumber)?.intValue { shuffle = mode >= 2 }

        // Posición: `elapsed` es la de `stamp`; mientras suena avanza sola.
        let anchor: (Double, Date)? = elapsed.map { ($0, stamp ?? Date()) }

        // Portada (llega en base64, a veces un poco después que el resto).
        var image: NSImage?
        let artworkKey = (info["artworkData"] as? String).map { "\(trackID)#\($0.count)" }
        if let base64 = info["artworkData"] as? String, artworkKey != adapterArtworkKey,
           let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) {
            image = Self.artworkImage(data)
        }

        if track?.id == trackID {
            if track != newTrack { track = newTrack }
            isPlaying = playing
            if let anchor {
                positionAnchor = anchor.0
                anchorDate = anchor.1
            }
            if let image {
                adapterArtworkKey = artworkKey
                let colors = ArtworkColors.extract(image) ?? ArtworkColors.default
                withAnimation(Motion.songChange) {
                    artwork = image
                    accent = Color(nsColor: colors.accent)
                    glow = Color(nsColor: colors.glow)
                }
                accentNS = colors.accent
            }
            if playing { announceIfFirstPlay(trackID) }
            return
        }

        // Si ya sonaba algo al abrir Lagoon, no se anuncia.
        if adapterFirstUpdate, playing { announcedThisSession = true }
        pendingTrackID = nil
        adapterArtworkKey = image == nil ? nil : artworkKey
        commitTrack(newTrack, artwork: image, playing: playing, position: anchor?.0 ?? 0)
        if let anchor { anchorDate = anchor.1 }
    }

    private func announceIfFirstPlay(_ trackID: String) {
        guard !announcedThisSession else { return }
        announcedThisSession = true
        if Prefs.bool(Prefs.showSongChange) {
            notch?.post(.songChange(trackID: trackID))
        }
    }

    private func clear() {
        pendingTrackID = nil
        withAnimation(Motion.songChange) {
            track = nil
            artwork = nil
            isPlaying = false
            accent = Palette.pink
            glow = Palette.pinkGlow
        }
        accentNS = .lagoonPink
        notch?.dismiss { if case .songChange = $0 { return true } else { return false } }
    }

    // MARK: - Controles

    func playPause() {
        guard let source = track?.source else { return }
        positionAnchor = position(at: Date())
        anchorDate = Date()
        isPlaying.toggle()
        if usingAdapter { return bridge.send(.togglePlayPause) }
        run("tell application \"\(source.scriptName)\" to playpause")
    }

    func next() {
        guard let source = track?.source else { return }
        if usingAdapter { return bridge.send(.next) }
        run("tell application \"\(source.scriptName)\" to next track")
    }

    func previous() {
        guard let source = track?.source else { return }
        if usingAdapter { return bridge.send(.previous) }
        run("tell application \"\(source.scriptName)\" to previous track")
    }

    func toggleShuffle() {
        guard let source = track?.source else { return }
        shuffle.toggle()
        if usingAdapter { return bridge.setShuffle(shuffle) }
        let property = source == .music ? "shuffle enabled" : "shuffling"
        run("tell application \"\(source.scriptName)\" to set \(property) to \(shuffle ? "true" : "false")")
    }

    func seek(to seconds: Double) {
        guard let source = track?.source else { return }
        positionAnchor = seconds
        anchorDate = Date()
        if usingAdapter { return bridge.seek(to: seconds) }
        run("tell application \"\(source.scriptName)\" to set player position to \(String(format: "%.2f", seconds))")
    }

    func open(_ source: MusicSource) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) else {
            if source == .spotify, let web = URL(string: "https://open.spotify.com") { NSWorkspace.shared.open(web) }
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - AppleScript

    private func queryState(_ source: MusicSource) {
        let script = """
        tell application "\(source.scriptName)"
            set st to player state as string
            if st is "stopped" then return {st}
            set t to current track
            return {st, name of t, artist of t, album of t, duration of t, player position}
        end tell
        """
        run(script) { [weak self] result in
            guard let self, let result, result.numberOfItems >= 6 else { return }
            let state = result.atIndex(1)?.stringValue ?? ""
            let title = result.atIndex(2)?.stringValue
            let artist = result.atIndex(3)?.stringValue ?? ""
            let album = result.atIndex(4)?.stringValue ?? ""
            var duration = result.atIndex(5)?.doubleValue ?? 0
            if source == .spotify { duration /= 1000 }
            let position = result.atIndex(6)?.doubleValue ?? 0
            let normalized = state.lowercased() == "playing" ? "Playing" : "Paused"
            if normalized == "Paused", self.track != nil { return }
            if normalized == "Playing" { self.announcedThisSession = true }
            self.apply(source: source, state: normalized, title: title, artist: artist, album: album,
                       duration: duration, position: position, id: nil)
        }
    }

    private func requestPosition(_ source: MusicSource) {
        run("tell application \"\(source.scriptName)\" to get player position") { [weak self] result in
            guard let self, let value = result?.doubleValue, self.track?.source == source else { return }
            self.positionAnchor = value
            self.anchorDate = Date()
        }
    }

    private func requestShuffle(_ source: MusicSource) {
        let property = source == .music ? "shuffle enabled" : "shuffling"
        run("tell application \"\(source.scriptName)\" to get \(property)") { [weak self] result in
            guard let self, let result else { return }
            self.shuffle = result.booleanValue
        }
    }

    private func fetchArtwork(_ source: MusicSource, completion: @escaping (NSImage?) -> Void) {
        switch source {
        case .music:
            run("tell application \"Music\" to get raw data of artwork 1 of current track") { result in
                guard let data = result?.data else {
                    completion(nil)
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    let image = Self.artworkImage(data)
                    DispatchQueue.main.async { completion(image) }
                }
            }
        case .spotify:
            run("tell application \"Spotify\" to get artwork url of current track") { result in
                guard let string = result?.stringValue, let url = URL(string: string) else {
                    completion(nil)
                    return
                }
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    let image = data.flatMap(Self.artworkImage)
                    DispatchQueue.main.async { completion(image) }
                }.resume()
            }
        default:
            completion(nil)
        }
    }

    /// La portada se muestra como mucho a 150 pt: se decodifica a 320 px en vez de guardar
    /// en memoria la original (Música puede entregar imágenes de varios miles de píxeles).
    private static func artworkImage(_ data: Data) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 320,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(data: data)
        }
        return NSImage(cgImage: cg, size: .zero)
    }

    /// Ejecuta AppleScript en una cola serie (nunca en el hilo principal).
    private func run(_ source: String, completion: ((NSAppleEventDescriptor?) -> Void)? = nil) {
        scriptQueue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let value = error == nil ? result : nil
            if let completion {
                DispatchQueue.main.async { completion(value) }
            }
        }
    }
}

/// Color de acento y resplandor a partir de la portada.
enum ArtworkColors {
    struct Pair {
        let accent: NSColor
        let glow: NSColor
    }

    static let `default` = Pair(accent: .lagoonPink,
                                glow: NSColor(srgbRed: 0xC9 / 255, green: 0x53 / 255, blue: 0x68 / 255, alpha: 1))

    static func extract(_ image: NSImage) -> Pair? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 12
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        // Media ponderada por saturación: favorece los colores vivos de la portada.
        var r = 0.0, g = 0.0, b = 0.0, total = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let pr = Double(pixels[i]) / 255, pg = Double(pixels[i + 1]) / 255, pb = Double(pixels[i + 2]) / 255
            let maxC = max(pr, pg, pb), minC = min(pr, pg, pb)
            let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
            let weight = 0.05 + saturation * saturation * (0.3 + maxC)
            r += pr * weight; g += pg * weight; b += pb * weight; total += weight
        }
        guard total > 0 else { return nil }
        let average = NSColor(srgbRed: r / total, green: g / total, blue: b / total, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.usingColorSpace(.sRGB)?.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        if saturation < 0.08 {
            // Portada en blanco y negro: acento neutro.
            return Pair(accent: NSColor(white: 0.9, alpha: 1), glow: NSColor(white: 0.55, alpha: 1))
        }
        // Legible sobre negro: brillante y moderadamente saturado (como el rosa por defecto).
        let accent = NSColor(hue: hue, saturation: min(0.62, max(0.36, saturation * 1.1)), brightness: 1, alpha: 1)
        let glow = NSColor(hue: hue, saturation: min(0.75, max(0.5, saturation + 0.2)), brightness: 0.8, alpha: 1)
        return Pair(accent: accent, glow: glow)
    }
}
