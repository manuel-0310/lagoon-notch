import SwiftUI

/// La forma negra y su contenido. Todo se dibuja en una única pieza que se estira desde el notch.
struct NotchRootView: View {
    @Environment(AppState.self) var app

    var body: some View {
        let model = app.notch
        let activity = currentActivity(model)

        ZStack(alignment: .top) {
            if let glow = activity?.glow {
                NotchShape(radius: model.cornerRadius)
                    .fill(Color.black)
                    .frame(width: model.shapeWidth, height: model.shapeHeight)
                    .shadow(color: glow.color, radius: glow.radius)
                    .transition(.opacity)
            }

            NotchShape(radius: model.cornerRadius)
                .fill(Color.black)
                .frame(width: model.shapeWidth, height: model.shapeHeight)
                .shadow(color: .black.opacity(shadowOpacity(model.shadow)),
                        radius: shadowRadius(model.shadow),
                        y: shadowY(model.shadow))

            contentLayer(model)
                .frame(width: model.shapeWidth, height: model.shapeHeight, alignment: .top)
                .clipShape(NotchShape(radius: model.cornerRadius))

            if let ring = activity?.ring {
                NotchOutline(radius: model.cornerRadius)
                    .stroke(ring, lineWidth: 1)
                    .frame(width: model.shapeWidth, height: model.shapeHeight)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .contentShape(NotchShape(radius: model.cornerRadius))
        .onTapGesture { model.handleTap() }
        .contextMenu { NotchContextMenu() }
        .modifier(ShakeEffect(animatableData: model.shakePhase))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.panelRevealed, model.panelRevealed)
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .ignoresSafeArea()
    }

    private func currentActivity(_ model: NotchViewModel) -> LiveActivity? {
        if case let .activity(activity)? = model.displayed { return activity }
        return nil
    }

    @ViewBuilder
    private func contentLayer(_ model: NotchViewModel) -> some View {
        ZStack(alignment: .top) {
            if let displayed = model.displayed {
                let spec = model.spec(for: displayed)
                PresentationContent(presentation: displayed)
                    .frame(width: spec.width, height: spec.height, alignment: .top)
                    .id(displayed.key)
                    .transition(displayed == .expanded ? .opacity : .activityContent)
            }
        }
    }

    private func shadowOpacity(_ kind: ShapeSpec.ShadowKind) -> Double {
        switch kind {
        case .none: return 0
        case .hover: return 0.25
        case .block: return 0.28
        case .expanded: return 0.35
        }
    }

    private func shadowRadius(_ kind: ShapeSpec.ShadowKind) -> CGFloat {
        switch kind {
        case .none: return 0
        case .hover: return 7
        case .block: return 17
        case .expanded: return 25
        }
    }

    private func shadowY(_ kind: ShapeSpec.ShadowKind) -> CGFloat {
        switch kind {
        case .none: return 0
        case .hover: return 4
        case .block: return 14
        case .expanded: return 22
        }
    }
}

/// Elige la vista de contenido para cada presentación.
struct PresentationContent: View {
    let presentation: Presentation

    var body: some View {
        switch presentation {
        case .idle:
            Color.clear
        case let .wings(content):
            WingsView(content: content)
        case let .activity(activity):
            switch activity.style {
            case .wing: WingActivityView(activity: activity)
            case .block: BlockActivityView(activity: activity)
            }
        case .expanded:
            PanelView()
        case .drop:
            DropZonesView()
        }
    }
}

/// Clic derecho sobre el notch.
struct NotchContextMenu: View {
    @Environment(AppState.self) var app

    var body: some View {
        Button("Ajustes de Lagoon…") { app.openSettings() }
        Divider()
        Button("Salir de Lagoon") { NSApp.terminate(nil) }
    }
}
