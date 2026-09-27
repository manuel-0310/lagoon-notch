import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 4b · Bandeja de archivos + AirDrop.
struct TrayView: View {
    @Environment(AppState.self) var app
    @State private var targeted = false

    var body: some View {
        Group {
            if app.tray.items.isEmpty {
                TrayEmptyView(targeted: targeted)
            } else {
                TrayFilesView(targeted: targeted)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            app.tray.add(providers: providers) { _ in }
            return true
        }
    }
}

struct TrayFilesView: View {
    @Environment(AppState.self) var app
    let targeted: Bool

    var body: some View {
        let tray = app.tray
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Bandeja").lagoonFont(14, .semibold)
                    TimelineView(.everyMinute) { context in
                        Text(tray.headerDescription(now: AppEnvironment.fixedNow ?? context.date))
                            .lagoonFont(11)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    PillButton(title: "AirDrop", icon: .wifiTethering) { AirDrop.share(tray.items.map(\.url)) }
                        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                            FileDrop.loadURLs(from: providers) { AirDrop.share($0) }
                            return true
                        }
                    PillButton(title: "Vaciar") {
                        withAnimation(Motion.activityOut) { tray.clear() }
                    }
                }
            }
            .stagger(1)

            LagoonScrollView(axis: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(tray.items) { item in
                        TrayTile(item: item)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                    DropHereTile(targeted: targeted)
                }
            }
            .stagger(2)

            Text("Arrastra un archivo fuera del notch para soltarlo en Finder, Mail o WhatsApp.")
                .lagoonFont(11)
                .foregroundStyle(Color.white(0.4))
                .lineLimit(1)
                .stagger(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct TrayTile: View {
    @Environment(AppState.self) var app
    let item: TrayItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                if let thumbnail = app.tray.thumbnails[item.id] {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    StripedFill(a: Color(hex: 0x1C2A2D), b: Color(hex: 0x233437), stripe: 6)
                    Text(item.typeLabel)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white(0.45))
                }
            }
            .frame(width: 100, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(item.name)
                .lagoonFont(11, .medium)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(Formatters.fileSize(item.size))
                .lagoonFont(10)
                .foregroundStyle(Palette.secondary)
                .padding(.top, -3)
        }
        .frame(width: 100)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .contextMenu {
            Button("Abrir") { NSWorkspace.shared.open(item.url) }
            Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Compartir por AirDrop") { AirDrop.share([item.url]) }
            Divider()
            Button("Quitar de la bandeja") { withAnimation(Motion.activityOut) { app.tray.remove(item) } }
        }
        .onAppear { app.tray.loadThumbnail(for: item) }
    }
}

struct DropHereTile: View {
    let targeted: Bool

    var body: some View {
        VStack(spacing: 2) {
            Icon(.add, size: 20)
            Text("Suelta aquí").lagoonFont(10)
        }
        .foregroundStyle(targeted ? Palette.cyan : Palette.secondary)
        .frame(width: 100, height: 72)
        .background(RoundedRectangle(cornerRadius: 12).fill(targeted ? Palette.cyan.opacity(0.14) : .clear))
        .overlay(DashedBorder(radius: 12, color: targeted ? Palette.cyan : .white(0.25)))
        .animation(.easeOut(duration: 0.15), value: targeted)
    }
}

/// 5b · Bandeja vacía.
struct TrayEmptyView: View {
    let targeted: Bool

    var body: some View {
        EmptyStateContent(icon: .inventory2,
                          title: "Arrastra archivos al notch",
                          message: "Se guardan aquí durante 1 hora. Suéltalos sobre AirDrop para compartirlos.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 18).fill(targeted ? Palette.cyan.opacity(0.1) : .clear))
            .overlay(DashedBorder(radius: 18, color: targeted ? Palette.cyan : .white(0.18)))
            .animation(.easeOut(duration: 0.15), value: targeted)
            .stagger(1)
    }
}
