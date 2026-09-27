import AppKit
import SwiftUI

/// Crea la ventana del notch, la mantiene en su sitio y decide cuándo recibe el ratón.
///
/// La ventana es fija y transparente; fuera de la forma negra deja pasar los clics
/// (`ignoresMouseEvents`), así que no molesta a la barra de menús ni a las apps.
final class NotchController {
    private let app: AppState
    private var panel: NotchPanel?
    private var catcher: DropCatcherPanel?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []

    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var draggingFiles = false
    private var openOnDragStart = true
    private var pressTimer: Timer?
    private var scrollAccumulator: CGFloat = 0
    private var scrollLocked = false

    init(app: AppState) {
        self.app = app
    }

    func start() {
        let model = app.notch
        model.isPanelKey = { [weak self] in self?.panel?.isKeyWindow ?? false }
        model.onExpandedChange = { [weak self] expanded in
            guard let self, let panel = self.panel else { return }
            if !expanded, panel.isKeyWindow {
                panel.resignKey()
            }
            self.updateMouse(at: NSEvent.mouseLocation)
        }

        buildPanel()
        installMonitors()

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reposition() })

        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.panel?.orderFrontRegardless() })

        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.applyVisibility() })
    }

    func stop() {
        pressTimer?.invalidate()
        pressTimer = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        catcher?.orderOut(nil)
        panel?.orderOut(nil)
    }

    // MARK: - Ventana

    private func buildPanel() {
        guard let screen = NotchGeometry.preferredScreen() else { return }
        let geometry = NotchGeometry.detect(on: screen)
        app.notch.geometry = geometry
        app.notch.refresh(animated: false)

        let panel = NotchPanel(frame: geometry.windowFrame)
        let root = NotchRootView().environment(app)
        let hosting = NotchHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: geometry.windowFrame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.panel = panel
        // La ventana que recibe los archivos existe desde el principio (oculta), así ya está
        // registrada como destino cuando empieza un arrastre.
        catcher = makeCatcher()
        applyVisibility()
    }

    private func reposition() {
        guard let panel, let screen = NotchGeometry.preferredScreen() else { return }
        let geometry = NotchGeometry.detect(on: screen)
        if geometry != app.notch.geometry {
            app.notch.geometry = geometry
            app.notch.refresh(animated: false)
        }
        panel.setFrame(geometry.windowFrame, display: true)
        applyVisibility()
    }

    private func applyVisibility() {
        guard let panel else { return }
        let visible = app.notch.geometry.hasNotch || Prefs.bool(Prefs.showOnScreensWithoutNotch)
        if visible {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    // MARK: - Ratón y teclado

    private func installMonitors() {
        let mouseMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown,
                                                .leftMouseUp, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            self?.handle(event, isLocal: false)
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            self?.handle(event, isLocal: true)
            return event
        }) {
            monitors.append(local)
        }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event) ? nil : event
        }) {
            monitors.append(keys)
        }
        if let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            self?.handleScroll(event)
            return event
        }) {
            monitors.append(scroll)
        }
    }

    private func handle(_ event: NSEvent, isLocal: Bool) {
        let location = NSEvent.mouseLocation
        let model = app.notch
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            if event.type == .leftMouseDown { beginPress() }
            if !isLocal, !model.interactiveRect.contains(location) {
                model.clickedOutside()
            }
        case .leftMouseDragged:
            if pressTimer == nil { beginPress(keepingBaseline: true) }
            checkFileDrag()
        case .leftMouseUp:
            endPress()
        default:
            break
        }
        updateMouse(at: location)
    }

    // MARK: - Arrastrar archivos al notch

    /// Cada vez que se pulsa el botón se vigila si empieza un arrastre de archivos. Mientras siga
    /// pulsado se revisa 30 veces por segundo el contador del portapapeles de arrastre (un entero)
    /// y la posición del cursor: durante un arrastre, macOS no siempre entrega los eventos del
    /// ratón a otras apps. Al soltar el botón se deja de revisar.
    private func beginPress(keepingBaseline: Bool = false) {
        if !keepingBaseline { dragChangeCount = NSPasteboard(name: .drag).changeCount }
        draggingFiles = false
        app.tray.isDraggingOut = false
        pressTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            if NSEvent.pressedMouseButtons & 1 == 0 {
                self.endPress()
            } else {
                self.checkFileDrag()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pressTimer = timer
    }

    private func checkFileDrag() {
        if !draggingFiles {
            let pasteboard = NSPasteboard(name: .drag)
            // Solo los arrastres que vienen de fuera (Finder, Mail…); los que salen de la bandeja no.
            guard pasteboard.changeCount != dragChangeCount, !app.tray.isDraggingOut else { return }
            let types = pasteboard.types ?? []
            guard Self.containsFiles(types) else {
                // Se arrastra otra cosa (texto, un enlace…): no hace falta volver a mirar.
                if !types.isEmpty { dragChangeCount = pasteboard.changeCount }
                return
            }
            draggingFiles = true
            openOnDragStart = Prefs.bool(Prefs.dropOpensOnDragStart)
        }
        updateFileDrag(at: NSEvent.mouseLocation)
    }

    private func endPress() {
        pressTimer?.invalidate()
        pressTimer = nil
        dragChangeCount = NSPasteboard(name: .drag).changeCount
        app.tray.isDraggingOut = false
        guard draggingFiles else { return }
        draggingFiles = false
        // Deja que el "soltar" llegue antes a la ventana que recibe los archivos.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !self.draggingFiles else { return }
            self.endFileDrag()
        }
    }

    private static func containsFiles(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        return types.contains(.fileURL) || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType"))
    }

    /// El modo "soltar" se abre en cuanto empieza el arrastre (o, si se desactiva en Ajustes, al
    /// acercar el archivo al notch). Así las zonas quedan bajo la barra de menús y no hace falta
    /// llevar el archivo al borde superior, donde macOS abre Mission Control.
    private func updateFileDrag(at location: CGPoint) {
        let model = app.notch
        let near: Bool
        if panel?.isVisible != true {
            near = false
        } else if openOnDragStart {
            near = true
        } else {
            // Una vez abierto, la zona crece para que no parpadee al moverse.
            let zone = model.isDropMode ? model.dropApproachRect.insetBy(dx: -120, dy: -120) : model.dropApproachRect
            near = zone.contains(location)
        }
        model.fileDrag(near: near)
        setCatcherVisible(near)
    }

    private func endFileDrag() {
        app.notch.fileDragEnded()
        setCatcherVisible(false)
    }

    private func setCatcherVisible(_ visible: Bool) {
        guard let catcher else { return }
        guard visible else {
            if catcher.isVisible { catcher.orderOut(nil) }
            return
        }
        let rect = app.notch.dropCatcherRect
        if catcher.frame != rect { catcher.setFrame(rect, display: false) }
        if !catcher.isVisible { catcher.orderFrontRegardless() }
    }

    private func makeCatcher() -> DropCatcherPanel {
        let catcher = DropCatcherPanel(frame: app.notch.dropCatcherRect)
        catcher.catcherView.onTarget = { [weak self] target in
            guard let model = self?.app.notch else { return }
            let tray = target == .tray, airDrop = target == .airDrop
            guard model.trayDropTargeted != tray || model.airDropTargeted != airDrop else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                model.trayDropTargeted = tray
                model.airDropTargeted = airDrop
            }
        }
        catcher.catcherView.onDrop = { [weak self] target, urls in
            guard let self else { return }
            self.draggingFiles = false
            switch target {
            case .tray:
                let added = self.app.tray.add(urls: urls)
                self.endFileDrag()
                if self.app.notch.isExpanded {
                    self.app.notch.select(.tray)
                } else if added > 0 {
                    self.app.notch.post(.traySaved)
                }
            case .airDrop:
                self.endFileDrag()
                AirDrop.share(urls)
            }
        }
        return catcher
    }

    private func updateMouse(at location: CGPoint) {
        guard let panel else { return }
        let model = app.notch
        let inside = model.interactiveRect.contains(location)
        // En modo "soltar" los archivos los recibe DropCatcherPanel; esta ventana deja pasar el
        // ratón para no tapar a las apps de debajo si sueltas el archivo en otro sitio.
        let accepts = inside && !model.isDropMode
        if panel.ignoresMouseEvents == accepts {
            panel.ignoresMouseEvents = !accepts
        }
        model.setPointerInside(inside)
    }

    /// Esc colapsa; en el portapapeles, ↑ ↓ ⏎ y ⌘P.
    private func handleKey(_ event: NSEvent) -> Bool {
        let model = app.notch
        guard model.isExpanded, panel?.isKeyWindow == true else { return false }
        switch event.keyCode {
        case 53: // Esc
            model.collapse()
            return true
        default:
            break
        }
        if model.tab == .clipboard {
            return app.clipboard.handleKey(event)
        }
        return false
    }

    /// Deslizar con dos dedos cambia de pestaña.
    private func handleScroll(_ event: NSEvent) {
        let model = app.notch
        guard model.isExpanded, event.hasPreciseScrollingDeltas else { return }
        if event.phase == .began {
            scrollAccumulator = 0
            scrollLocked = false
        }
        if event.momentumPhase != [] { return }
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }
        scrollAccumulator += event.scrollingDeltaX
        if !scrollLocked, abs(scrollAccumulator) > 50 {
            scrollLocked = true
            model.swipe(scrollAccumulator < 0 ? 1 : -1)
        }
        if event.phase == .ended || event.phase == .cancelled {
            scrollAccumulator = 0
            scrollLocked = false
        }
    }
}
