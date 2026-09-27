import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// Blanco con opacidad, el recurso más usado del prototipo (rgba(255,255,255,x)).
    static func white(_ opacity: Double) -> Color { Color.white.opacity(opacity) }
}

/// Colores del prototipo (convertidos de OKLCH a sRGB).
enum Palette {
    /// oklch(0.78 0.13 12) — acento de música por defecto.
    static let pink = Color(hex: 0xFE93A1)
    /// oklch(0.6 0.15 12) — resplandor de la portada.
    static let pinkGlow = Color(hex: 0xC95368)
    /// oklch(0.8 0.15 65) — timer.
    static let orange = Color(hex: 0xFFA746)
    /// oklch(0.8 0.17 150) — batería / carga.
    static let green = Color(hex: 0x5EDB81)
    /// oklch(0.68 0.2 25) — alertas.
    static let red = Color(hex: 0xFC5855)
    /// oklch(0.74 0.13 250) — eventos.
    static let blue = Color(hex: 0x67B0F9)
    /// oklch(0.6 0.15 250) — botón "Unirse".
    static let blueButton = Color(hex: 0x2784D5)
    /// oklch(0.8 0.12 200) — bandeja, recordatorios, portapapeles.
    static let cyan = Color(hex: 0x43D5DC)
    /// oklch(0.86 0.13 85) — sol.
    static let yellow = Color(hex: 0xF8CA65)
    /// oklch(0.78 0.14 150)
    static let greenDot = Color(hex: 0x6FD087)
    /// oklch(0.8 0.14 70)
    static let orangeDot = Color(hex: 0xF7AC4D)

    /// Texto secundario: rgba(255,255,255,.55)
    static let secondary = Color.white(0.55)
    /// Fondo de tarjetas: rgba(255,255,255,.07)
    static let card = Color.white(0.07)
    /// Separadores de lista: rgba(255,255,255,.07)
    static let divider = Color.white(0.07)
}

extension NSColor {
    static let lagoonPink = NSColor(srgbRed: 0xFE / 255, green: 0x93 / 255, blue: 0xA1 / 255, alpha: 1)
}

// MARK: - Tipografía

extension View {
    /// Fuente del sistema (SF Pro) con tamaño y peso del prototipo.
    func lagoonFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        font(.system(size: size, weight: weight))
    }

    /// `letter-spacing` en em, como en CSS.
    func letterSpacing(_ em: CGFloat, size: CGFloat) -> some View {
        tracking(em * size)
    }

    /// Etiqueta de sección en mayúsculas (10.5 pt, 600, .5 de opacidad, +.04em).
    func sectionLabel() -> some View {
        font(.system(size: 10.5, weight: .semibold))
            .tracking(0.42)
            .foregroundStyle(Color.white(0.5))
    }
}
