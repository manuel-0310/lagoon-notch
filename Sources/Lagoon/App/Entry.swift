import AppKit

@main
enum LagoonEntry {
    static func main() {
        MainActor.assumeIsolated {
            run()
        }
    }

    @MainActor
    private static func run() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshots"), index + 1 < arguments.count {
            SnapshotRenderer.run(outputDirectory: URL(fileURLWithPath: arguments[index + 1]))
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
