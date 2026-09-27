import SwiftUI

/// Panel expandido (580 × 232): pestañas en las alas junto a la cámara y contenido a toda altura.
struct PanelView: View {
    @Environment(AppState.self) var app
    @Namespace private var tabNamespace
    /// Solo para redibujar las pestañas al ocultar o mostrar alguna en Ajustes.
    @AppStorage(Prefs.hiddenTabs) private var hiddenTabs = ""

    var body: some View {
        let model = app.notch
        VStack(spacing: 0) {
            tabBar(model)
                .frame(height: model.geometry.notchHeight)
            ZStack {
                content(model)
                    .id(contentKey(model))
                    .transition(.tabSlide(model.tabDirection))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(EdgeInsets(top: 8, leading: 22, bottom: 18, trailing: 22))
        }
        .frame(width: NotchGeometry.expandedWidth,
               height: model.geometry.notchHeight + NotchGeometry.expandedContentHeight)
        .background(alignment: .topLeading) {
            if model.tab == .music, app.music.track != nil {
                // El resplandor sale de la portada.
                EllipticalGradient(colors: [app.music.glow.opacity(0.38), app.music.glow.opacity(0)],
                                   center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                    .frame(width: 420, height: 300)
                    .offset(x: -60, y: -20)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(Motion.songChange, value: app.music.glow)
    }

    private func contentKey(_ model: NotchViewModel) -> String {
        "\(model.tab.rawValue)-\(model.subpage?.rawValue ?? "")"
    }

    // MARK: Pestañas

    private func tabBar(_ model: NotchViewModel) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(PanelTab.left) { tab in tabButton(tab, model: model) }
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                ForEach(PanelTab.right) { tab in tabButton(tab, model: model) }
            }
        }
        .padding(.horizontal, 12)
        .stagger(0)
    }

    private func tabButton(_ tab: PanelTab, model: NotchViewModel) -> some View {
        let selected = model.tab == tab
        return Button {
            model.select(tab)
        } label: {
            Icon(tab.icon, size: 16, color: selected ? .white : .white(0.42))
                .frame(width: 30, height: 22)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 11)
                            .fill(Color.white(0.16))
                            .matchedGeometryEffect(id: "activeTab", in: tabNamespace)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help(tab.title)
    }

    // MARK: Contenido

    @ViewBuilder
    private func content(_ model: NotchViewModel) -> some View {
        switch model.tab {
        case .home:
            switch model.subpage {
            case .clock?: ClockDetailView()
            case .weather?: WeatherDetailView()
            case .battery?: BatteryDetailView()
            case .sound?: SoundDetailView()
            case nil: HomeView()
            }
        case .music: MusicView()
        case .tray: TrayView()
        case .calendar: AgendaView()
        case .timer: TimerPanelView()
        case .clipboard: ClipboardView()
        case .mirror: MirrorView()
        case .shortcuts: ShortcutsView()
        case .system: SystemView()
        case .claude: ClaudeView()
        }
    }
}
