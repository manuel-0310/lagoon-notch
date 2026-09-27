import AppKit
import Observation
import UniformTypeIdentifiers

struct FavoriteApp: Codable, Identifiable, Equatable {
    var path: String
    var name: String
    var id: String { path }
}

/// Atajos de la app Atajos y apps favoritas para la pestaña Atajos.
///
/// La lista de atajos se pide a `/usr/bin/shortcuts list` solo al abrir la pestaña, y cada atajo
/// se ejecuta con `shortcuts run` en segundo plano.
@Observable
final class ShortcutsService {
    var available: [String] = []
    var favorites: [String] = []
    var apps: [FavoriteApp] = []
    var running: Set<String> = []
    var isLoadingList = false

    @ObservationIgnored weak var notch: NotchViewModel?
    @ObservationIgnored private var iconCache: [String: NSImage] = [:]
    @ObservationIgnored private let queue = DispatchQueue(label: "app.lagoon.shortcuts", qos: .userInitiated)
    @ObservationIgnored private var listLoadedAt: Date?

    static let tool = "/usr/bin/shortcuts"

    init() {
        favorites = Self.decode([String].self, key: Prefs.favoriteShortcuts) ?? []
        apps = Self.decode([FavoriteApp].self, key: Prefs.favoriteApps) ?? []
    }

    var isEmpty: Bool { favorites.isEmpty && apps.isEmpty }

    // MARK: - Lista de atajos

    /// Se llama al abrir la pestaña; como mucho una vez por minuto.
    func refreshAvailableIfNeeded() {
        guard !AppEnvironment.isSnapshot, !isLoadingList else { return }
        if let listLoadedAt, Date().timeIntervalSince(listLoadedAt) < 60 { return }
        isLoadingList = true
        queue.async { [weak self] in
            let output = Self.execute(arguments: ["list"]).output
            let names = output.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            DispatchQueue.main.async {
                guard let self else { return }
                self.available = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                self.isLoadingList = false
                self.listLoadedAt = Date()
            }
        }
    }

    // MARK: - Favoritos

    func addShortcut(_ name: String) {
        guard !favorites.contains(name) else { return }
        favorites.append(name)
        save()
    }

    func removeShortcut(_ name: String) {
        favorites.removeAll { $0 == name }
        save()
    }

    @discardableResult
    func addApps(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls where url.pathExtension == "app" {
            guard !apps.contains(where: { $0.path == url.path }) else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            apps.append(FavoriteApp(path: url.path, name: name))
            added += 1
        }
        if added > 0 { save() }
        return added
    }

    func removeApp(_ app: FavoriteApp) {
        apps.removeAll { $0.id == app.id }
        save()
    }

    /// Selector de apps (carpeta Aplicaciones).
    func chooseApps() {
        let panel = NSOpenPanel()
        panel.title = "Elige apps para la pestaña Atajos"
        panel.prompt = "Añadir"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            self?.addApps(panel.urls)
        }
    }

    private func save() {
        Self.encode(favorites, key: Prefs.favoriteShortcuts)
        Self.encode(apps, key: Prefs.favoriteApps)
    }

    // MARK: - Ejecutar

    func run(_ name: String) {
        guard !running.contains(name) else { return }
        running.insert(name)
        queue.async { [weak self] in
            let ok = Self.execute(arguments: ["run", name]).status == 0
            DispatchQueue.main.async {
                guard let self else { return }
                self.running.remove(name)
                self.notch?.post(.shortcutRan(name: name, ok: ok))
            }
        }
    }

    func launch(_ app: FavoriteApp) {
        let url = URL(fileURLWithPath: app.path)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        notch?.collapse()
    }

    func icon(for app: FavoriteApp) -> NSImage {
        if let cached = iconCache[app.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: app.path)
        iconCache[app.path] = image
        return image
    }

    /// Abre la app Atajos (para crear o editar atajos).
    func openShortcutsApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Utilidades

    private static func execute(arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let string = Prefs.string(key), let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        Prefs.defaults.set(String(decoding: data, as: UTF8.self), forKey: key)
    }
}
