import AppKit
import AudioToolbox
import CoreAudio
import Observation

struct AudioOutput: Identifiable, Equatable {
    enum Kind: Equatable {
        case builtIn, headphones, speaker, tv, display, group

        var icon: MS {
            switch self {
            case .builtIn: return .laptopMac
            case .headphones: return .headphones
            case .speaker: return .speaker
            case .tv: return .tv
            case .display: return .monitor
            case .group: return .speakerGroup
            }
        }
    }

    let id: UInt32
    var name: String
    var kind: Kind
}

/// Volumen, salida de audio (Core Audio) y brillo de la pantalla integrada.
@Observable
final class AudioService {
    var volume: Double = 0.5
    var isMuted = false
    var outputs: [AudioOutput] = []
    var currentOutputID: UInt32?
    var brightness: Double = 0.5
    var brightnessAvailable = false

    @ObservationIgnored weak var notch: NotchViewModel?
    @ObservationIgnored private var listenedDevice: AudioDeviceID = 0
    @ObservationIgnored private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    @ObservationIgnored private var suppressHUDUntil = Date()
    @ObservationIgnored private var lastUserChange = Date.distantPast
    @ObservationIgnored private let display = BuiltInDisplay()

    // MARK: - Arranque

    func start() {
        suppressHUDUntil = Date().addingTimeInterval(2)
        addSystemListener(selector: kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
            self?.defaultDeviceChanged()
        }
        addSystemListener(selector: kAudioHardwarePropertyDevices) { [weak self] in
            self?.refreshOutputs()
        }
        defaultDeviceChanged()
        refreshOutputs()
        readBrightness()
    }

    private func addSystemListener(selector: AudioObjectPropertySelector, handler: @escaping () -> Void) {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { _, _ in
            handler()
        }
    }

    private func defaultDeviceChanged() {
        guard let device = Self.defaultOutputDevice() else { return }
        suppressHUDUntil = Date().addingTimeInterval(1)
        if device != listenedDevice {
            removeDeviceListeners()
            listenedDevice = device
            addDeviceListeners(device)
        }
        currentOutputID = device
        readVolume(showHUD: false)
    }

    private func addDeviceListeners(_ device: AudioDeviceID) {
        let selectors: [(AudioObjectPropertySelector, AudioObjectPropertyElement)] = [
            (kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, 1),
            (kAudioDevicePropertyMute, kAudioObjectPropertyElementMain),
        ]
        for (selector, element) in selectors {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                                     mElement: element)
            guard AudioObjectHasProperty(device, &address) else { continue }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.readVolume(showHUD: true)
            }
            if AudioObjectAddPropertyListenerBlock(device, &address, .main, block) == noErr {
                deviceListeners.append((address, block))
            }
        }
    }

    private func removeDeviceListeners() {
        for (address, block) in deviceListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(listenedDevice, &address, .main, block)
        }
        deviceListeners.removeAll()
    }

    // MARK: - Volumen

    private func readVolume(showHUD: Bool) {
        guard let device = Self.defaultOutputDevice() else { return }
        let newVolume = Double(Self.volume(of: device) ?? Float(volume))
        let newMuted = Self.isMuted(device)
        let changed = abs(newVolume - volume) > 0.001 || newMuted != isMuted
        volume = newVolume
        isMuted = newMuted
        guard showHUD, changed, Date() > suppressHUDUntil,
              Date().timeIntervalSince(lastUserChange) > 0.6,
              Prefs.bool(Prefs.showVolumeHUD) else { return }
        notch?.post(.volume)
    }

    /// Cambio desde el panel (arrastrando la barra).
    func setVolume(_ value: Double) {
        lastUserChange = Date()
        applyVolume(value)
    }

    private func applyVolume(_ value: Double) {
        guard let device = Self.defaultOutputDevice() else { return }
        let clamped = max(0, min(1, value))
        volume = clamped
        if clamped > 0, isMuted { Self.setMuted(device, false); isMuted = false }
        Self.setVolume(of: device, to: Float(clamped))
    }

    func toggleMute() {
        guard let device = Self.defaultOutputDevice() else { return }
        isMuted.toggle()
        Self.setMuted(device, isMuted)
    }

    /// Teclas de volumen (cuando Lagoon reemplaza el indicador de macOS).
    /// Devuelve `false` si el dispositivo no permite cambiar el volumen (la tecla sigue su curso).
    func handleVolumeKey(_ key: MediaKey, fine: Bool) -> Bool {
        guard let device = Self.defaultOutputDevice(), Self.canSetVolume(device) else { return false }
        let step = fine ? 1.0 / 64 : 1.0 / 16
        lastUserChange = Date()
        switch key {
        case .soundUp: applyVolume(((volume + step) / step).rounded() * step)
        case .soundDown: applyVolume(((volume - step) / step).rounded() * step)
        case .mute: toggleMute()
        default: return false
        }
        notch?.post(.volume)
        return true
    }

    // MARK: - Salidas

    func refreshOutputs() {
        outputs = Self.outputDevices()
        currentOutputID = Self.defaultOutputDevice()
    }

    func select(_ output: AudioOutput) {
        var id = AudioDeviceID(output.id)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &id) == noErr {
            currentOutputID = output.id
        }
    }

    // MARK: - Brillo

    func readBrightness() {
        if let value = display.brightness() {
            brightness = Double(value)
            brightnessAvailable = true
        } else {
            brightnessAvailable = false
        }
    }

    func setBrightness(_ value: Double) {
        let clamped = max(0, min(1, value))
        brightness = clamped
        display.setBrightness(Float(clamped))
    }

    var canControlBrightness: Bool { display.isAvailable }

    func handleBrightnessKey(_ key: MediaKey, fine: Bool) -> Bool {
        guard display.isAvailable else { return false }
        readBrightness()
        let step = fine ? 1.0 / 64 : 1.0 / 16
        switch key {
        case .brightnessUp: setBrightness(((brightness + step) / step).rounded() * step)
        case .brightnessDown: setBrightness(((brightness - step) / step).rounded() * step)
        default: return false
        }
        if Prefs.bool(Prefs.showVolumeHUD) { notch?.post(.brightness) }
        return true
    }

    // MARK: - Core Audio

    static func defaultOutputDevice() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != kAudioObjectUnknown ? id : nil
    }

    private static func volumeAddress(_ device: AudioDeviceID) -> AudioObjectPropertyAddress? {
        var main = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &main) { return main }
        var scalar = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                mScope: kAudioDevicePropertyScopeOutput,
                                                mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &scalar) { return scalar }
        scalar.mElement = 1
        if AudioObjectHasProperty(device, &scalar) { return scalar }
        return nil
    }

    static func volume(of device: AudioDeviceID) -> Float? {
        guard var address = volumeAddress(device) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func canSetVolume(_ device: AudioDeviceID) -> Bool {
        guard var address = volumeAddress(device) else { return false }
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    static func setVolume(of device: AudioDeviceID, to value: Float) {
        guard var address = volumeAddress(device) else { return }
        var volume = Float32(value)
        let size = UInt32(MemoryLayout<Float32>.size)
        if address.mSelector == kAudioDevicePropertyVolumeScalar && address.mElement != kAudioObjectPropertyElementMain {
            // Sin canal maestro: aplica a los dos canales.
            for channel: UInt32 in [1, 2] {
                address.mElement = channel
                if AudioObjectHasProperty(device, &address) {
                    AudioObjectSetPropertyData(device, &address, 0, nil, size, &volume)
                }
            }
        } else {
            AudioObjectSetPropertyData(device, &address, 0, nil, size, &volume)
        }
    }

    static func isMuted(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return value != 0
    }

    static func setMuted(_ device: AudioDeviceID, _ muted: Bool) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return }
        var value = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    static func outputDevices() -> [AudioOutput] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id -> AudioOutput? in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                     mScope: kAudioDevicePropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var streamSize = UInt32(0)
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
            let name = deviceName(id)
            guard !name.isEmpty, !name.hasPrefix("CADefault") else { return nil }
            return AudioOutput(id: id, name: name, kind: kind(of: id, name: name))
        }
    }

    private static func deviceName(_ id: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value = name?.takeRetainedValue() else { return "" }
        return value as String
    }

    private static func kind(of id: AudioDeviceID, name: String) -> AudioOutput.Kind {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
        let lower = name.lowercased()
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            let speakerHints = ["speaker", "altavoz", "homepod", "soundlink", "boom", "flip", "charge"]
            return speakerHints.contains(where: { lower.contains($0) }) ? .speaker : .headphones
        case kAudioDeviceTransportTypeAirPlay:
            return lower.contains("tv") ? .tv : .speaker
        case kAudioDeviceTransportTypeHDMI:
            return .tv
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeThunderbolt:
            return .display
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeVirtual:
            return .group
        default:
            return lower.contains("headphone") || lower.contains("auricular") ? .headphones : .speaker
        }
    }
}

/// Brillo de la pantalla integrada mediante DisplayServices (framework privado, cargado dinámicamente).
final class BuiltInDisplay {
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32

    private let getter: GetBrightness?
    private let setter: SetBrightness?
    private let displayID: CGDirectDisplayID?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        if let handle, let get = dlsym(handle, "DisplayServicesGetBrightness"), let set = dlsym(handle, "DisplayServicesSetBrightness") {
            getter = unsafeBitCast(get, to: GetBrightness.self)
            setter = unsafeBitCast(set, to: SetBrightness.self)
        } else {
            getter = nil
            setter = nil
        }
        displayID = Self.builtInDisplayID()
    }

    var isAvailable: Bool { getter != nil && setter != nil && displayID != nil }

    func brightness() -> Float? {
        guard let getter, let displayID else { return nil }
        var value: Float = 0
        return getter(displayID, &value) == 0 ? value : nil
    }

    func setBrightness(_ value: Float) {
        guard let setter, let displayID else { return }
        _ = setter(displayID, value)
    }

    private static func builtInDisplayID() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return nil }
        return ids.first { CGDisplayIsBuiltin($0) != 0 }
    }
}
