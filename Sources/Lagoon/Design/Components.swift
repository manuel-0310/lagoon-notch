import AppKit
import QuartzCore
import SwiftUI

// MARK: - Botones

/// Estilo de pulsación: se encoge un poco y se atenúa.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Botón píldora del prototipo: 28 pt de alto, radio 14, 12 pt semibold.
struct PillButton: View {
    enum Style {
        /// rgba(255,255,255,.14), texto blanco.
        case normal
        /// Fondo de color sólido con texto del color indicado.
        case filled(Color, text: Color)
        /// Fondo del color al 25 % y texto del color.
        case tinted(Color)
    }

    var title: String? = nil
    var icon: MS? = nil
    var style: Style = .normal
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Icon(icon, size: 15) }
                if let title { Text(title) }
            }
            .lagoonFont(12, .semibold)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(background))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }

    private var background: Color {
        switch style {
        case .normal: return .white(0.14)
        case let .filled(color, _): return color
        case let .tinted(color): return color.opacity(0.25)
        }
    }

    private var foreground: Color {
        switch style {
        case .normal: return .white
        case let .filled(_, text): return text
        case let .tinted(color): return color
        }
    }
}

/// Botón de ícono circular.
struct CircleIconButton: View {
    let icon: MS
    var size: CGFloat = 44
    var iconSize: CGFloat = 22
    var background: Color = .white(0.12)
    var foreground: Color = .white
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(icon, size: iconSize, color: foreground)
                .frame(width: size, height: size)
                .background(Circle().fill(background))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Ícono pulsable sin fondo (controles de reproducción, etc.).
struct IconButton: View {
    let icon: MS
    var size: CGFloat
    var color: Color? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(icon, size: size, color: color)
                .contentShape(Rectangle().inset(by: -6))
        }
        .buttonStyle(PressableStyle())
    }
}

/// "‹ Inicio" para volver desde las subpáginas de Inicio.
struct BackLink: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Icon(.chevronLeft, size: 14)
                Text("Inicio").lagoonFont(11)
            }
            .foregroundStyle(Palette.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Controles

/// Control segmentado (Timer / Cronómetro / Pomodoro, 1× / 2×).
struct SegmentedPill<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    @Namespace var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.0 == selection
                Text(option.1)
                    .lagoonFont(12, .semibold)
                    .foregroundStyle(selected ? Color.white : Palette.secondary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.white(0.2))
                                .matchedGeometryEffect(id: "segment", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(Motion.tab) { selection = option.0 }
                    }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white(0.1)))
        .fixedSize()
    }
}

/// Interruptor de 34 × 20 pt.
struct LagoonToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? Palette.cyan : Color.white(0.2))
            Circle().fill(.white).frame(width: 16, height: 16).padding(2)
        }
        .frame(width: 34, height: 20)
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(Motion.reduced ? Motion.fade : .spring(response: 0.25, dampingFraction: 0.8)) { isOn.toggle() }
        }
    }
}

/// Barra de progreso lineal.
struct ProgressBar: View {
    var value: Double
    var color: Color = .white
    var track: Color = .white(0.16)
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, value)) * proxy.size.width)
            }
        }
        .frame(height: height)
    }
}

/// Barra deslizable (volumen, brillo): 24 pt de alto, relleno blanco.
struct SliderBar: View {
    var value: Double
    var height: CGFloat = 24
    var onChange: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white(0.14))
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(height, max(0, min(1, value)) * proxy.size.width))
                    .opacity(value <= 0.001 ? 0 : 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        onChange(max(0, min(1, g.location.x / max(1, proxy.size.width))))
                    }
            )
        }
        .frame(height: height)
        .animation(Motion.hudStep, value: value)
    }
}

// MARK: - Indicadores

/// Pila dibujada como en el prototipo (borde 1,5 pt, relleno con margen, "polo" al 60 %).
struct BatteryGlyph: View {
    var level: Double
    var color: Color
    var width: CGFloat = 20
    var height: CGFloat = 10

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.3)
                    .strokeBorder(color, lineWidth: 1.5)
                RoundedRectangle(cornerRadius: height * 0.15)
                    .fill(color)
                    .frame(width: max(0, (width - 6) * min(1, level)), height: height - 6)
                    .padding(.leading, 3)
            }
            .frame(width: width, height: height)
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 1, topTrailingRadius: 1)
                .fill(color)
                .frame(width: 2, height: height * 0.4)
                .opacity(0.6)
        }
    }
}

/// Anillo de progreso (conic-gradient del prototipo).
struct RingProgress: View {
    var value: Double
    var color: Color
    var lineWidth: CGFloat
    var track: Color = .white(0.14)

    var body: some View {
        ZStack {
            Circle().inset(by: lineWidth / 2).stroke(track, lineWidth: lineWidth)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: max(0, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Tarjeta: rgba(255,255,255,.07), radio 16.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 12
    var radius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius).fill(Palette.card))
    }
}

extension View {
    func card(padding: CGFloat = 12, radius: CGFloat = 16) -> some View {
        modifier(CardBackground(padding: padding, radius: radius))
    }
}

/// Borde discontinuo redondeado (zonas para soltar, estados vacíos).
struct DashedBorder: View {
    var radius: CGFloat
    var color: Color
    var lineWidth: CGFloat = 1.5

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .strokeBorder(color, style: StrokeStyle(lineWidth: lineWidth, dash: [4, 3]))
    }
}

// MARK: - Portada y relleno a rayas

/// Relleno a rayas diagonales (el marcador de posición del prototipo).
struct StripedFill: View {
    var a: Color
    var b: Color
    var stripe: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(a))
            let step = stripe * 2 * 1.4142
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                // Bandas "/" como repeating-linear-gradient(135deg, …).
                var p = Path()
                let w = stripe * 1.4142
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + w, y: size.height))
                p.addLine(to: CGPoint(x: x + w + size.height, y: 0))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                p.closeSubpath()
                context.fill(p, with: .color(b))
                x += step
            }
        }
    }
}

/// Portada del disco con marcador a rayas cuando no hay imagen.
struct ArtworkView: View {
    var image: NSImage?
    var size: CGFloat
    var radius: CGFloat
    var label: String? = nil

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                StripedFill(a: Color(hex: 0x6B3446), b: Color(hex: 0x7A3D51), stripe: 5)
                if let label {
                    Text(label)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white(0.5))
                } else if size >= 40 {
                    Icon(.musicNote, size: size * 0.36, color: .white(0.5))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

// MARK: - Onda de audio (Core Animation: no despierta la app en cada fotograma)

struct Waveform: View {
    var heights: [CGFloat]
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 2
    var color: NSColor
    var animating: Bool

    var body: some View {
        let width = CGFloat(heights.count) * barWidth + CGFloat(max(0, heights.count - 1)) * spacing
        Group {
            if AppEnvironment.isSnapshot {
                HStack(spacing: spacing) {
                    ForEach(Array(heights.enumerated()), id: \.offset) { _, h in
                        RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: color)).frame(width: barWidth, height: h)
                    }
                }
            } else {
                WaveformRepresentable(heights: heights, barWidth: barWidth, spacing: spacing,
                                      color: color, animating: animating)
            }
        }
        .frame(width: width, height: 24)
    }
}

private struct WaveformRepresentable: NSViewRepresentable {
    var heights: [CGFloat]
    var barWidth: CGFloat
    var spacing: CGFloat
    var color: NSColor
    var animating: Bool

    func makeNSView(context: Context) -> WaveformNSView {
        WaveformNSView(heights: heights, barWidth: barWidth, spacing: spacing)
    }

    func updateNSView(_ view: WaveformNSView, context: Context) {
        view.setColor(color)
        view.setAnimating(animating)
    }
}

final class WaveformNSView: NSView {
    private let heights: [CGFloat]
    private let barWidth: CGFloat
    private let spacing: CGFloat
    private var bars: [CALayer] = []
    private var animating = false
    private var color: NSColor = .lagoonPink
    private let durations: [CFTimeInterval] = [0.52, 0.38, 0.61, 0.44, 0.57, 0.41, 0.49]
    private var powerObserver: NSObjectProtocol?

    init(heights: [CGFloat], barWidth: CGFloat, spacing: CGFloat) {
        self.heights = heights
        self.barWidth = barWidth
        self.spacing = spacing
        super.init(frame: .zero)
        wantsLayer = true
        for _ in heights {
            let bar = CALayer()
            bar.backgroundColor = color.cgColor
            bar.cornerRadius = min(2, barWidth / 2)
            layer?.addSublayer(bar)
            bars.append(bar)
        }
        // Con el modo de bajo consumo la onda se queda quieta (es la única animación continua).
        powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange,
                                                               object: nil, queue: .main) { [weak self] _ in
            self?.applyAnimations()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: heights[i])
            bar.position = CGPoint(x: CGFloat(i) * (barWidth + spacing) + barWidth / 2, y: bounds.midY)
        }
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAnimations()
    }

    func setColor(_ newColor: NSColor) {
        guard newColor != color else { return }
        color = newColor
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.5)
        bars.forEach { $0.backgroundColor = newColor.cgColor }
        CATransaction.commit()
    }

    func setAnimating(_ value: Bool) {
        guard value != animating else { return }
        animating = value
        applyAnimations()
    }

    private func applyAnimations() {
        let maxHeight = heights.max() ?? 24
        let now = CACurrentMediaTime()
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        for (i, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: "wave")
            guard animating, window != nil, !Motion.reduced, !lowPower else { continue }
            let animation = CABasicAnimation(keyPath: "bounds.size.height")
            animation.fromValue = max(3, heights[i] * 0.35)
            animation.toValue = min(maxHeight * 1.15, max(heights[i], maxHeight * 0.8))
            animation.duration = durations[i % durations.count]
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.beginTime = now + Double(i) * 0.07
            animation.isRemovedOnCompletion = false
            bar.add(animation, forKey: "wave")
        }
    }
}

// MARK: - Scroll (en capturas se dibuja sin NSScrollView)

struct LagoonScrollView<Content: View>: View {
    var axis: Axis.Set = .vertical
    @ViewBuilder var content: Content

    var body: some View {
        if AppEnvironment.isSnapshot {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        } else {
            ScrollView(axis, showsIndicators: false) { content }
        }
    }
}
