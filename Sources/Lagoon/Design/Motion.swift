import AppKit
import SwiftUI

/// Intensidad de animación (Ajustes › Apariencia). Escala la amortiguación de los muelles.
enum AnimationIntensity: String, CaseIterable, Identifiable {
    case minimal, normal, lively

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minimal: return "Mínima"
        case .normal: return "Normal"
        case .lively: return "Viva"
        }
    }
}

/// Curvas y duraciones de la tabla "Transiciones y animaciones" del prototipo.
enum Motion {
    static var intensity: AnimationIntensity {
        AnimationIntensity(rawValue: UserDefaults.standard.string(forKey: Prefs.animationIntensity) ?? "") ?? .normal
    }

    /// "Reducir movimiento": ajuste del sistema o intensidad "Mínima" → fundidos de 200 ms.
    static var reduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || intensity == .minimal
    }

    static let fade = Animation.easeInOut(duration: 0.2)

    static func spring(response: Double, damping: Double) -> Animation {
        if reduced { return fade }
        let d = intensity == .lively ? max(0.55, damping - 0.12) : damping
        return .spring(response: response, dampingFraction: d)
    }

    /// Colapsado → Actividad: 380 ms · muelle 0,38 s, amort. 0,78.
    static var activityIn: Animation { spring(response: 0.38, damping: 0.78) }
    /// Actividad → Colapsado: 280 ms · ease-in-out.
    static var activityOut: Animation { reduced ? fade : .easeInOut(duration: 0.28) }
    /// Hover: 160 ms · ease-out.
    static var hover: Animation { reduced ? fade : .easeOut(duration: 0.16) }
    /// Colapsado → Expandido: 450 ms · muelle 0,45 s, amort. 0,72.
    static var expand: Animation { spring(response: 0.45, damping: 0.72) }
    /// Expandido → Colapsado: 320 ms · muelle crítico.
    static var collapse: Animation { reduced ? fade : .spring(response: 0.32, dampingFraction: 1) }
    /// Cambio de pestaña: 220 ms · muelle 0,3 s.
    static var tab: Animation { spring(response: 0.3, damping: 0.86) }
    /// Cambio de canción: 500 ms · ease-in-out.
    static var songChange: Animation { reduced ? fade : .easeInOut(duration: 0.5) }
    /// El contenido entra 80 ms después, con fundido y desenfoque.
    static var contentIn: Animation { reduced ? fade : .easeOut(duration: 0.24).delay(0.08) }
    /// El contenido se desvanece primero (120 ms).
    static var contentOut: Animation { reduced ? fade : .easeIn(duration: 0.12) }
    /// Volumen y brillo: 90 ms por paso, sin rebote.
    static var hudStep: Animation { .easeOut(duration: 0.09) }
    /// Arrastrar archivo: 200 ms entrar.
    static var dropIn: Animation { reduced ? fade : .easeOut(duration: 0.2) }
    /// Contenido escalonado del panel: 30 ms por bloque, subiendo 6 pt.
    static func stagger(_ index: Int) -> Animation {
        reduced ? fade : .easeOut(duration: 0.28).delay(0.07 + Double(index) * 0.03)
    }
}

// MARK: - Transiciones reutilizables

/// Fundido + desenfoque de 6 → 0 pt.
struct BlurFade: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .blur(radius: active ? 6 : 0)
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(active: BlurFade(active: true), identity: BlurFade(active: false))
    }

    /// Entrada con desenfoque (80 ms de retraso) y salida rápida.
    static var activityContent: AnyTransition {
        .asymmetric(insertion: .blurFade.animation(Motion.contentIn),
                    removal: .opacity.animation(Motion.contentOut))
    }

    /// Fundido cruzado con 12 pt de desplazamiento en la dirección del gesto.
    static func tabSlide(_ direction: CGFloat) -> AnyTransition {
        if Motion.reduced { return .opacity }
        return .asymmetric(insertion: .offset(x: 12 * direction).combined(with: .opacity),
                           removal: .offset(x: -12 * direction).combined(with: .opacity))
    }

    /// Portada: gira 90° en Y al salir y entra la nueva.
    static var artworkFlip: AnyTransition {
        if Motion.reduced { return .opacity }
        return .asymmetric(insertion: .modifier(active: FlipModifier(angle: -90), identity: FlipModifier(angle: 0)),
                           removal: .modifier(active: FlipModifier(angle: 90), identity: FlipModifier(angle: 0)))
    }
}

struct FlipModifier: ViewModifier {
    var angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .opacity(abs(angle) >= 89 ? 0 : 1)
    }
}

// MARK: - Entrada escalonada del panel expandido

private struct PanelRevealedKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var panelRevealed: Bool {
        get { self[PanelRevealedKey.self] }
        set { self[PanelRevealedKey.self] = newValue }
    }
}

struct StaggerIn: ViewModifier {
    @Environment(\.panelRevealed) private var revealed
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 6)
            .animation(revealed ? Motion.stagger(index) : .easeIn(duration: 0.1), value: revealed)
    }
}

extension View {
    func stagger(_ index: Int) -> some View { modifier(StaggerIn(index: index)) }
}

// MARK: - Sacudida horizontal

struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 4
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * 2 * shakes), y: 0))
    }
}
