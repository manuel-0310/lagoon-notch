import AppKit
import Observation
import SwiftUI

enum ClipKind: String, Codable, Equatable {
    case text, link, color, image, file

    var label: String {
        switch self {
        case .text: return "Texto"
        case .link: return "Enlace"
        case .color: return "Color"
        case .image: return "Imagen"
        case .file: return "Archivo"
        }
    }

    var icon: MS {
        switch self {
        case .text: return .textFields
        case .link: return .link
        case .color: return .palette
        case .image: return .image
        case .file: return .description
        }
    }
}

struct ClipItem: Identifiable, Equatable, Codable {
    var id = UUID()
    var kind: ClipKind
    var title: String
    var text: String?
    var filePaths: [String]?
    var imageFile: String?
    var date: Date
    var pinned = false

    var swatch: Color? {
        guard kind == .color, let text else { return nil }
        return ClipboardService.color(fromHex: text)
    }
}

/// Historial del portapapeles. macOS no avisa de los cambios, así que se consulta
/// solo el contador del portapapeles (un entero) dos veces por segundo, con tolerancia
/// para que el sistema agrupe los despertares.
@Observable
final class ClipboardService {
    var items: [ClipItem] = []
    var query = ""
    var selectedID: UUID?

    @ObservationIgnored weak var notch: NotchViewModel?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastChangeCount = NSPasteboard.general.changeCount
    @ObservationIgnored private var ownChangeCount: Int?
    @ObservationIgnored private var thumbnails: [UUID: NSImage] = [:]
    @ObservationIgnored private var saveWork: DispatchWorkItem?

    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    var filtered: [ClipItem] {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(term) || ($0.text ?? "").localizedCaseInsensitiveContains(term) }
    }

    var countDescription: String {
        items.count == 1 ? "1 elemento" : "\(items.count) elementos"
    }

    // MARK: - Ciclo de vida

    func start() {
        load()
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard count != ownChangeCount, Prefs.bool(Prefs.clipboardEnabled) else { return }
        capture(pasteboard)
    }

    private func capture(_ pasteboard: NSPasteboard) {
        let types = pasteboard.types ?? []
        if types.contains(Self.concealed) || types.contains(Self.transient) { return }

        var item: ClipItem?
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let title = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) archivos"
            item = ClipItem(kind: .file, title: title, filePaths: urls.map(\.path), date: Date())
        } else if types.contains(.png) || types.contains(.tiff), let image = NSImage(pasteboard: pasteboard) {
            item = storeImage(image)
        } else if let string = pasteboard.string(forType: .string) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            item = Self.classify(trimmed)
        }
        guard let item else { return }
        insert(item)
        if Prefs.bool(Prefs.showClipboardCopied) {
            notch?.post(.copied(item.kind))
        }
    }

    private static func classify(_ text: String) -> ClipItem {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
        if color(fromHex: text) != nil {
            return ClipItem(kind: .color, title: text.uppercased(), text: text.uppercased(), date: Date())
        }
        if !text.contains(" "), let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           ["http", "https", "mailto", "ftp"].contains(scheme) {
            return ClipItem(kind: .link, title: text, text: text, date: Date())
        }
        return ClipItem(kind: .text, title: String(singleLine.prefix(300)), text: text, date: Date())
    }

    private func insert(_ item: ClipItem) {
        var list = items
        var newItem = item
        if let index = list.firstIndex(where: { $0.kind == item.kind && $0.text == item.text
                && $0.filePaths == item.filePaths && item.kind != .image }) {
            newItem.pinned = list[index].pinned
            newItem.id = list[index].id
            list.remove(at: index)
        }
        list.insert(newItem, at: 0)
        items = Self.sorted(trim(list))
        scheduleSave()
    }

    private static func sorted(_ list: [ClipItem]) -> [ClipItem] {
        list.filter(\.pinned) + list.filter { !$0.pinned }
    }

    private func trim(_ list: [ClipItem]) -> [ClipItem] {
        let limit = max(10, Prefs.int(Prefs.clipboardLimit))
        var kept: [ClipItem] = []
        var unpinned = 0
        for item in list {
            if item.pinned {
                kept.append(item)
            } else if unpinned < limit {
                kept.append(item)
                unpinned += 1
            } else {
                removeImageFile(item)
            }
        }
        return kept
    }

    // MARK: - Acciones

    /// Clic para pegar: copia el elemento, cierra el panel y simula ⌘V en la app activa.
    func paste(_ item: ClipItem) {
        copy(item)
        notch?.collapse()
        if MediaKeyTap.isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { Self.sendPaste() }
        } else {
            notch?.post(.copied(item.kind))
        }
    }

    func copy(_ item: ClipItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .text, .link, .color:
            pasteboard.setString(item.text ?? item.title, forType: .string)
        case .image:
            if let image = image(for: item) { pasteboard.writeObjects([image]) }
        case .file:
            let urls = (item.filePaths ?? []).map { URL(fileURLWithPath: $0) as NSURL }
            pasteboard.writeObjects(urls)
        }
        ownChangeCount = pasteboard.changeCount
        lastChangeCount = pasteboard.changeCount
        // Sube al principio.
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            var moved = items.remove(at: index)
            moved.date = Date()
            items.insert(moved, at: 0)
            items = Self.sorted(items)
            scheduleSave()
        }
    }

    func togglePin(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            items[index].pinned.toggle()
            items = Self.sorted(items)
        }
        scheduleSave()
    }

    func delete(_ item: ClipItem) {
        removeImageFile(item)
        items.removeAll { $0.id == item.id }
        scheduleSave()
    }

    func clear() {
        items.filter { !$0.pinned }.forEach(removeImageFile)
        items.removeAll { !$0.pinned }
        scheduleSave()
    }

    func resetSelection() {
        selectedID = filtered.first?.id
    }

    /// ↑ ↓ ⏎ ⌘P ⌘⌫ mientras el panel tiene el foco.
    func handleKey(_ event: NSEvent) -> Bool {
        let list = filtered
        let index = list.firstIndex { $0.id == selectedID }
        switch event.keyCode {
        case 125: // ↓
            let next = min((index ?? -1) + 1, list.count - 1)
            if next >= 0 { selectedID = list[next].id }
            return true
        case 126: // ↑
            let previous = max((index ?? 1) - 1, 0)
            if !list.isEmpty { selectedID = list[previous].id }
            return true
        case 36, 76: // ⏎
            if let index { paste(list[index]) }
            return true
        case 35 where event.modifierFlags.contains(.command): // ⌘P
            if let index { togglePin(list[index]) }
            return true
        case 51 where event.modifierFlags.contains(.command): // ⌘⌫
            if let index { delete(list[index]) }
            return true
        default:
            return false
        }
    }

    private static func sendPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Imágenes

    private func storeImage(_ image: NSImage) -> ClipItem? {
        let size = image.size
        let item = ClipItem(kind: .image,
                            title: "Imagen · \(Int(size.width)) × \(Int(size.height))",
                            imageFile: UUID().uuidString + ".png",
                            date: Date())
        guard let file = item.imageFile, let data = Self.pngData(image, maxSide: 1600) else { return nil }
        try? data.write(to: Self.imagesDirectory.appendingPathComponent(file))
        return item
    }

    func image(for item: ClipItem) -> NSImage? {
        guard let file = item.imageFile else { return nil }
        return NSImage(contentsOf: Self.imagesDirectory.appendingPathComponent(file))
    }

    func thumbnail(for item: ClipItem) -> NSImage? {
        if let cached = thumbnails[item.id] { return cached }
        guard let image = image(for: item) else { return nil }
        let thumb = NSImage(size: NSSize(width: 44, height: 44), flipped: false) { rect in
            image.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
            return true
        }
        thumbnails[item.id] = thumb
        return thumb
    }

    private func removeImageFile(_ item: ClipItem) {
        guard let file = item.imageFile else { return }
        thumbnails[item.id] = nil
        try? FileManager.default.removeItem(at: Self.imagesDirectory.appendingPathComponent(file))
    }

    private static func pngData(_ image: NSImage, maxSide: CGFloat) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, maxSide / CGFloat(max(cg.width, cg.height)))
        let width = Int(CGFloat(cg.width) * scale), height = Int(CGFloat(cg.height) * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])
    }

    // MARK: - Persistencia

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let url = base.appendingPathComponent("Lagoon", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var imagesDirectory: URL {
        let url = directory.appendingPathComponent("Clipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var storeURL: URL { directory.appendingPathComponent("clipboard.json") }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storeURL),
              let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) else { return }
        items = Self.sorted(decoded)
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = items
        let work = DispatchWorkItem {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: Self.storeURL, options: .atomic)
            }
        }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: work)
    }

    // MARK: - Utilidades

    static func color(fromHex text: String) -> Color? {
        var hex = text.trimmingCharacters(in: .whitespaces)
        guard hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return Color(hex: value)
    }
}
