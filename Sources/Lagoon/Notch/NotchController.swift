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

    private var dragChangeCount = 0
    private var dragChecked = false
    private var draggingFiles = false
    private var dragWatchdog: DispatchWorkItem?
    private var scrollAccumulator: CGFloat = 0
    private var scrollLocked = false
    private let fullscreen = FullscreenWatcher()

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

        fullscreen.onChange = { [weak self] value in self?.app.notch.setFullscreen(value) }
        fullscreen.start()

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reposition() })

        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.panel?.orderFrontRegardless() })

        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.applyVisibility()
            self.app.notch.setFullscreen(self.fullscreen.isFullscreen)
        })
    }

    func stop() {
        fullscreen.stop()
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
        fullscreen.scheduleChecks()
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
            dragChangeCount = NSPasteboard(name: .drag).changeCount
            dragChecked = false
            draggingFiles = false
            if !isLocal, !model.interactiveRect.contains(location) {
                model.clickedOutside()
            }
        case .leftMouseDragged:
            if !dragChecked {
                let pasteboard = NSPasteboard(name: .drag)
                if pasteboard.changeCount != dragChangeCount {
                    dragChecked = true
                    // Solo los arrastres que vienen de fuera (Finder, Mail…); los que salen de la bandeja no.
                    draggingFiles = !app.tray.isDraggingOut && Self.containsFiles(pasteboard)
                }
            }
            if draggingFiles {
                updateFileDrag(at: location)
                armDragWatchdog()
            }
        case .leftMouseUp:
            if draggingFiles {
                draggingFiles = false
                dragWatchdog?.cancel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.endFileDrag()
                }
            }
            app.tray.isDraggingOut = false
        default:
            break
        }
        updateMouse(at: location)
    }

    // MARK: - Arrastrar archivos al notch

    private static func containsFiles(_ pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []
        return types.contains(.fileURL) || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType"))
    }

    /// En cuanto el archivo se acerca al notch (zona amplia en la parte superior) se abre el modo
    /// "soltar". Una vez abierto, la zona crece para que no parpadee al moverse.
    private func updateFileDrag(at location: CGPoint) {
        let model = app.notch
        let zone = model.isDropMode ? model.dropApproachRect.insetBy(dx: -120, dy: -120) : model.dropApproachRect
        let near = zone.contains(location)
        model.fileDrag(near: near)
        setCatcherVisible(near)
    }

    private func endFileDrag() {
        app.notch.fileDragEnded()
        setCatcherVisible(false)
    }

    private func setCatcherVisible(_ visible: Bool) {
        guard visible else {
            catcher?.orderOut(nil)
            return
        }
        let catcher = self.catcher ?? makeCatcher()
        let rect = app.notch.dropCatcherRect
        if catcher.frame != rect { catcher.setFrame(rect, display: false) }
        if !catcher.isVisible { catcher.orderFrontRegardless() }
    }

    private func makeCatcher() -> DropCatcherPanel {
        let catcher = DropCatcherPanel()
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
            self.dragWatchdog?.cancel()
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
        self.catcher = catcher
        return catcher
    }

    /// Por si el sistema no entrega el "soltar" durante un arrastre: sale del modo "soltar"
    /// en cuanto no hay ningún botón pulsado.
    private func armDragWatchdog() {
        dragWatchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.draggingFiles else { return }
            if NSEvent.pressedMouseButtons == 0 {
                self.draggingFiles = false
                self.endFileDrag()
            } else {
                self.armDragWatchdog()
            }
        }
        dragWatchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func updateMouse(at location: CGPoint) {
        guard let panel else { return }
        let model = app.notch
        let inside = model.interactiveRect.contains(location)
        let accepts = inside || model.isDropMode
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
