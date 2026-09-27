import Foundation

/// Socket Unix entre Lagoon y el ayudante que llaman los hooks de Claude Code.
///
/// Protocolo: el ayudante escribe un mensaje JSON en una sola línea. Solo para
/// `PermissionRequest` espera una línea de respuesta; en los demás casos cierra enseguida.
enum ClaudeSocket {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Lagoon", isDirectory: true)
    }

    static var path: String { directory.appendingPathComponent("claude.sock").path }

    /// Rellena una `sockaddr_un` con la ruta (máx. 103 bytes).
    static func address(for path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }

    /// Escribe todo el buffer (el socket puede aceptar menos de una vez).
    @discardableResult
    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard var pointer = raw.baseAddress else { return true }
            var remaining = raw.count
            while remaining > 0 {
                let written = Darwin.write(fd, pointer, remaining)
                if written < 0 {
                    if errno == EINTR || errno == EAGAIN { continue }
                    return false
                }
                remaining -= written
                pointer = pointer.advanced(by: written)
            }
            return true
        }
    }

    static func disableSigpipe(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }
}

/// Servidor del socket (vive en la app). Cada cliente es un descriptor con su propia fuente de lectura.
final class ClaudeSocketServer {
    final class Client {
        let fd: Int32
        let source: DispatchSourceRead
        var buffer = Data()
        var closed = false

        init(fd: Int32, source: DispatchSourceRead) {
            self.fd = fd
            self.source = source
        }
    }

    /// Mensaje recibido (en el hilo principal). El cliente sigue abierto hasta `reply` o `close`.
    var onMessage: (_ object: [String: Any], _ client: Client) -> Void = { _, _ in }
    /// El cliente cerró la conexión (por ejemplo, Claude Code canceló el hook).
    var onDisconnect: (_ client: Client) -> Void = { _ in }

    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [Int32: Client] = [:]
    private let queue = DispatchQueue(label: "app.lagoon.claude.socket", qos: .userInitiated)

    func start() -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: ClaudeSocket.directory, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        let path = ClaudeSocket.path
        guard var address = ClaudeSocket.address(for: path) else { return false }
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            Darwin.close(fd)
            return false
        }
        chmod(path, 0o600)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        listenFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptClients() }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        acceptSource = source
        return true
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        queue.sync {
            for client in clients.values { closeLocked(client) }
            clients.removeAll()
        }
        unlink(ClaudeSocket.path)
    }

    /// Responde con una línea y cierra.
    func reply(_ client: Client, _ object: [String: Any]) {
        queue.async { [weak self] in
            guard let self, !client.closed else { return }
            if var data = try? JSONSerialization.data(withJSONObject: object) {
                data.append(0x0A)
                ClaudeSocket.writeAll(client.fd, data)
            }
            self.closeLocked(client)
        }
    }

    func close(_ client: Client) {
        queue.async { [weak self] in self?.closeLocked(client) }
    }

    // MARK: - Cola del socket

    private func acceptClients() {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            ClaudeSocket.disableSigpipe(fd)
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            let client = Client(fd: fd, source: source)
            source.setEventHandler { [weak self] in self?.read(client) }
            source.setCancelHandler { Darwin.close(fd) }
            clients[fd] = client
            source.resume()
        }
    }

    private func read(_ client: Client) {
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        let count = Darwin.read(client.fd, &chunk, chunk.count)
        if count > 0 {
            client.buffer.append(contentsOf: chunk[0..<count])
            // Un mensaje por conexión: se procesa la primera línea completa.
            if let newline = client.buffer.firstIndex(of: 0x0A) {
                let line = client.buffer[client.buffer.startIndex..<newline]
                client.buffer.removeSubrange(client.buffer.startIndex...newline)
                if let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] {
                    DispatchQueue.main.async { [weak self] in self?.onMessage(object, client) }
                }
            }
            // Protección: mensajes absurdamente grandes.
            if client.buffer.count > 8 * 1024 * 1024 { closeLocked(client) }
        } else if count == 0 || (errno != EAGAIN && errno != EINTR) {
            let wasOpen = !client.closed
            closeLocked(client)
            if wasOpen {
                DispatchQueue.main.async { [weak self] in self?.onDisconnect(client) }
            }
        }
    }

    private func closeLocked(_ client: Client) {
        guard !client.closed else { return }
        client.closed = true
        client.source.cancel()
        clients.removeValue(forKey: client.fd)
    }
}
