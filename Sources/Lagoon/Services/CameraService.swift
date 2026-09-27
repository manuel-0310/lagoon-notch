import AppKit
import AVFoundation
import Observation

/// Cámara para el espejo. Solo se enciende mientras la pestaña está visible.
@Observable
final class CameraService {
    enum Authorization: Equatable { case authorized, notDetermined, denied }

    var authorization: Authorization = .notDetermined

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let queue = DispatchQueue(label: "app.lagoon.camera", qos: .userInitiated)
    @ObservationIgnored private var configured = false

    init() {
        refreshAuthorization()
    }

    func refreshAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: authorization = .authorized
        case .notDetermined: authorization = .notDetermined
        default: authorization = .denied
        }
    }

    func panelDidAppear() {
        guard !AppEnvironment.isSnapshot else { return }
        refreshAuthorization()
        switch authorization {
        case .authorized: start()
        case .notDetermined: requestAccess()
        case .denied: break
        }
    }

    func requestAccess() {
        if authorization == .denied {
            SystemLinks.open(.camera)
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                self.authorization = granted ? .authorized : .denied
                if granted { self.start() }
            }
        }
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            if !self.configured { self.configure() }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
                                                         mediaType: .video, position: .unspecified)
        if let device = discovery.devices.first ?? AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        session.commitConfiguration()
        configured = true
    }
}
