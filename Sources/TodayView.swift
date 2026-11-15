import SwiftUI

@main
struct MedRep486App: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            TodayView().tabItem { Label("Today", systemImage: "checklist") }
            EventsView().tabItem { Label("Events", systemImage: "calendar") }
            DoctorsView().tabItem { Label("Doctors", systemImage: "stethoscope") }
            HospitalsView().tabItem { Label("Hospitals", systemImage: "building.2") }
            MoreView().tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .tint(.green)
    }
}

struct TodayView: View {
    @EnvironmentObject var store: Store
    @State private var compose: ComposeItem?

    var body: some View {
        NavigationStack {
            List {
                let suggestions = store.suggestions()
                if !suggestions.isEmpty {
                    Section("Suggestions") {
                        ForEach(suggestions) { s in
                            Label(s.text, systemImage: s.icon).font(.subheadline)
                        }
                    }
                }

                let due = store.dueMessages()
                Section("Message today (\(due.count))") {
                    if due.isEmpty {
                        Text("All caught up.").foregroundStyle(.secondary)
                    }
                    ForEach(due) { item in
                        DueRow(item: item, compose: $compose)
                    }
                }

                let occasions = store.data.occasions.filter { o in
                    Calendar.current.isDateInToday(o.date) && o.greetedIDs.count < store.data.doctors.count
                }
                if !occasions.isEmpty {
                    Section("Greetings today") {
                        ForEach(occasions) { o in
                            NavigationLink {
                                GreetingsView(occasionID: o.id)
                            } label: {
                                Label("\(o.name): send greetings (\(o.greetedIDs.count)/\(store.data.doctors.count) sent)",
                                      systemImage: "gift")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Today")
            .sheet(item: $compose) { ComposeSheet(item: $0) }
        }
    }
}

struct DueRow: View {
    @EnvironmentObject var store: Store
    let item: DueMessage
    @Binding var compose: ComposeItem?

    var body: some View {
        if let d = store.doctor(item.invite.doctorID), let e = store.event(item.invite.eventID) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(d.displayName).font(.headline)
                    Spacer()
                    StatusBadge(status: item.invite.status)
                }
                Text("\(item.kind.title) - \(e.name) (\(e.date.shortText))")
                    .font(.subheadline).foregroundStyle(.secondary)
                if !item.invite.note.isEmpty {
                    Text(item.invite.note).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    Button {
                        let inviteID = item.invite.id
                        let kind = item.kind
                        compose = ComposeItem(to: d.displayName, phone: d.phone,
                                              text: store.messageText(kind, invite: item.invite),
                                              onSent: { store.markSent(inviteID, kind) })
                    } label: {
                        Label("Write", systemImage: "message.fill")
                    }
                    let reps = store.reps(forDoctor: d)
                    if !reps.isEmpty {
                        Menu {
                            ForEach(reps) { r in
                                Button("Ask \(r.name)") {
                                    let inviteID = item.invite.id
                                    compose = ComposeItem(to: r.name, phone: r.phone,
                                                          text: store.repHelpText(rep: r, invite: item.invite),
                                                          onSent: {
                                                              if var inv = store.invite(inviteID) {
                                                                  inv.askedRepID = r.id
                                                                  store.upsert(inv)
                                                              }
                                                          })
                                }
                            }
                        } label: {
                            Label("Ask rep", systemImage: "person.2.fill")
                        }
                    }
                    Spacer()
                    Button("Skip") { store.skip(item.invite.id, item.kind) }
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
            }
            .padding(.vertical, 4)
        }
    }
}

struct GreetingsView: View {
    @EnvironmentObject var store: Store
    let occasionID: UUID
    @State private var compose: ComposeItem?

    var body: some View {
        List {
            if let o = store.data.occasions.first(where: { $0.id == occasionID }) {
                Section {
                    Text(o.message).font(.footnote).foregroundStyle(.secondary)
                }
                Section("Doctors (\(o.greetedIDs.count)/\(store.data.doctors.count) sent)") {
                    ForEach(store.sortedDoctors) { d in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(d.displayName)
                                Text(store.hospital(d.hospitalID)?.name ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if o.greetedIDs.contains(d.id) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else {
                                Button("Send") {
                                    let docID = d.id
                                    compose = ComposeItem(to: d.displayName, phone: d.phone,
                                                          text: store.occasionText(o, doctor: d),
                                                          onSent: {
                                                              if var occ = store.data.occasions.first(where: { $0.id == occasionID }) {
                                                                  occ.greetedIDs.append(docID)
                                                                  store.upsert(occ)
                                                              }
                                                          })
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Greetings")
        .sheet(item: $compose) { ComposeSheet(item: $0) }
    }
}
