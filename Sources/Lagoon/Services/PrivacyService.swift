import AppKit
import CoreAudio
import CoreMediaIO
import Observation
import SwiftUI

enum PrivacyKind: String, CaseIterable {
    case camera, microphone, screen

    var color: Color {
        switch self {
        case .camera: return Palette.green
        case .microphone: return Palette.orange
        case .screen: return Palette.red
        }
    }

    var icon: MS {
        switch self {
        case .camera: return .videocam
        case .microphone: return .mic
        case .screen: return .screenRecord
        }
    }

    var label: String {
        switch self {
        case .camera: return "la cámara"
        case .microphone: return "el micrófono"
        case .screen: return "la pantalla"
        }
    }
}

struct PrivacyAlert: Equatable {
    var kind: PrivacyKind
    var appName: String?

    var title: String {
        switch kind {
        case .camera: return "Cámara en uso"
        case .microphone: return "Micrófono en uso"
        case .screen: return "Se está grabando la pantalla"
        }
    }

    var subtitle: String {
        if let appName { return kind == .screen ? "\(appName) está capturando" : "\(appName) está usando \(kind.label)" }
        return kind == .screen ? "Alguna app está capturando la pantalla" : "Alguna app está usando \(kind.label)"
    }
}

/// Cámara, micrófono y grabación de pantalla en uso por otras apps.
///
/// Cámara y micrófono funcionan por avisos del sistema (CoreMediaIO y Core Audio) y no necesitan
/// permisos. La grabación de pantalla no tiene API pública: se consulta una función privada
/// cada 3 s (una llamada barata, con margen para que el sistema agrupe los despertares).
@Observable
final class PrivacyService {
    var cameraInUse = false
    var microphoneInUse = false
    var microphoneApps: [String] = []
    var screenRecording = false

    @ObservationIgnored weak var notch: NotchViewModel?
    /// La cámara del propio espejo no cuenta.
    @ObservationIgnored var ownCameraActive: () -> Bool = { false }

    @ObservationIgnored private var cameraListeners: [(CMIOObjectID, CMIOObjectPropertyAddress, CMIOObjectPropertyListenerBlock)] = []
    @ObservationIgnored private var audioListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    @ObservationIgnored private var screenTimer: DispatchSourceTimer?
    @ObservationIgnored private var lastAlert: [PrivacyKind: Date] = [:]
    @ObservationIgnored private var started = false

    /// Indicadores activos, en el orden en que se dibujan.
    var activeKinds: [PrivacyKind] {
        guard Prefs.bool(Prefs.showPrivacyIndicators) else { return [] }
        var kinds: [PrivacyKind] = []
        if cameraInUse { kinds.append(.camera) }
        if microphoneInUse { kinds.append(.microphone) }
        if screenRecording { kinds.append(.screen) }
        return kinds
    }

    // MARK: - Ciclo de vida

    func start() {
        guard !started else { return }
        started = true
        installCameraListeners()
        installAudioListeners()
        applyScreenPreference()
    }

    /// Se llama al cambiar las preferencias.
    func applyScreenPreference() {
        let wanted = Prefs.bool(Prefs.detectScreenRecording) && ScreenWatcher.isAvailable
        if wanted, screenTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + 1, repeating: 3, leeway: .seconds(1))
            timer.setEventHandler { [weak self] in self?.checkScreen() }
            timer.resume()
            screenTimer = timer
        } else if !wanted, let timer = screenTimer {
            timer.cancel()
            screenTimer = nil
            if screenRecording { screenRecording = false }
        }
    }

    // MARK: - Cámara (CoreMediaIO)

    private func installCameraListeners() {
        var devicesAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let systemObject = CMIOObjectID(kCMIOObjectSystemObject)
        let devicesBlock: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.reinstallCameraDeviceListeners() }
        }
        if CMIOObjectAddPropertyListenerBlock(systemObject, &devicesAddress, DispatchQueue.main, devicesBlock) == noErr {
            cameraListeners.append((systemObject, devicesAddress, devicesBlock))
        }
        reinstallCameraDeviceListeners()
    }

    private func reinstallCameraDeviceListeners() {
        // Quita los de dispositivos (deja el de la lista, que es el primero).
        for (id, address, block) in cameraListeners.dropFirst() {
            var address = address
            CMIOObjectRemovePropertyListenerBlock(id, &address, DispatchQueue.main, block)
        }
        cameraListeners = Array(cameraListeners.prefix(1))

        for device in Self.cameraDevices() {
            var address = Self.runningAddress
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                DispatchQueue.main.async { self?.refreshCamera() }
            }
            if CMIOObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main, block) == noErr {
                cameraListeners.append((device, address, block))
            }
        }
        refreshCamera()
    }

    private static var runningAddress: CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func cameraDevices() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &ids) == noErr else { return [] }
        return ids
    }

    private func refreshCamera() {
        var running = false
        for device in Self.cameraDevices() {
            var address = Self.runningAddress
            var value: UInt32 = 0
            var used: UInt32 = 0
            if CMIOObjectGetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == noErr,
               value != 0 {
                running = true
                break
            }
        }
        if running, ownCameraActive() { running = false }
        guard running != cameraInUse else { return }
        cameraInUse = running
        if running { alert(.camera, appName: nil) }
    }

    // MARK: - Micrófono (Core Audio)

    private func installAudioListeners() {
        addAudioListener(object: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDevices) { [weak self] in
            self?.reinstallMicrophoneListeners()
        }
        if #available(macOS 14.2, *) {
            addAudioListener(object: AudioObjectID(kAudioObjectSystemObject),
                             selector: kAudioHardwarePropertyProcessObjectList) { [weak self] in
                self?.refreshMicrophone()
            }
        }
        reinstallMicrophoneListeners()
    }

    private func addAudioListener(object: AudioObjectID, selector: AudioObjectPropertySelector,
                                  handler: @escaping () -> Void) {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async(execute: handler)
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block) == noErr {
            audioListeners.append((object, address, block))
        }
    }

    private func reinstallMicrophoneListeners() {
        // Los de sistema (lista de dispositivos y de procesos) se conservan.
        let system = AudioObjectID(kAudioObjectSystemObject)
        for (id, address, block) in audioListeners where id != system {
            var address = address
            AudioObjectRemovePropertyListenerBlock(id, &address, DispatchQueue.main, block)
        }
        audioListeners.removeAll { $0.0 != system }
        for device in Self.inputDevices() {
            addAudioListener(object: device, selector: kAudioDevicePropertyDeviceIsRunningSomewhere) { [weak self] in
                self?.refreshMicrophone()
            }
        }
        refreshMicrophone()
    }

    private static func inputDevices() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { device in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                     mScope: kAudioObjectPropertyScopeInput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            return AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr && streamSize > 0
        }
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    /// Procesos del sistema que escuchan el micrófono sin que el usuario lo sepa (Siri, dictado).
    private static let ignoredBundlePrefixes = ["com.apple.corespeech", "com.apple.siri", "com.apple.assistant",
                                                "com.apple.SpeechRecognitionCore", "com.apple.controlcenter"]

    private func refreshMicrophone() {
        var apps: [String] = []
        var running: Bool
        if #available(macOS 14.2, *) {
            let processes = Self.inputProcesses()
            apps = processes
            running = !processes.isEmpty
            // Si la lista de procesos no está disponible, se usa el indicador del dispositivo.
            if processes.isEmpty, Self.processListUnavailable {
                running = Self.inputDevices().contains { Self.uint32($0, kAudioDevicePropertyDeviceIsRunningSomewhere) ?? 0 != 0 }
            }
        } else {
            running = Self.inputDevices().contains { Self.uint32($0, kAudioDevicePropertyDeviceIsRunningSomewhere) ?? 0 != 0 }
        }
        if apps != microphoneApps { microphoneApps = apps }
        guard running != microphoneInUse else { return }
        microphoneInUse = running
        if running { alert(.microphone, appName: apps.first) }
    }

    private static var processListUnavailable = false

    /// Apps que están grabando del micrófono (macOS 14.2+).
    @available(macOS 14.2, *)
    private static func inputProcesses() -> [String] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
            processListUnavailable = true
            return []
        }
        processListUnavailable = false
        guard size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var names: [String] = []
        for process in ids {
            guard uint32(process, kAudioProcessPropertyIsRunningInput) ?? 0 != 0 else { continue }
            var pidAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID,
                                                        mScope: kAudioObjectPropertyScopeGlobal,
                                                        mElement: kAudioObjectPropertyElementMain)
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(process, &pidAddress, 0, nil, &pidSize, &pid) == noErr,
                  pid != ownPID else { continue }
            let app = NSRunningApplication(processIdentifier: pid)
            let bundleID = app?.bundleIdentifier ?? ""
            if ignoredBundlePrefixes.contains(where: { bundleID.hasPrefix($0) }) { continue }
            let name = Self.displayName(for: app, pid: pid)
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// Los procesos auxiliares ("Google Chrome Helper") se muestran con el nombre de su app.
    private static func displayName(for app: NSRunningApplication?, pid: pid_t) -> String {
        if let url = app?.bundleURL {
            var candidate = url
            while candidate.pathComponents.count > 1 {
                candidate.deleteLastPathComponent()
                if candidate.pathExtension == "app",
                   let bundle = Bundle(url: candidate),
                   let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
                    return name
                }
            }
        }
        return app?.localizedName ?? "Una app"
    }

    // MARK: - Grabación de pantalla

    private func checkScreen() {
        let recording = ScreenWatcher.isPresent()
        guard recording != screenRecording else { return }
        screenRecording = recording
        if recording { alert(.screen, appName: nil) }
    }

    // MARK: - Avisos

    private func alert(_ kind: PrivacyKind, appName: String?) {
        guard Prefs.bool(Prefs.showPrivacyAlerts) else { return }
        // No repetir el aviso si se enciende y se apaga varias veces seguidas.
        if let last = lastAlert[kind], Date().timeIntervalSince(last) < 20 { return }
        lastAlert[kind] = Date()
        notch?.post(.privacyStarted(PrivacyAlert(kind: kind, appName: appName)))
    }
}

/// `CGSIsScreenWatcherPresent` (SkyLight, privada): true mientras alguna app captura la pantalla.
enum ScreenWatcher {
    private typealias Function = @convention(c) () -> Bool

    private static let function: Function? = {
        let paths = ["/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
                     "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"]
        for path in paths {
            guard let handle = dlopen(path, RTLD_LAZY) else { continue }
            for name in ["SLSIsScreenWatcherPresent", "CGSIsScreenWatcherPresent"] {
                if let symbol = dlsym(handle, name) {
                    return unsafeBitCast(symbol, to: Function.self)
                }
            }
        }
        return nil
    }()

    static var isAvailable: Bool { function != nil }

    static func isPresent() -> Bool { function?() ?? false }
}
