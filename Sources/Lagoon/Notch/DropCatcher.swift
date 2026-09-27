import AppKit

/// Ventana invisible que recibe los archivos que se sueltan sobre el notch.
///
/// Se muestra solo mientras se arrastra un archivo cerca del notch, justo encima de las dos
/// zonas (bandeja y AirDrop). Una ventana recién mostrada siempre es un destino válido para
/// el arrastre, a diferencia de una que tenía desactivado el ratón al empezar.
final class DropCatcherPanel: NSPanel {
    let catcherView = DropCatcherView()

    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: true)
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

final class DropCatcherView: NSView {
    enum Target { case tray, airDrop }

    /// Zona bajo el cursor (nil = fuera).
    var onTarget: (Target?) -> Void = { _ in }
    /// Archivos soltados en una zona.
    var onDrop: (Target, [URL]) -> Void = { _, _ in }

    init() {
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("NSFilenamesPboardType")])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func target(for sender: NSDraggingInfo) -> Target {
        let point = convert(sender.draggingLocation, from: nil)
        return point.x < bounds.midX ? .tray : .airDrop
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onTarget(target(for: sender))
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        onTarget(target(for: sender))
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTarget(nil)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onDrop(target(for: sender), urls)
        return true
    }
}
