import AppKit

/// Ventana invisible que recibe los archivos que se sueltan sobre el notch.
///
/// Se crea oculta al arrancar. Con el modo "soltar" abierto se coloca justo encima de las dos
/// zonas (bandeja y AirDrop); antes, si no se sabe qué se arrastra, cubre la zona cercana al
/// notch para preguntárselo al arrastre. Una ventana recién mostrada siempre es un destino válido
/// para el arrastre, a diferencia de una que tenía desactivado el ratón al empezar.
final class DropCatcherPanel: NSPanel {
    let catcherView = DropCatcherView()

    init(frame: CGRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        // Casi transparente (no del todo: las zonas 100 % transparentes dejan pasar el ratón).
        backgroundColor = NSColor(white: 0, alpha: 0.001)
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        ignoresMouseEvents = false
        contentView = catcherView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Archivos en un portapapeles de arrastre.
enum DraggedFiles {
    static let legacyType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    static func present(in types: [NSPasteboard.PasteboardType]) -> Bool {
        types.contains(.fileURL) || types.contains(legacyType)
    }

    static func present(in pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || present(in: pasteboard.types ?? [])
    }

    static func urls(in pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return urls
        }
        let paths = pasteboard.propertyList(forType: legacyType) as? [String] ?? []
        return paths.map { URL(fileURLWithPath: $0) }
    }
}

final class DropCatcherView: NSView {
    enum Target { case tray, airDrop }

    /// Sobre las zonas se puede soltar; mientras solo sondea (ver `NotchController`), no.
    var acceptsDrops = false
    /// Entra un arrastre de archivos.
    var onFilesEntered: () -> Void = {}
    /// Entra un arrastre de otra cosa.
    var onOtherEntered: () -> Void = {}
    /// Zona bajo el cursor (nil = fuera).
    var onTarget: (Target?) -> Void = { _ in }
    /// Archivos soltados en una zona.
    var onDrop: (Target, [URL]) -> Void = { _, _ in }

    private var checkedDrag: Int?
    private var checkedHasFiles = false

    init() {
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL, DraggedFiles.legacyType])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func hasFiles(_ sender: NSDraggingInfo) -> Bool {
        if checkedDrag != sender.draggingSequenceNumber {
            checkedDrag = sender.draggingSequenceNumber
            checkedHasFiles = DraggedFiles.present(in: sender.draggingPasteboard)
        }
        return checkedHasFiles
    }

    private func target(for sender: NSDraggingInfo) -> Target? {
        let point = convert(sender.draggingLocation, from: nil)
        guard bounds.contains(point) else { return nil }
        return point.x < bounds.midX ? .tray : .airDrop
    }

    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptsDrops, let target = target(for: sender) else {
            onTarget(nil)
            return []
        }
        onTarget(target)
        return .copy
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasFiles(sender) else {
            onOtherEntered()
            return []
        }
        onFilesEntered()
        return update(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasFiles(sender) else { return [] }
        return update(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTarget(nil)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { acceptsDrops }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard acceptsDrops, let target = target(for: sender) else { return false }
        let urls = DraggedFiles.urls(in: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        onDrop(target, urls)
        return true
    }
}
