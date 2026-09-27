import SwiftUI

/// 4f · Portapapeles: clic para pegar, fijar con ⌘P.
struct ClipboardView: View {
    @Environment(AppState.self) var app

    var body: some View {
        let clipboard = app.clipboard
        if clipboard.items.isEmpty {
            ClipboardEmptyView()
        } else {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ClipboardSearchField()
                    Text(clipboard.countDescription)
                        .lagoonFont(11)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize()
                }
                .stagger(1)

                ScrollViewReader { proxy in
                    LagoonScrollView {
                        VStack(spacing: 0) {
                            ForEach(clipboard.filtered) { item in
                                ClipboardRow(item: item, selected: clipboard.selectedID == item.id)
                                    .id(item.id)
                            }
                        }
                    }
                    .onChange(of: clipboard.selectedID) { _, id in
                        if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
                    }
                }
                .stagger(2)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .onAppear { clipboard.resetSelection() }
        }
    }
}

struct ClipboardSearchField: View {
    @Environment(AppState.self) var app

    var body: some View {
        @Bindable var clipboard = app.clipboard
        HStack(spacing: 6) {
            Icon(.search, size: 15, color: .white(0.4))
            if AppEnvironment.isSnapshot {
                Text("Buscar en el historial")
                    .lagoonFont(12)
                    .foregroundStyle(Color.white(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: $clipboard.query, prompt: Text("Buscar en el historial").foregroundStyle(Color.white(0.4)))
                    .textFieldStyle(.plain)
                    .lagoonFont(12)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white(0.08)))
    }
}

struct ClipboardRow: View {
    @Environment(AppState.self) var app
    let item: ClipItem
    let selected: Bool

    var body: some View {
        let clipboard = app.clipboard
        HStack(spacing: 10) {
            leading
            Text(item.title)
                .lagoonFont(12.5)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if item.pinned {
                Icon(.pushPin, size: 14, color: Palette.cyan)
            }
            Text(selected ? "Pegar ⏎" : Formatters.relative(item.date))
                .lagoonFont(11)
                .foregroundStyle(Palette.secondary)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(height: 31)
        .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Color.white(0.1) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering in if hovering { clipboard.selectedID = item.id } }
        .onTapGesture { clipboard.paste(item) }
        .contextMenu {
            Button("Pegar") { clipboard.paste(item) }
            Button("Copiar") { clipboard.copy(item) }
            Button(item.pinned ? "Desfijar" : "Fijar") { clipboard.togglePin(item) }
            Divider()
            Button("Eliminar") { withAnimation { clipboard.delete(item) } }
            Button("Borrar historial") { withAnimation { clipboard.clear() } }
        }
    }

    @ViewBuilder
    private var leading: some View {
        if item.kind == .color, let color = item.swatch {
            RoundedRectangle(cornerRadius: 6).fill(color).frame(width: 22, height: 22)
        } else if item.kind == .image, let thumbnail = app.clipboard.thumbnail(for: item) {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Icon(item.kind.icon, size: 14, color: .white(0.8))
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white(0.1)))
        }
    }
}

/// 5d · Portapapeles vacío.
struct ClipboardEmptyView: View {
    var body: some View {
        EmptyStateContent(icon: .contentPaste,
                          title: "El historial está vacío",
                          message: "Copia algo con ⌘C y aparecerá aquí para pegarlo de nuevo con un clic.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .stagger(1)
    }
}
