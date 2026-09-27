import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Pestaña Atajos: atajos de la app Atajos y apps favoritas, a un clic.
struct ShortcutsView: View {
    @Environment(AppState.self) var app
    @State private var targeted = false

    var body: some View {
        let shortcuts = app.shortcuts
        Group {
            if shortcuts.isEmpty {
                EmptyStateContent(icon: .apps, title: "Tus atajos y apps",
                                  message: "Añade atajos de la app Atajos o arrastra apps aquí para abrirlos desde el notch.") {
                    HStack(spacing: 8) {
                        AddShortcutMenu()
                        PillButton(title: "Añadir app", icon: .add) { shortcuts.chooseApps() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay { if targeted { DashedBorder(radius: 18, color: Palette.cyan) } }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Atajos").lagoonFont(14, .semibold)
                        Spacer(minLength: 0)
                        HStack(spacing: 6) {
                            AddShortcutMenu()
                            PillButton(title: "App", icon: .add) { shortcuts.chooseApps() }
                        }
                    }
                    .stagger(1)

                    LagoonScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76, maximum: 92), spacing: 10)],
                                  alignment: .leading, spacing: 10) {
                            ForEach(shortcuts.favorites, id: \.self) { name in
                                ShortcutTile(name: name)
                            }
                            ForEach(shortcuts.apps) { favorite in
                                AppTile(favorite: favorite)
                            }
                        }
                    }
                    .stagger(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay { if targeted { DashedBorder(radius: 18, color: Palette.cyan).padding(-6) } }
            }
        }
        .onAppear { shortcuts.refreshAvailableIfNeeded() }
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            FileDrop.loadURLs(from: providers) { urls in
                DispatchQueue.main.async { shortcuts.addApps(urls) }
            }
            return true
        }
    }
}

/// "+ Atajo": menú con los atajos disponibles que aún no están en la pestaña.
struct AddShortcutMenu: View {
    @Environment(AppState.self) var app

    var body: some View {
        let shortcuts = app.shortcuts
        let remaining = shortcuts.available.filter { !shortcuts.favorites.contains($0) }
        Menu {
            if shortcuts.isLoadingList {
                Text("Cargando atajos…")
            } else if remaining.isEmpty {
                Text(shortcuts.available.isEmpty ? "No hay atajos" : "Ya están todos")
            } else {
                ForEach(remaining, id: \.self) { name in
                    Button(name) { shortcuts.addShortcut(name) }
                }
            }
            Divider()
            Button("Abrir la app Atajos…") { shortcuts.openShortcutsApp() }
        } label: {
            HStack(spacing: 5) {
                Icon(.add, size: 15)
                Text("Atajo")
            }
            .lagoonFont(12, .semibold)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(Color.white(0.14)))
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct ShortcutTile: View {
    @Environment(AppState.self) var app
    let name: String

    var body: some View {
        let shortcuts = app.shortcuts
        let isRunning = shortcuts.running.contains(name)
        Button { shortcuts.run(name) } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(LinearGradient(colors: [Color(hex: 0x5E5CE6), Color(hex: 0xBF5AF2)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    if isRunning {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Icon(.layers, size: 20, color: .white)
                    }
                }
                .frame(width: 40, height: 40)
                Text(name)
                    .lagoonFont(11)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.card))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button("Ejecutar") { shortcuts.run(name) }
            Button("Quitar de Lagoon") { withAnimation(Motion.activityOut) { shortcuts.removeShortcut(name) } }
        }
        .help("Ejecutar “\(name)”")
    }
}

struct AppTile: View {
    @Environment(AppState.self) var app
    let favorite: FavoriteApp

    var body: some View {
        let shortcuts = app.shortcuts
        Button { shortcuts.launch(favorite) } label: {
            VStack(spacing: 6) {
                Image(nsImage: shortcuts.icon(for: favorite))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 40, height: 40)
                Text(favorite.name)
                    .lagoonFont(11)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.card))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button("Abrir") { shortcuts.launch(favorite) }
            Button("Quitar de Lagoon") { withAnimation(Motion.activityOut) { shortcuts.removeApp(favorite) } }
        }
    }
}
