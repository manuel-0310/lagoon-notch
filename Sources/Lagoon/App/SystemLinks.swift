import AppKit

/// Atajos a paneles de Ajustes del Sistema.
enum SystemLinks {
    enum Pane {
        case battery, camera, accessibility, location, automation, calendars, reminders, bluetooth, loginItems
    }

    static func open(_ pane: Pane) {
        let candidates: [String]
        switch pane {
        case .battery:
            candidates = ["x-apple.systempreferences:com.apple.Battery-Settings.extension",
                          "x-apple.systempreferences:com.apple.preference.battery"]
        case .camera:
            candidates = ["x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"]
        case .accessibility:
            candidates = ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]
        case .location:
            candidates = ["x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"]
        case .automation:
            candidates = ["x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"]
        case .calendars:
            candidates = ["x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"]
        case .reminders:
            candidates = ["x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"]
        case .bluetooth:
            candidates = ["x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"]
        case .loginItems:
            candidates = ["x-apple.systempreferences:com.apple.LoginItems-Settings.extension"]
        }
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }
}
