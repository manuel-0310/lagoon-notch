import AppKit
import SwiftUI

/// Crea la ventana del notch, la mantiene en su sitio y decide cuándo recibe el ratón.
///
/// La ventana es fija y transparente; fuera de la forma negra deja pasar los clics
/// (`ignoresMouseEvents`), así que no molesta a la barra de menús ni a las apps.
final class NotchController {
    private let app: AppState
    private var panel: NotchPanel?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []

    private var dragChangeCount = 0
    private var dragChecked = false
    private var draggingFiles = false
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
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
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
                    // Solo los arrastres que vienen de fuera (Finder, Mail…); los de la bandeja no.
                    draggingFiles = !isLocal && (pasteboard.types?.contains(.fileURL) ?? false)
                }
            }
            if draggingFiles {
                model.fileDrag(near: model.dropActivationRect.contains(location))
            }
        case .leftMouseUp:
            if draggingFiles {
                draggingFiles = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.app.notch.fileDragEnded()
                }
            }
        default:
            break
        }
        updateMouse(at: location)
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
