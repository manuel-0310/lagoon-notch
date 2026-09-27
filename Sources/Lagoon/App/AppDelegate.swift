import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: AppState?
    private var notchController: NotchController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        let screen = NotchGeometry.preferredScreen()
        let state = AppState(geometry: screen.map { NotchGeometry.detect(on: $0) } ?? .preview)
        state.openSettings = { [weak self] in self?.showSettings() }
        self.state = state

        let controller = NotchController(app: state)
        controller.start()
        notchController = controller
        state.startServices()

        if !Prefs.bool(Prefs.didShowWelcome) {
            Prefs.defaults.set(true, forKey: Prefs.didShowWelcome)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                state.notch.post(.welcome)
            }
        }
    }

    /// Abrir la app otra vez desde el Finder o el Launchpad muestra los Ajustes.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        notchController?.stop()
        state?.camera.stop()
        state?.music.stop()
        state?.claude.stop()
        state?.mediaKeys.stop()
    }

    func showSettings() {
        guard let state else { return }
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView().environment(state))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Ajustes de Lagoon"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 520, height: 600))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
