import AppKit

/// Detecta si la app al frente está a pantalla completa en la pantalla del notch.
///
/// Sin sondeo: se recalcula al cambiar de espacio o de app (entrar o salir de pantalla completa
/// siempre cambia de espacio). Como la lista de ventanas tarda un poco en actualizarse, cada aviso
/// se comprueba dos veces más, a los 0,3 s y a 1 s.
final class FullscreenWatcher {
    var onChange: (Bool) -> Void = { _ in }
    /// Pantalla que se vigila (la del notch).
    var screen: () -> NSScreen? = { NotchGeometry.preferredScreen() }

    private(set) var isFullscreen = false
    private var observers: [NSObjectProtocol] = []

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.scheduleChecks()
            })
        }
        check()
    }

    func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
    }

    func scheduleChecks() {
        check()
        for delay in [0.3, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.check() }
        }
    }

    func check() {
        let value = screen().map(Self.isFullscreen(on:)) ?? false
        guard value != isFullscreen else { return }
        isFullscreen = value
        onChange(value)
    }

    /// ¿La app al frente está a pantalla completa en esta pantalla?
    static func isFullscreen(on screen: NSScreen) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier,
              front.bundleIdentifier != "com.apple.finder" else { return false }
        let pid = front.processIdentifier
        // Con permiso de Accesibilidad (opcional) se pregunta directamente a la ventana.
        if AXIsProcessTrusted(), let value = accessibilityFullscreen(pid: pid) {
            return value && windowCovers(screen: screen, pid: pid, allowNotchStrip: true)
        }
        return windowCovers(screen: screen, pid: pid, allowNotchStrip: false)
    }

    /// Atributo "AXFullScreen" de la ventana principal de la app.
    private static func accessibilityFullscreen(pid: pid_t) -> Bool? {
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, "AXFullScreen" as CFString, &value) == .success
        else { return nil }
        return (value as? Bool) ?? (value as? NSNumber)?.boolValue
    }

    /// ¿Hay una ventana normal de la app que ocupa toda la pantalla?
    /// Leer los límites, la capa y el dueño de las ventanas no necesita permiso de grabación.
    private static func windowCovers(screen: NSScreen, pid: pid_t, allowNotchStrip: Bool) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return false }

        // CoreGraphics usa el origen arriba a la izquierda de la pantalla principal.
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let frame = screen.frame
        let target = CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
        // En pantallas con notch, la app a pantalla completa suele quedarse debajo de la cámara.
        // Una ventana maximizada tiene el mismo tamaño, así que sin Accesibilidad se distingue
        // porque en pantalla completa la barra de menús está oculta.
        let notchStrip = screen.safeAreaInsets.top + 2
        let stripAllowed = allowNotchStrip || !menuBarVisible(in: list, target: target)

        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = bounds(of: info) else { continue }
            let sameWidth = abs(bounds.width - target.width) < 2 && abs(bounds.minX - target.minX) < 2
            let reachesBottom = abs(bounds.maxY - target.maxY) < 2
            let fullHeight = abs(bounds.height - target.height) < 2
            let belowNotch = notchStrip > 2 && bounds.height >= target.height - notchStrip
            if sameWidth, reachesBottom, fullHeight || (stripAllowed && belowNotch) { return true }
        }
        return false
    }

    /// La barra de menús es una ventana del Window Server en la capa del menú principal.
    private static func menuBarVisible(in list: [[String: Any]], target: CGRect) -> Bool {
        let menuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        return list.contains { info in
            guard (info[kCGWindowLayer as String] as? Int) == menuLevel,
                  (info[kCGWindowOwnerName as String] as? String) == "Window Server",
                  let bounds = bounds(of: info) else { return false }
            return abs(bounds.minY - target.minY) < 2 && bounds.intersects(target) && bounds.height > 10
        }
    }

    private static func bounds(of info: [String: Any]) -> CGRect? {
        guard let dict = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dict as CFDictionary)
    }
}
