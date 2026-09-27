import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 2m · Arrastrando un archivo: dos zonas para soltar. La zona bajo el cursor se ilumina.
struct DropZonesView: View {
    @Environment(AppState.self) var app

    var body: some View {
        let model = app.notch
        HStack(spacing: 12) {
            DropZone(icon: .inventory2, title: "Guardar en la bandeja", targeted: model.trayDropTargeted)
                .onDrop(of: [UTType.fileURL], isTargeted: Binding(
                    get: { model.trayDropTargeted },
                    set: { value in withAnimation(.easeOut(duration: 0.15)) { model.trayDropTargeted = value } }
                )) { providers in
                    app.tray.add(providers: providers) { added in
                        model.fileDragEnded()
                        if added > 0 { model.post(.traySaved) }
                    }
                    return true
                }
            DropZone(icon: .wifiTethering, title: "AirDrop", targeted: model.airDropTargeted)
                .onDrop(of: [UTType.fileURL], isTargeted: Binding(
                    get: { model.airDropTargeted },
                    set: { value in withAnimation(.easeOut(duration: 0.15)) { model.airDropTargeted = value } }
                )) { providers in
                    FileDrop.loadURLs(from: providers) { urls in
                        model.fileDragEnded()
                        AirDrop.share(urls)
                    }
                    return true
                }
        }
        .padding(.top, model.geometry.notchHeight + 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }
}

struct DropZone: View {
    let icon: MS
    let title: String
    let targeted: Bool

    var body: some View {
        let color = targeted ? Palette.cyan : Palette.secondary
        VStack(spacing: 6) {
            Icon(icon, size: 26)
            Text(title).lagoonFont(12, .semibold)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .background(RoundedRectangle(cornerRadius: 18).fill(targeted ? Palette.cyan.opacity(0.14) : .clear))
        .overlay(DashedBorder(radius: 18, color: targeted ? Palette.cyan : .white(0.25)))
        .scaleEffect(targeted && !Motion.reduced ? 1.02 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

/// Lectura de URLs de archivos desde un drop.
enum FileDrop {
    static func loadURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }
}

/// Compartir por AirDrop.
enum AirDrop {
    static func share(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        if service.canPerform(withItems: urls) {
            service.perform(withItems: urls)
        }
    }
}
