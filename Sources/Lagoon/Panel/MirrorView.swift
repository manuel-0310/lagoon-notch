import AVFoundation
import SwiftUI

/// 4g · Espejo. La cámara se apaga al cerrar el panel.
struct MirrorView: View {
    @Environment(AppState.self) var app

    var body: some View {
        let camera = app.camera
        Group {
            switch camera.authorization {
            case .authorized:
                MirrorLiveView()
            case .notDetermined:
                MirrorPermissionView(requesting: true)
            case .denied:
                MirrorPermissionView(requesting: false)
            }
        }
        .onAppear { camera.panelDidAppear() }
        .onDisappear { camera.stop() }
    }
}

struct MirrorLiveView: View {
    @Environment(AppState.self) var app
    @AppStorage(Prefs.mirrorFlip) private var flip = false
    @AppStorage(Prefs.mirrorZoom) private var zoom = 1

    var body: some View {
        let camera = app.camera
        HStack(spacing: 18) {
            ZStack {
                if AppEnvironment.isSnapshot {
                    StripedFill(a: Color(hex: 0x1C1C1F), b: Color(hex: 0x232327), stripe: 6)
                    Text("vista de cámara")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white(0.45))
                } else {
                    Color(hex: 0x1C1C1F)
                    CameraPreview(session: camera.session, mirrored: !flip, zoom: zoom)
                }
            }
            .frame(width: 300, height: 168)
            .clipShape(RoundedRectangle(cornerRadius: 17))
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.white(0.12)))
            .stagger(1)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Voltear imagen")
                    Spacer()
                    LagoonToggle(isOn: $flip)
                }
                HStack {
                    Text("Zoom")
                    Spacer()
                    SegmentedPill(options: [(1, "1×"), (2, "2×")], selection: $zoom)
                }
                Text("La cámara se apaga al cerrar el panel.")
                    .lagoonFont(11)
                    .foregroundStyle(Palette.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .lagoonFont(12.5)
            .frame(maxWidth: .infinity)
            .stagger(2)
        }
    }
}

/// 5e · Espejo sin permiso de cámara.
struct MirrorPermissionView: View {
    @Environment(AppState.self) var app
    let requesting: Bool

    var body: some View {
        EmptyStateContent(icon: .videocamOff,
                          title: "Lagoon necesita acceso a la cámara",
                          message: "Solo se usa mientras este panel está abierto.") {
            PillButton(title: "Permitir acceso", style: .filled(Palette.cyan, text: .black)) {
                app.camera.requestAccess()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: 0x141416)))
        .stagger(1)
    }
}

/// Vista previa de la cámara con AVCaptureVideoPreviewLayer.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    var mirrored: Bool
    var zoom: Int

    func makeNSView(context: Context) -> PreviewNSView {
        PreviewNSView(session: session)
    }

    func updateNSView(_ view: PreviewNSView, context: Context) {
        view.update(mirrored: mirrored, zoom: CGFloat(zoom))
    }

    final class PreviewNSView: NSView {
        private let previewLayer: AVCaptureVideoPreviewLayer

        init(session: AVCaptureSession) {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            wantsLayer = true
            layer?.masksToBounds = true
            previewLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(previewLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let transform = previewLayer.affineTransform()
            previewLayer.setAffineTransform(.identity)
            previewLayer.frame = bounds
            previewLayer.setAffineTransform(transform)
            CATransaction.commit()
        }

        func update(mirrored: Bool, zoom: CGFloat) {
            if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrored
            }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            previewLayer.setAffineTransform(CGAffineTransform(scaleX: zoom, y: zoom))
            CATransaction.commit()
        }
    }
}
