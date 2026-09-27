import SwiftUI

/// 4c · Agenda: calendario y recordatorios.
struct AgendaView: View {
    @Environment(AppState.self) var app

    var body: some View {
        let calendar = app.calendar
        Group {
            if calendar.eventsAccess != .granted && calendar.remindersAccess != .granted {
                AgendaPermissionView()
            } else if calendar.todayEvents.isEmpty && calendar.reminders.isEmpty {
                AgendaEmptyView()
            } else {
                HStack(alignment: .top, spacing: 18) {
                    EventsColumn()
                        .frame(width: 268)
                        .stagger(1)
                    RemindersColumn()
                        .frame(maxWidth: .infinity)
                        .stagger(2)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .onAppear { calendar.requestAccessIfNeeded() }
    }
}

struct EventsColumn: View {
    @Environment(AppState.self) var app

    var body: some View {
        let calendar = app.calendar
        VStack(alignment: .leading, spacing: 9) {
            if let featured = calendar.featuredEvent {
                FeaturedEventCard(event: featured)
            } else {
                VStack(spacing: 4) {
                    Icon(.eventAvailable, size: 24, color: .white(0.35))
                    Text("Sin eventos hoy").lagoonFont(13, .semibold)
                    Text("Tu calendario está libre.").lagoonFont(11).foregroundStyle(Palette.secondary)
                }
                .frame(maxWidth: .infinity)
                .card()
            }
            ForEach(calendar.laterEvents.prefix(3)) { event in
                HStack(spacing: 10) {
                    Circle().fill(event.color).frame(width: 6, height: 6)
                    Text(event.isAllDay ? "Todo el día" : Formatters.time(event.start))
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondary)
                        .frame(width: event.isAllDay ? nil : 36, alignment: .leading)
                        .fixedSize()
                    Text(event.title).lineLimit(1)
                }
                .lagoonFont(12)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .onTapGesture { calendar.open(event) }
            }
        }
    }
}

struct FeaturedEventCard: View {
    @Environment(AppState.self) var app
    let event: CalendarEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                HStack(spacing: 9) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.blue)
                        .frame(width: 4, height: 36)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(event.title)
                            .lagoonFont(13, .semibold)
                            .lineLimit(1)
                        Text(event.subtitle)
                            .lagoonFont(11)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 6)
                TimelineView(.everyMinute) { context in
                    Text(event.relativeDescription(now: AppEnvironment.fixedNow ?? context.date))
                        .lagoonFont(11, .semibold)
                        .foregroundStyle(Palette.blue)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            if let service = event.meetingShortName {
                Button { app.calendar.join(event) } label: {
                    HStack(spacing: 6) {
                        Icon(.videocam, size: 16)
                        Text("Unirse a \(service)").lagoonFont(12, .semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Palette.blueButton))
                    .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 10)
            }
        }
        .card()
        .contentShape(Rectangle())
        .onTapGesture { app.calendar.open(event) }
    }
}

struct RemindersColumn: View {
    @Environment(AppState.self) var app

    var body: some View {
        let calendar = app.calendar
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("RECORDATORIOS").sectionLabel()
                Spacer()
                Text(calendar.pendingDescription)
                    .lagoonFont(11)
                    .foregroundStyle(Palette.secondary)
            }
            .padding(.bottom, 2)
            if calendar.remindersAccess != .granted {
                Text("Permite el acceso a Recordatorios en Ajustes del Sistema.")
                    .lagoonFont(12)
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 8)
            } else if calendar.reminders.isEmpty {
                VStack(spacing: 6) {
                    Icon(.checkCircle, size: 24, color: .white(0.35))
                    Text("Todo hecho").lagoonFont(13, .semibold)
                    NewReminderField()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
            } else {
                LagoonScrollView {
                    VStack(spacing: 0) {
                        ForEach(calendar.reminders) { reminder in
                            ReminderRow(reminder: reminder)
                        }
                    }
                }
            }
        }
    }
}

struct ReminderRow: View {
    @Environment(AppState.self) var app
    let reminder: ReminderItem

    var body: some View {
        HStack(spacing: 9) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { app.calendar.toggle(reminder) }
            } label: {
                Icon(reminder.isCompleted ? .checkCircle : .radioButtonUnchecked, size: 19,
                     color: reminder.isCompleted ? Palette.cyan : .white(0.4))
                    .contentTransition(.opacity)
            }
            .buttonStyle(PressableStyle())
            Text(reminder.title)
                .lagoonFont(12.5)
                .strikethrough(reminder.isCompleted, color: .white(0.4))
                .foregroundStyle(reminder.isCompleted ? Color.white(0.4) : .white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let time = reminder.timeLabel {
                Text(time)
                    .lagoonFont(11)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.divider).frame(height: 1)
        }
    }
}

/// Campo para crear un recordatorio rápido.
struct NewReminderField: View {
    @Environment(AppState.self) var app
    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        if editing {
            TextField("Nuevo recordatorio", text: $text)
                .textFieldStyle(.plain)
                .lagoonFont(12)
                .focused($focused)
                .padding(.horizontal, 12)
                .frame(width: 200, height: 28)
                .background(Capsule().fill(Color.white(0.1)))
                .onSubmit {
                    app.calendar.addReminder(title: text)
                    text = ""
                    editing = false
                }
                .onExitCommand { editing = false }
                .onAppear { focused = true }
        } else {
            PillButton(title: "Nuevo recordatorio", icon: .add) {
                editing = true
            }
        }
    }
}

/// 5c · Agenda sin eventos ni tareas.
struct AgendaEmptyView: View {
    var body: some View {
        HStack(spacing: 18) {
            EmptyStateContent(icon: .eventAvailable, title: "Sin eventos hoy", message: "Tu calendario está libre.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.white(0.05)))
                .stagger(1)
            EmptyStateContent(icon: .checkCircle, title: "Todo hecho", message: "No quedan recordatorios para hoy.") {
                NewReminderField()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white(0.05)))
            .stagger(2)
        }
    }
}

/// Sin permiso de Calendario/Recordatorios.
struct AgendaPermissionView: View {
    @Environment(AppState.self) var app

    var body: some View {
        EmptyStateContent(icon: .calendarMonth,
                          title: "Conecta tu calendario",
                          message: "Lagoon muestra tus eventos de hoy, te avisa antes de cada reunión y te deja marcar recordatorios.") {
            PillButton(title: app.calendar.eventsAccess == .denied ? "Abrir Ajustes" : "Permitir acceso",
                       style: .filled(Palette.cyan, text: .black)) {
                app.calendar.requestAccess(openSettingsIfDenied: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: 0x141416)))
        .stagger(1)
    }
}
