import AppKit

/// Medidas del notch físico de la pantalla (o un notch virtual en pantallas sin notch).
struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var hasNotch: Bool

    /// Tamaño fijo de la ventana transparente: cabe el panel expandido (580 × 232) con su sombra.
    static let windowSize = CGSize(width: 760, height: 330)

    /// Ancho y alto del panel expandido (propuesta: 580 × 232 con notch de 32 pt).
    static let expandedWidth: CGFloat = 580
    static let expandedContentHeight: CGFloat = 200

    static let preview = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                       notchWidth: 200, notchHeight: 32, hasNotch: true)

    static func detect(on screen: NSScreen) -> NotchGeometry {
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return NotchGeometry(screenFrame: screen.frame,
                                 notchWidth: max(120, width.rounded()),
                                 notchHeight: top,
                                 hasNotch: true)
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        let height = menuBar > 10 ? min(max(menuBar, 24), 32) : 24
        return NotchGeometry(screenFrame: screen.frame, notchWidth: 200, notchHeight: height, hasNotch: false)
    }

    /// Pantalla preferida: la integrada con notch; si no hay, la principal.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    var windowFrame: CGRect {
        CGRect(x: screenFrame.midX - Self.windowSize.width / 2,
               y: screenFrame.maxY - Self.windowSize.height,
               width: Self.windowSize.width,
               height: Self.windowSize.height)
    }

    /// Rectángulo (coordenadas de pantalla) de una forma de `size` pegada al borde superior.
    func screenRect(for size: CGSize) -> CGRect {
        CGRect(x: screenFrame.midX - size.width / 2,
               y: screenFrame.maxY - size.height,
               width: size.width,
               height: size.height)
    }
}
