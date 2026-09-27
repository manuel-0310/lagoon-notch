import SwiftUI

/// Estado vacío: explica qué va a aparecer y ofrece una sola acción (sección 5).
struct EmptyStateContent<Actions: View>: View {
    let icon: MS
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    init(icon: MS, title: String, message: String, @ViewBuilder actions: () -> Actions) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 5) {
            Icon(icon, size: 30, color: .white(0.35))
            Text(title)
                .lagoonFont(14, .semibold)
                .lineLimit(1)
                .padding(.top, 4)
            Text(message)
                .lagoonFont(12)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 320)
                .fixedSize(horizontal: false, vertical: true)
            actions
                .padding(.top, 8)
        }
        .padding(.horizontal, 20)
    }
}

extension EmptyStateContent where Actions == EmptyView {
    init(icon: MS, title: String, message: String) {
        self.init(icon: icon, title: title, message: message) { EmptyView() }
    }
}
