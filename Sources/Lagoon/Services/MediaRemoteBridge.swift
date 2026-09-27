import Foundation

/// Puente con `mediaremote-adapter` (Vendor/mediaremote-adapter, BSD-3).
///
/// Desde macOS 15.4 solo los procesos de Apple pueden leer "Ahora suena". El adaptador carga un
/// framework pequeño dentro de `/usr/bin/perl` y escribe cada cambio como una línea JSON.
/// Es un proceso vivo que empuja los cambios: no hay sondeo.
final class MediaRemoteBridge {
    struct Paths {
        let script: String
        let framework: String
        let testClient: String
    }

    /// Recursos copiados por `scripts/build-app.sh`. nil al ejecutar sin empaquetar (`swift run`).
    static let paths: Paths? = {
        let contents = Bundle.main.bundleURL.appendingPathComponent("Contents")
        let paths = Paths(script: contents.appendingPathComponent("Resources/mediaremote-adapter.pl").path,
                          framework: contents.appendingPathComponent("Frameworks/MediaRemoteAdapter.framework").path,
                          testClient: contents.appendingPathComponent("Helpers/MediaRemoteAdapterTestClient").path)
        let fm = FileManager.default
        guard fm.fileExists(atPath: paths.script), fm.fileExists(atPath: paths.framework),
              fm.fileExists(atPath: "/usr/bin/perl") else { return nil }
        return paths
    }()

    /// Estado completo (los mensajes con `diff` solo traen lo que cambió).
    var onUpdate: ([String: Any]) -> Void = { _ in }
    /// El adaptador dejó de funcionar (varios cierres seguidos): hay que volver a AppleScript.
    var onFailure: () -> Void = {}

    private var process: Process?
    private var buffer = Data()
    private var state: [String: Any] = [:]
    private var stopped = true
    private var quickFailures = 0
    private var startedAt = Date()
    private let readQueue = DispatchQueue(label: "app.lagoon.mediaremote", qos: .userInitiated)
    private let commandQueue = DispatchQueue(label: "app.lagoon.mediaremote.commands", qos: .userInitiated)

    // MARK: - Comprobación

    /// `test`: código 0 = el adaptador funciona en esta versión de macOS.
    static func test(completion: @escaping (Bool) -> Void) {
        guard let paths else {
            completion(false)
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let status = run([paths.script, paths.framework, paths.testClient, "test"], timeout: 8)
            DispatchQueue.main.async { completion(status == 0) }
        }
    }

    // MARK: - Flujo

    func start() {
        guard let paths = Self.paths, process == nil else { return }
        stopped = false
        startedAt = Date()
        state = [:]
        buffer = Data()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.script, paths.framework, "stream", "--micros", "--debounce=80"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.readQueue.async { self?.consume(data) }
        }
        process.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { self?.processEnded() }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            onFailure()
        }
    }

    func stop() {
        stopped = true
        process?.terminate()
        process = nil
    }

    private func processEnded() {
        process = nil
        guard !stopped else { return }
        // Reinicio con espera creciente; si muere nada más arrancar varias veces, se abandona.
        if Date().timeIntervalSince(startedAt) < 10 { quickFailures += 1 } else { quickFailures = 0 }
        if quickFailures >= 4 {
            stopped = true
            onFailure()
            return
        }
        let delay = min(30, pow(2, Double(quickFailures)))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.stopped else { return }
            self.start()
        }
    }

    /// Junta los trozos leídos y procesa cada línea completa (se ejecuta en `readQueue`).
    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let payload = object["payload"] as? [String: Any] else { continue }
            let diff = object["diff"] as? Bool ?? false
            if diff {
                for (key, value) in payload {
                    if value is NSNull { state.removeValue(forKey: key) } else { state[key] = value }
                }
            } else {
                state = payload
            }
            let snapshot = state
            DispatchQueue.main.async { [weak self] in self?.onUpdate(snapshot) }
        }
    }

    // MARK: - Controles

    enum Command: Int {
        case play = 0, pause = 1, togglePlayPause = 2, next = 4, previous = 5
    }

    func send(_ command: Command) {
        runCommand(["send", String(command.rawValue)])
    }

    func seek(to seconds: Double) {
        runCommand(["seek", String(Int64(max(0, seconds) * 1_000_000))])
    }

    func setShuffle(_ on: Bool) {
        runCommand(["shuffle", on ? "3" : "1"])
    }

    private func runCommand(_ arguments: [String]) {
        guard let paths = Self.paths else { return }
        commandQueue.async {
            _ = Self.run([paths.script, paths.framework] + arguments, timeout: 5)
        }
    }

    /// Ejecuta `perl` con los argumentos y devuelve el código de salida (-1 si falla o tarda demasiado).
    @discardableResult
    private static func run(_ arguments: [String], timeout: TimeInterval) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do {
            try process.run()
        } catch {
            return -1
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return -1
        }
        return process.terminationStatus
    }
}
