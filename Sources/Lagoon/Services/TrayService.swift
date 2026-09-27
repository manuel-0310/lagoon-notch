import AppKit
import Observation
import QuickLookThumbnailing
import SwiftUI

struct TrayItem: Identifiable, Equatable, Codable {
    var id = UUID()
    var url: URL
    var name: String
    var size: Int64
    var added: Date

    /// "PDF", "HEIC"…
    var typeLabel: String {
        let ext = url.pathExtension.uppercased()
        if ext.isEmpty { return url.hasDirectoryPath ? "CARPETA" : "ARCHIVO" }
        return ext
    }
}

/// Bandeja temporal de archivos: guarda referencias (no copia nada) y se vacía sola.
@Observable
final class TrayService {
    var items: [TrayItem] = []
    var thumbnails: [UUID: NSImage] = [:]
    var expiresAt: Date?

    @ObservationIgnored weak var notch: NotchViewModel?
    /// Un archivo de la bandeja se está arrastrando hacia fuera (no abrir el modo "soltar").
    @ObservationIgnored var isDraggingOut = false
    @ObservationIgnored private var expiryTimer: Timer?
    @ObservationIgnored private var loadingThumbnails = Set<UUID>()
    @ObservationIgnored private let storeKey = "trayItems"
    @ObservationIgnored private let expiryKey = "trayExpiresAt"

    var countDescription: String {
        items.count == 1 ? "1 archivo" : "\(items.count) archivos"
    }

    /// "3 archivos · se vacía en 58 min"
    func headerDescription(now: Date) -> String {
        guard let expiresAt else { return countDescription }
        let minutes = max(1, Int((expiresAt.timeIntervalSince(now) / 60).rounded(.up)))
        let remaining = minutes >= 60 ? Formatters.hoursMinutes(minutes) : "\(minutes) min"
        return "\(countDescription) · se vacía en \(remaining)"
    }

    func start() {
        load()
        scheduleExpiry()
    }

    // MARK: - Añadir y quitar

    func add(providers: [NSItemProvider], completion: @escaping (Int) -> Void) {
        FileDrop.loadURLs(from: providers) { [weak self] urls in
            let added = self?.add(urls: urls) ?? 0
            completion(added)
        }
    }

    @discardableResult
    func add(urls: [URL]) -> Int {
        var added = 0
        var list = items
        for url in urls where !list.contains(where: { $0.url.path == url.path }) {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey])
            let size = Int64(values?.fileSize ?? values?.totalFileAllocatedSize ?? 0)
            list.append(TrayItem(url: url, name: url.lastPathComponent, size: size, added: Date()))
            added += 1
        }
        guard added > 0 else { return 0 }
        withAnimation(Motion.activityIn) { items = list }
        let lifetime = TimeInterval(max(5, Prefs.int(Prefs.trayLifetimeMinutes)) * 60)
        expiresAt = Date().addingTimeInterval(lifetime)
        save()
        scheduleExpiry()
        return added
    }

    func remove(_ item: TrayItem) {
        items.removeAll { $0.id == item.id }
        thumbnails[item.id] = nil
        if items.isEmpty { expiresAt = nil }
        save()
    }

    func clear() {
        items.removeAll()
        thumbnails.removeAll()
        expiresAt = nil
        save()
        scheduleExpiry()
    }

    // MARK: - Miniaturas (Quick Look, bajo demanda)

    func loadThumbnail(for item: TrayItem) {
        guard thumbnails[item.id] == nil, !loadingThumbnails.contains(item.id), !AppEnvironment.isSnapshot else { return }
        loadingThumbnails.insert(item.id)
        let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 100, height: 72),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2,
                                                   representationTypes: .all)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            let image = representation?.nsImage
            DispatchQueue.main.async {
                guard let self else { return }
                self.loadingThumbnails.remove(item.id)
                if let image { self.thumbnails[item.id] = image }
            }
        }
    }

    // MARK: - Caducidad y persistencia

    private func scheduleExpiry() {
        expiryTimer?.invalidate()
        guard let expiresAt else { return }
        let timer = Timer(fire: expiresAt, interval: 0, repeats: false) { [weak self] _ in
            withAnimation(Motion.activityOut) { self?.clear() }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
    }

    private func save() {
        let defaults = Prefs.defaults
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: storeKey) }
        defaults.set(expiresAt, forKey: expiryKey)
    }

    private func load() {
        let defaults = Prefs.defaults
        guard let expiry = defaults.object(forKey: expiryKey) as? Date, expiry > Date(),
              let data = defaults.data(forKey: storeKey),
              let decoded = try? JSONDecoder().decode([TrayItem].self, from: data) else {
            items = []
            expiresAt = nil
            return
        }
        items = decoded.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        expiresAt = items.isEmpty ? nil : expiry
    }
}
