import AppKit
import ApplicationServices

/// Teclas multimedia (NX_KEYTYPE_*).
enum MediaKey: Int {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
}

/// Intercepta las teclas de volumen y brillo para mostrar el indicador de Lagoon
/// en lugar del de macOS. Requiere permiso de Accesibilidad.
final class MediaKeyTap {
    /// Devuelve `true` si Lagoon se encarga de la tecla (y el sistema no la verá).
    var handler: ((MediaKey, _ isDown: Bool, _ fine: Bool) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Pide el permiso de Accesibilidad mostrando el aviso del sistema.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard Self.isTrusted else { return false }
        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
            return tap.handle(type: type, event: event)
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                           place: .headInsertEventTap,
                                           options: .defaultTap,
                                           eventsOfInterest: mask,
                                           callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == 14,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let data = nsEvent.data1
        let keyCode = (data & 0xFFFF_0000) >> 16
        let flags = data & 0x0000_FFFF
        let isDown = ((flags & 0xFF00) >> 8) == 0xA
        guard let key = MediaKey(rawValue: keyCode), let handler else {
            return Unmanaged.passUnretained(event)
        }
        let modifiers = nsEvent.modifierFlags
        let fine = modifiers.contains(.option) && modifiers.contains(.shift)
        return handler(key, isDown, fine) ? nil : Unmanaged.passUnretained(event)
    }
}
