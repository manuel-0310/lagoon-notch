import Foundation
import IOBluetooth
import Observation

struct BatteryRing: Equatable {
    let label: String
    let level: Int
}

struct BluetoothDevice: Identifiable, Equatable {
    enum Kind: Equatable {
        case headphones, mouse, keyboard, trackpad, speaker, gamepad, other

        var icon: MS {
            switch self {
            case .headphones: return .headphones
            case .mouse: return .mouse
            case .keyboard: return .keyboard
            case .trackpad: return .tabletMac
            case .speaker: return .speaker
            case .gamepad: return .sportsEsports
            case .other: return .bluetooth
            }
        }
    }

    var id: String
    var name: String
    var kind: Kind
    var main: Int?
    var left: Int?
    var right: Int?
    var caseLevel: Int?

    /// Nivel general (el más bajo de los auriculares, como en el prototipo).
    var level: Int? {
        if let main { return main }
        let buds = [left, right].compactMap { $0 }
        return buds.min()
    }

    var hasBattery: Bool { level != nil }

    /// "Izq. 82 · Der. 80 · Estuche 64" o "Bluetooth".
    var detail: String {
        var parts: [String] = []
        if let left { parts.append("Izq. \(left)") }
        if let right { parts.append("Der. \(right)") }
        if let caseLevel { parts.append("Estuche \(caseLevel)") }
        return parts.isEmpty ? "Bluetooth" : parts.joined(separator: " · ")
    }

    var batteryRings: [BatteryRing] {
        var rings: [BatteryRing] = []
        if let left { rings.append(BatteryRing(label: "Izq.", level: left)) }
        if let right { rings.append(BatteryRing(label: "Der.", level: right)) }
        if let caseLevel { rings.append(BatteryRing(label: "Estuche", level: caseLevel)) }
        if rings.isEmpty, let main { rings.append(BatteryRing(label: "Batería", level: main)) }
        return rings
    }
}

/// Dispositivos Bluetooth con batería (AirPods, Magic Mouse, teclados…).
///
/// La lista se lee con `system_profiler` solo cuando hace falta (al abrir el detalle
/// o al conectarse unos auriculares), nunca en bucle.
@Observable
final class BluetoothService {
    var devices: [BluetoothDevice] = []
    var macName = Host.current().localizedName ?? "Este Mac"
    var isLoading = false

    @ObservationIgnored weak var notch: NotchViewModel?
    @ObservationIgnored private var watcher: BluetoothConnectWatcher?
    @ObservationIgnored private let queue = DispatchQueue(label: "app.lagoon.bluetooth", qos: .utility)
    @ObservationIgnored private var lastRefresh = Date.distantPast
    @ObservationIgnored private var startedAt = Date()

    func start() {
        startedAt = Date()
        loadMacName()
        let watcher = BluetoothConnectWatcher { [weak self] name, address, isAudio in
            self?.deviceConnected(name: name, address: address, isAudio: isAudio)
        }
        watcher.start()
        self.watcher = watcher
    }

    func refresh(force: Bool = false, completion: (() -> Void)? = nil) {
        if !force, Date().timeIntervalSince(lastRefresh) < 20 {
            completion?()
            return
        }
        lastRefresh = Date()
        isLoading = devices.isEmpty
        queue.async {
            let parsed = Self.readDevices()
            DispatchQueue.main.async {
                self.devices = parsed
                self.isLoading = false
                completion?()
            }
        }
    }

    private func deviceConnected(name: String, address: String, isAudio: Bool) {
        // Ignora las conexiones que ya existían al arrancar la app.
        guard Date().timeIntervalSince(startedAt) > 5, isAudio, Prefs.bool(Prefs.showAirPods) else { return }
        // La batería de los AirPods tarda un par de segundos en publicarse.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.refresh(force: true) {
                guard let self else { return }
                let key = Self.normalize(address)
                let match = self.devices.first { Self.normalize($0.id) == key }
                    ?? self.devices.first { $0.name == name }
                if let match, match.hasBattery, match.kind == .headphones || match.left != nil {
                    self.notch?.post(.airPodsConnected(match))
                }
            }
        }
    }

    private func loadMacName() {
        queue.async {
            guard let data = Self.systemProfiler(["SPHardwareDataType"]),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["SPHardwareDataType"] as? [[String: Any]],
                  let name = items.first?["machine_name"] as? String else { return }
            DispatchQueue.main.async { self.macName = name }
        }
    }

    // MARK: - system_profiler

    private static func normalize(_ address: String) -> String {
        address.lowercased().filter { $0.isHexDigit }
    }

    private static func systemProfiler(_ types: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "-detailLevel", "basic"] + types
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }

    private static func readDevices() -> [BluetoothDevice] {
        guard let data = systemProfiler(["SPBluetoothDataType"]),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = json["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var result: [BluetoothDevice] = []
        for controller in controllers {
            guard let connected = controller["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (name, value) in entry {
                    guard let props = value as? [String: Any] else { continue }
                    let device = BluetoothDevice(
                        id: props["device_address"] as? String ?? name,
                        name: name,
                        kind: kind(for: props["device_minorType"] as? String, name: name),
                        main: percent(props["device_batteryLevelMain"] ?? props["device_batteryLevel"]),
                        left: percent(props["device_batteryLevelLeft"]),
                        right: percent(props["device_batteryLevelRight"]),
                        caseLevel: percent(props["device_batteryLevelCase"])
                    )
                    if device.hasBattery { result.append(device) }
                }
            }
        }
        return result.sorted { ($0.kind == .headphones ? 0 : 1, $0.name) < ($1.kind == .headphones ? 0 : 1, $1.name) }
    }

    private static func percent(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        guard let string = value as? String else { return nil }
        return Int(string.filter { $0.isNumber })
    }

    private static func kind(for minorType: String?, name: String) -> BluetoothDevice.Kind {
        let type = (minorType ?? "").lowercased()
        let lower = name.lowercased()
        if type.contains("headphone") || type.contains("headset") || lower.contains("airpods")
            || lower.contains("beats") || lower.contains("buds") { return .headphones }
        if type.contains("mouse") || lower.contains("mouse") { return .mouse }
        if type.contains("keyboard") || lower.contains("keyboard") || lower.contains("teclado") { return .keyboard }
        if type.contains("trackpad") || lower.contains("trackpad") { return .trackpad }
        if type.contains("speaker") || type.contains("loudspeaker") { return .speaker }
        if type.contains("gamepad") || type.contains("joystick") || lower.contains("controller") { return .gamepad }
        return .other
    }
}

/// Recibe los avisos de conexión de IOBluetooth (necesita un NSObject para el selector).
final class BluetoothConnectWatcher: NSObject {
    private let handler: (String, String, Bool) -> Void
    private var notification: IOBluetoothUserNotification?

    init(handler: @escaping (String, String, Bool) -> Void) {
        self.handler = handler
    }

    func start() {
        notification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                  selector: #selector(deviceConnected(_:device:)))
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification?, device: IOBluetoothDevice?) {
        guard let device else { return }
        // Clase mayor 0x04 = audio/vídeo (auriculares, altavoces).
        let isAudio = device.deviceClassMajor == 0x04
        let name = device.name ?? "Auriculares"
        let address = device.addressString ?? ""
        DispatchQueue.main.async { self.handler(name, address, isAudio) }
    }
}
