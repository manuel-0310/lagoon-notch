import SwiftUI

/// Pestaña Sistema: seis tarjetas con valor grande y una línea de historial.
/// La medición solo corre mientras esta vista está en pantalla.
struct SystemView: View {
    @Environment(AppState.self) var app

    var body: some View {
        let system = app.system
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                SystemTile(icon: .developerBoard, title: "CPU", tint: Palette.cyan,
                           value: Self.percent(system.cpu),
                           detail: "\(system.coreCount) núcleos",
                           history: system.cpuHistory)
                SystemTile(icon: .memory, title: "Memoria", tint: Palette.purple,
                           value: Self.bytes(system.memoryUsed),
                           detail: "de \(Self.bytes(system.memoryTotal))",
                           history: system.memoryHistory,
                           fraction: system.memoryFraction)
                SystemTile(icon: .speed, title: "GPU", tint: Palette.green,
                           value: system.gpu.map(Self.percent) ?? "—",
                           detail: system.gpu == nil ? "No disponible" : "Uso del procesador gráfico",
                           history: system.gpuHistory)
            }
            GridRow {
                SystemTile(icon: .arrowDownward, title: "Red", tint: Palette.blue,
                           value: Self.rate(system.networkDown),
                           detail: "↑ " + Self.rate(system.networkUp),
                           history: system.networkHistory, scaleFloor: 64 * 1024)
                SystemTile(icon: .hardDrive, title: "Disco", tint: Palette.orange,
                           value: Self.bytes(UInt64(max(0, system.diskFree))) + " libres",
                           detail: "L " + Self.rate(system.diskRead) + " · E " + Self.rate(system.diskWrite),
                           history: [],
                           fraction: system.diskUsedFraction)
                SystemTile(icon: .deviceThermostat, title: "Temperatura", tint: thermalTint(system),
                           value: system.temperature.map { "\(Int($0.rounded())) °C" } ?? Self.thermalLabel(system.thermalState),
                           detail: system.temperature == nil ? "Estado térmico" : Self.thermalLabel(system.thermalState),
                           history: [])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .stagger(1)
        .onAppear { app.system.begin() }
        .onDisappear { app.system.end() }
    }

    private func thermalTint(_ system: SystemMonitorService) -> Color {
        switch system.thermalState {
        case .serious, .critical: return Palette.red
        case .fair: return Palette.orange
        default: return Palette.green
        }
    }

    // MARK: - Formatos

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded())) %"
    }

    static func bytes(_ value: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        f.allowedUnits = [.useMB, .useGB, .useTB]
        return f.string(fromByteCount: Int64(min(value, UInt64(Int64.max)))).replacingOccurrences(of: ".", with: ",")
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f.string(fromByteCount: Int64(max(0, bytesPerSecond))).replacingOccurrences(of: ".", with: ",") + "/s"
    }

    static func thermalLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Normal"
        case .fair: return "Templado"
        case .serious: return "Caliente"
        case .critical: return "Crítico"
        @unknown default: return "—"
        }
    }
}

struct SystemTile: View {
    let icon: MS
    let title: String
    let tint: Color
    let value: String
    let detail: String
    var history: [Double]
    /// Si se indica, se dibuja una barra en lugar de la línea de historial.
    var fraction: Double? = nil
    /// Escala mínima de la línea (para que un poco de tráfico no llene la gráfica).
    var scaleFloor: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Icon(icon, size: 13, color: tint)
                Text(title.uppercased()).sectionLabel()
            }
            Text(value)
                .lagoonFont(17, .semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 5)
            Text(detail)
                .lagoonFont(10.5)
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if let fraction {
                ProgressBar(value: fraction, color: tint, track: .white(0.12), height: 4)
            } else {
                Sparkline(values: history, color: tint, floor: scaleFloor)
                    .frame(height: 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: 10, radius: 14)
    }
}

/// Línea de historial con relleno suave.
struct Sparkline: View {
    var values: [Double]
    var color: Color
    var floor: Double = 1

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else {
                var base = Path()
                base.move(to: CGPoint(x: 0, y: size.height - 1))
                base.addLine(to: CGPoint(x: size.width, y: size.height - 1))
                context.stroke(base, with: .color(color.opacity(0.3)), lineWidth: 1)
                return
            }
            let top = max(floor, values.max() ?? 1)
            let count = SystemMonitorService.historyLength
            let step = size.width / CGFloat(max(1, count - 1))
            let offset = CGFloat(count - values.count) * step
            var line = Path()
            for (i, value) in values.enumerated() {
                let point = CGPoint(x: offset + CGFloat(i) * step,
                                    y: size.height - 1 - CGFloat(min(1, value / top)) * (size.height - 2))
                if i == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: offset, y: size.height))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(Gradient(colors: [color.opacity(0.35), color.opacity(0)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
    }
}
