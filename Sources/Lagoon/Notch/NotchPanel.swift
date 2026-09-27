import AppKit
import SwiftUI

/// Ventana transparente, sin bordes y que no activa la app, colocada sobre la barra de menús.
final class NotchPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // `isFloatingPanel` cambia el nivel a "flotante" (debajo de la barra de menús), así que va
        // antes de fijar el nivel. Por encima de la barra, las pestañas junto al notch se ven y
        // reciben los clics.
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        animationBehavior = .none
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// macOS baja por defecto las ventanas para que no tapen la barra de menús.
    /// El notch tiene que quedar pegado al borde superior, sobre el notch físico.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Hosting view que acepta el primer clic (los botones responden aunque el panel no tenga foco).
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }
}
