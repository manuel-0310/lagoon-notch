import Foundation
import IOKit.ps
import Observation
import SwiftUI

/// Batería del Mac. Sin sondeo: IOKit avisa cuando cambia la fuente de energía.
@Observable
final class BatteryService {
    var hasBattery = true
    var level = 100
    var isCharging = false
    var isPluggedIn = false
    var isCharged = false
    /// Minutos restantes en batería (nil = calculando).
    var minutesToEmpty: Int?
    /// Minutos hasta carga completa (nil = calculando).
    var minutesToFull: Int?
    var adapterWatts: Int?

    @ObservationIgnored weak var notch: NotchViewModel?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var initialized = false

    var fraction: Double { Double(level) / 100 }

    var tint: Color {
        if isCharging || isCharged || isPluggedIn { return Palette.green }
        if level <= Prefs.int(Prefs.lowBatteryThreshold) { return Palette.red }
        return .white
    }

    /// "Cargando" / "Cargada" / "Conectada" / "En batería"
    var shortStatus: String {
        if !hasBattery { return "Conectado" }
        if isCharging { return "Cargando" }
        if isCharged { return "Cargada" }
        if isPluggedIn { return "Conectada" }
        return "En batería"
    }

    /// "Cargando · lleno en 38 min"
    var detailStatus: String {
        if !hasBattery { return "Conectado a la corriente" }
        if isCharging {
            if let minutes = minutesToFull, minutes > 0 { return "Cargando · lleno en \(Formatters.hoursMinutes(minutes))" }
            return "Cargando"
        }
        if isCharged || (isPluggedIn && level >= 99) { return "Carga completa" }
        if isPluggedIn { return "Conectado · carga en pausa" }
        if let minutes = minutesToEmpty { return "En batería · quedan \(Formatters.hoursMinutes(minutes))" }
        return "En batería"
    }

    /// "5 h 12 min" (para el aviso "En batería").
    var remainingDescription: String {
        if let minutes = minutesToEmpty { return Formatters.hoursMinutes(minutes) }
        return "Calculando…"
    }

    /// "18 % · unos 42 min restantes"
    var lowBatterySubtitle: String {
        if let minutes = minutesToEmpty { return "\(level) % · unos \(Formatters.hoursMinutes(minutes)) restantes" }
        return "\(level) % · conecta el cargador"
    }

    /// "Adaptador USB-C de 70 W"
    var adapterDescription: String? {
        guard isPluggedIn else { return nil }
        if let watts = adapterWatts, watts > 0 { return "Adaptador USB-C de \(watts) W" }
        return "Conectado a la corriente"
    }

    func start() {
        read()
        initialized = true
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            service.read()
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
    }

    func read() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            hasBattery = false
            return
        }
        var found = false
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  description["Type"] as? String == "InternalBattery" else { continue }
            found = true
            let current = description["Current Capacity"] as? Int ?? 0
            let maximum = max(1, description["Max Capacity"] as? Int ?? 100)
            let newLevel = Int((Double(current) / Double(maximum) * 100).rounded())
            let newCharging = description["Is Charging"] as? Bool ?? false
            let newPlugged = (description["Power Source State"] as? String) == "AC Power"
            let newCharged = description["Is Charged"] as? Bool ?? false
            let toEmpty = description["Time to Empty"] as? Int ?? -1
            let toFull = description["Time to Full Charge"] as? Int ?? -1

            let previousPlugged = isPluggedIn
            let previousLevel = level

            if level != newLevel { level = newLevel }
            if isCharging != newCharging { isCharging = newCharging }
            if isPluggedIn != newPlugged { isPluggedIn = newPlugged }
            if isCharged != newCharged { isCharged = newCharged }
            minutesToEmpty = toEmpty > 0 && !newPlugged ? toEmpty : nil
            minutesToFull = toFull > 0 && newCharging ? toFull : nil

            if initialized {
                if !previousPlugged, newPlugged, Prefs.bool(Prefs.showChargerEvents) {
                    notch?.post(.chargerConnected)
                } else if previousPlugged, !newPlugged, Prefs.bool(Prefs.showChargerEvents) {
                    notch?.post(.chargerDisconnected)
                }
                let threshold = Prefs.int(Prefs.lowBatteryThreshold)
                if !newPlugged, newLevel <= threshold, previousLevel > threshold, Prefs.bool(Prefs.showLowBattery) {
                    notch?.post(.lowBattery)
                }
                if newPlugged {
                    notch?.dismiss { $0 == .lowBattery }
                }
            }
        }
        hasBattery = found
        readAdapter()
    }

    private func readAdapter() {
        guard isPluggedIn,
              let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else {
            adapterWatts = nil
            return
        }
        adapterWatts = details["Watts"] as? Int
    }
}
