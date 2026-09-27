import AppKit
import Observation
import SwiftUI

/// Máquina de estados del notch: colapsado, alas, actividades, panel expandido y modo "soltar".
/// La forma negra siempre se mueve como una sola pieza que se estira desde el notch.
@Observable
final class NotchViewModel {
    var geometry: NotchGeometry

    // MARK: Estado de dibujo (animado)

    var shapeWidth: CGFloat
    var shapeHeight: CGFloat
    var cornerRadius: CGFloat = 12
    var shadow: ShapeSpec.ShadowKind = .none
    /// Contenido que se está mostrando (nil = en transición, sin contenido).
    var displayed: Presentation? = .idle
    /// Activa la entrada escalonada del contenido del panel.
    var panelRevealed = false
    /// Fase de la sacudida horizontal (timer terminado).
    var shakePhase: CGFloat = 0

    // MARK: Interacción

    var isHovering = false
    var isExpanded = false
    var isDropMode = false
    /// La app al frente está a pantalla completa: el notch se esconde hasta pasar el cursor.
    private(set) var isFullscreenHidden = false
    /// La forma está escondida (pantalla completa, sin hover y sin nada importante que mostrar).
    private(set) var shapeHidden = false
    var trayDropTargeted = false
    var airDropTargeted = false
    var tab: PanelTab = .home
    var subpage: HomeSubpage?
    var tabDirection: CGFloat = 1

    // MARK: Actividades

    private(set) var transient: LiveActivity?

    @ObservationIgnored private var queue: [LiveActivity] = []
    @ObservationIgnored private var dismissWork: DispatchWorkItem?
    @ObservationIgnored private var expandWork: DispatchWorkItem?
    @ObservationIgnored private var collapseWork: DispatchWorkItem?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private(set) var current: Presentation = .idle
    @ObservationIgnored private(set) var currentSpec: ShapeSpec
    @ObservationIgnored private var pointerInside = false
    @ObservationIgnored private var lastTab: PanelTab = .home

    /// Alas en estado continuo (música, timer, carga). Lo aporta `AppState`.
    @ObservationIgnored var wingsProvider: () -> WingContent? = { nil }
    /// Aviso al controlador de ventana (para devolver el foco al colapsar, etc.).
    @ObservationIgnored var onExpandedChange: (Bool) -> Void = { _ in }
    /// ¿El panel tiene el foco de teclado? (no se colapsa solo mientras escribes).
    @ObservationIgnored var isPanelKey: () -> Bool = { false }

    init(geometry: NotchGeometry) {
        self.geometry = geometry
        shapeWidth = geometry.notchWidth
        shapeHeight = geometry.notchHeight
        currentSpec = ShapeSpec(width: geometry.notchWidth, height: geometry.notchHeight, radius: 12, shadow: .none)
    }

    // MARK: - Resolución de estado

    private func resolve() -> Presentation {
        if isDropMode { return .drop }
        if isExpanded { return .expanded }
        if isFullscreenHidden, !isHovering {
            // A pantalla completa solo baja lo importante (si así se eligió en Ajustes).
            if let transient, transient.isImportant, Prefs.bool(Prefs.fullscreenShowImportant) {
                return .activity(transient)
            }
            return .idle
        }
        if let transient { return .activity(transient) }
        if let wings = wingsProvider() { return .wings(wings) }
        return .idle
    }

    func setFullscreen(_ fullscreen: Bool) {
        let hide = fullscreen && Prefs.bool(Prefs.hideInFullscreen)
        guard hide != isFullscreenHidden else { return }
        isFullscreenHidden = hide
        refresh()
    }

    private func updateShapeHidden(for next: Presentation) {
        let hide = isFullscreenHidden && !isHovering && next == .idle
        guard hide != shapeHidden else { return }
        withAnimation(hide ? .easeIn(duration: 0.18) : .easeOut(duration: 0.15)) { shapeHidden = hide }
    }

    func spec(for presentation: Presentation) -> ShapeSpec {
        let nw = geometry.notchWidth
        let nh = geometry.notchHeight
        switch presentation {
        case .idle:
            // Hover · crece 6 pt por lado y 2 pt de alto antes de abrirse.
            return isHovering
                ? ShapeSpec(width: nw + 12, height: nh + 2, radius: 13, shadow: .hover)
                : ShapeSpec(width: nw, height: nh, radius: 12, shadow: .none)
        case let .wings(wings):
            let base = nw + 2 * wings.wingWidth
            return isHovering
                ? ShapeSpec(width: base + 12, height: nh + 2, radius: 15, shadow: .hover)
                : ShapeSpec(width: base, height: nh, radius: 14, shadow: .none)
        case let .activity(activity):
            switch activity.style {
            case .wing:
                return ShapeSpec(width: nw + 2 * activity.wingWidth, height: nh, radius: 14, shadow: .none)
            case .block:
                return ShapeSpec(width: max(activity.blockWidth, nw + 100),
                                 height: nh + 8 + activity.blockContentHeight + 14,
                                 radius: 26, shadow: .block)
            }
        case .expanded:
            return ShapeSpec(width: NotchGeometry.expandedWidth,
                             height: nh + NotchGeometry.expandedContentHeight,
                             radius: 30, shadow: .expanded)
        case .drop:
            return ShapeSpec(width: 480, height: nh + 8 + 104 + 14, radius: 26, shadow: .block)
        }
    }

    /// Recalcula qué mostrar y anima la forma según la tabla de transiciones.
    func refresh(animated: Bool = true) {
        let next = resolve()
        let target = spec(for: next)
        updateShapeHidden(for: next)

        if next == current {
            if target != currentSpec {
                currentSpec = target
                if animated {
                    withAnimation(Motion.hover) { setShape(target) }
                } else {
                    setShape(target)
                }
            }
            return
        }

        let previous = current
        let previousSpec = currentSpec
        current = next
        currentSpec = target
        generation += 1
        let gen = generation

        guard animated else {
            setShape(target)
            displayed = next
            panelRevealed = next == .expanded
            return
        }

        // Colapsado → Expandido: el panel nace del notch con un rebote ligero.
        if next == .expanded {
            panelRevealed = false
            withAnimation(Motion.expand) { setShape(target) }
            withAnimation(.easeOut(duration: 0.12)) { displayed = .expanded }
            after(0.02, gen) { self.panelRevealed = true }
            return
        }

        // Expandido → Colapsado: el contenido se va 100 ms antes que la forma, sin rebote.
        if previous == .expanded {
            panelRevealed = false
            withAnimation(.easeIn(duration: 0.1)) { displayed = nil }
            after(0.1, gen) {
                withAnimation(Motion.collapse) { self.setShape(target) }
                withAnimation(Motion.contentIn) { self.displayed = next }
            }
            return
        }

        // Arrastrando un archivo: se abre en modo "soltar" (200 ms).
        if next == .drop {
            withAnimation(Motion.dropIn) {
                setShape(target)
                displayed = next
            }
            return
        }

        let growing = target.width * target.height >= previousSpec.width * previousSpec.height - 1
        if growing {
            // Crece primero en ancho y luego en alto; el contenido entra 80 ms después.
            withAnimation(Motion.activityIn) {
                shapeWidth = target.width
                shadow = target.shadow
            }
            withAnimation(Motion.reduced ? Motion.fade : Motion.activityIn.delay(0.05)) {
                shapeHeight = target.height
                cornerRadius = target.radius
            }
            withAnimation(Motion.contentIn) { displayed = next }
        } else {
            // El contenido se desvanece primero (120 ms) y la forma se contrae sin rebote.
            withAnimation(Motion.contentOut) { displayed = nil }
            after(0.1, gen) {
                withAnimation(Motion.activityOut) { self.setShape(target) }
                withAnimation(Motion.contentIn) { self.displayed = next }
            }
        }
    }

    private func setShape(_ spec: ShapeSpec) {
        shapeWidth = spec.width
        shapeHeight = spec.height
        cornerRadius = spec.radius
        shadow = spec.shadow
    }

    private func after(_ delay: TimeInterval, _ gen: Int, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == gen else { return }
            work()
        }
    }

    // MARK: - Geometría de interacción (coordenadas de pantalla)

    /// Zona que recibe el ratón. Fuera de ella la ventana deja pasar los clics.
    var interactiveRect: CGRect {
        var size = currentSpec.size
        switch current {
        case .idle, .wings:
            size.width += 16
            size.height += 4
        default:
            size.width += 4
            size.height += 4
        }
        var rect = geometry.screenRect(for: size)
        rect.size.height += 6
        return rect
    }

    /// Zona amplia alrededor del notch: al acercar un archivo aquí se abre el modo "soltar".
    var dropApproachRect: CGRect {
        let frame = geometry.screenFrame
        let width: CGFloat = 900, height: CGFloat = 320
        return CGRect(x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height + 10)
    }

    /// Donde se colocan las dos zonas para soltar (con un poco de margen).
    var dropCatcherRect: CGRect {
        geometry.screenRect(for: spec(for: .drop).size).insetBy(dx: -20, dy: -20)
    }

    // MARK: - Hover, clic, expandir, colapsar

    func setPointerInside(_ inside: Bool) {
        guard inside != pointerInside else { return }
        pointerInside = inside
        if inside {
            collapseWork?.cancel()
            guard !isExpanded, !isDropMode else { return }
            switch current {
            case .idle, .wings:
                isHovering = true
                refresh()
            default:
                break
            }
            dismissWork?.cancel()
            scheduleHoverExpand()
        } else {
            expandWork?.cancel()
            if isHovering {
                isHovering = false
                refresh()
            }
            scheduleDismiss()
            if isExpanded { scheduleCollapse(after: 0.3) }
        }
    }

    private func scheduleHoverExpand() {
        expandWork?.cancel()
        guard Prefs.bool(Prefs.hoverToOpen) else { return }
        if case let .activity(activity) = current, activity.isInteractive { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pointerInside, NSEvent.pressedMouseButtons == 0 else { return }
            self.expand()
        }
        expandWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, Prefs.double(Prefs.hoverDelay)), execute: work)
    }

    func scheduleCollapse(after delay: TimeInterval) {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isExpanded, !self.pointerInside else { return }
            if self.isPanelKey() { return }
            // No colapsar mientras se arrastra algo fuera del panel.
            if NSEvent.pressedMouseButtons != 0 {
                self.scheduleCollapse(after: 0.25)
                return
            }
            self.collapse()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Clic sobre la forma colapsada o sobre una actividad.
    func handleTap() {
        guard !isExpanded else { return }
        expand()
    }

    func expand(tab requested: PanelTab? = nil, subpage requestedSubpage: HomeSubpage? = nil) {
        expandWork?.cancel()
        collapseWork?.cancel()
        if let requested {
            tab = requested
            subpage = requestedSubpage
        } else if let transient {
            let target = Self.destination(for: transient)
            tab = target.0
            subpage = target.1
        } else if !isExpanded {
            tab = PanelTab.hidden.contains(lastTab) ? .home : lastTab
            subpage = nil
        }
        if let transient, !transient.isSticky {
            dismissWork?.cancel()
            self.transient = queue.isEmpty ? nil : queue.removeFirst()
        }
        isHovering = false
        if !isExpanded {
            isExpanded = true
            onExpandedChange(true)
        }
        refresh()
    }

    func collapse() {
        expandWork?.cancel()
        collapseWork?.cancel()
        guard isExpanded else { return }
        lastTab = tab
        isExpanded = false
        onExpandedChange(false)
        refresh()
        scheduleDismiss()
    }

    func clickedOutside() {
        if isExpanded { collapse() }
    }

    private static func destination(for activity: LiveActivity) -> (PanelTab, HomeSubpage?) {
        switch activity {
        case .songChange: return (.music, nil)
        case .chargerConnected, .chargerDisconnected, .lowBattery, .airPodsConnected: return (.home, .battery)
        case .volume, .brightness: return (.home, .sound)
        case .upcomingEvent, .reminderDue: return (.calendar, nil)
        case .timerFinished: return (.timer, nil)
        case .copied: return (.clipboard, nil)
        case .traySaved: return (.tray, nil)
        case .welcome, .focusChanged, .privacyStarted: return (.home, nil)
        case .shortcutRan: return (.shortcuts, nil)
        case .claudePermission, .claudeNotice: return (.claude, nil)
        }
    }

    // MARK: - Pestañas

    func select(_ newTab: PanelTab) {
        guard newTab != tab || subpage != nil else { return }
        tabDirection = newTab.rawValue >= tab.rawValue ? 1 : -1
        withAnimation(Motion.tab) {
            tab = newTab
            subpage = nil
        }
    }

    func open(_ page: HomeSubpage) {
        tabDirection = 1
        withAnimation(Motion.tab) {
            tab = .home
            subpage = page
        }
    }

    func back() {
        tabDirection = -1
        withAnimation(Motion.tab) { subpage = nil }
    }

    /// Deslizar con dos dedos.
    func swipe(_ direction: Int) {
        let tabs = PanelTab.visible
        guard let current = tabs.firstIndex(of: tab) else {
            select(.home)
            return
        }
        let index = current + direction
        guard tabs.indices.contains(index) else { return }
        select(tabs[index])
    }

    // MARK: - Arrastrar archivos

    func fileDrag(near: Bool) {
        guard near != isDropMode else { return }
        isDropMode = near
        if !near {
            trayDropTargeted = false
            airDropTargeted = false
        }
        refresh()
    }

    func fileDragEnded() {
        guard isDropMode else { return }
        isDropMode = false
        trayDropTargeted = false
        airDropTargeted = false
        refresh()
        if isExpanded, !pointerInside { scheduleCollapse(after: 0.8) }
    }

    // MARK: - Actividades en vivo

    func post(_ activity: LiveActivity) {
        guard !AppEnvironment.isSnapshot else { return }
        if let cur = transient {
            if cur.key == activity.key {
                if cur != activity { transient = activity }
                scheduleDismiss()
                return
            }
            if activity.isHUD {
                if !cur.isHUD { queue.insert(cur, at: 0) }
                show(activity)
                return
            }
            if cur.isHUD || cur.isSticky || activity.priority <= cur.priority {
                if !queue.contains(where: { $0.key == activity.key }) { queue.append(activity) }
                return
            }
            show(activity)
            return
        }
        show(activity)
    }

    private func show(_ activity: LiveActivity) {
        transient = activity
        scheduleDismiss()
        refresh()
        if case .timerFinished = activity, !Motion.reduced {
            // Sacudida horizontal (3 × 4 pt, 3 × 60 ms).
            after(0.25, generation) {
                withAnimation(.linear(duration: 0.18)) { self.shakePhase += 1 }
            }
        }
    }

    /// Solo para las capturas: fija una actividad sin animar.
    func showForSnapshot(_ activity: LiveActivity?) {
        transient = activity
        refresh(animated: false)
    }

    /// Cierra la actividad actual y muestra la siguiente de la cola.
    func dismissTransient() {
        dismissWork?.cancel()
        transient = queue.isEmpty ? nil : queue.removeFirst()
        scheduleDismiss()
        refresh()
    }

    /// Cierra la actividad si es la indicada (o la saca de la cola).
    func dismiss(where predicate: (LiveActivity) -> Bool) {
        queue.removeAll(where: predicate)
        if let transient, predicate(transient) { dismissTransient() }
    }

    private func scheduleDismiss() {
        dismissWork?.cancel()
        guard let activity = transient,
              let duration = activity.duration(base: max(1, Prefs.double(Prefs.activityDuration))) else { return }
        // Mientras el cursor está encima, la actividad no se va.
        if pointerInside, !activity.isHUD, !isExpanded { return }
        let work = DispatchWorkItem { [weak self] in self?.dismissTransient() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
