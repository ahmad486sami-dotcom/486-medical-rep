import SwiftUI

struct EventsView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                let start = Calendar.current.startOfDay(for: Date())
                let upcoming = store.data.events.filter { $0.date >= start }.sorted { $0.date < $1.date }
                let past = store.data.events.filter { $0.date < start }.sorted { $0.date > $1.date }
                if store.data.events.isEmpty {
                    Text("No events yet. Tap + to add one.").foregroundStyle(.secondary)
                }
                if !upcoming.isEmpty {
                    Section("Upcoming") { ForEach(upcoming) { EventRow(event: $0) } }
                }
                if !past.isEmpty {
                    Section("Past") { ForEach(past) { EventRow(event: $0) } }
                }
            }
            .navigationTitle("Events")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $adding) {
                EventEditView(event: MedEvent(name: "", date: Date().addingTimeInterval(7 * 86400)), isNew: true)
            }
        }
    }
}

struct EventRow: View {
    @EnvironmentObject var store: Store
    let event: MedEvent
    var body: some View {
        let invs = store.invites(forEvent: event.id)
        NavigationLink {
            EventDetailView(eventID: event.id)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.name).font(.headline)
                Text(Store.longDate.string(from: event.date)).font(.subheadline).foregroundStyle(.secondary)
                Text("Coming \(invs.filter { $0.status == .coming }.count)/\(event.target) - Maybe \(invs.filter { $0.status == .maybe }.count) - No \(invs.filter { $0.status == .no }.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct EventEditView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var event: MedEvent
    let isNew: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Name (e.g. New launch dinner)", text: $event.name)
                    DatePicker("Date & time", selection: $event.date)
                    TextField("Venue", text: $event.venue)
                    TextField("CME hours (optional)", text: $event.cmeHours).keyboardType(.decimalPad)
                    TextField("Main points (speaker, topic...)", text: $event.details, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section("Target") {
                    Stepper("Goal: \(event.target) doctors", value: $event.target, in: 1...100)
                }
                Section {
                    Toggle("Open to all specialties", isOn: Binding(
                        get: { event.specialties.isEmpty },
                        set: { all in event.specialties = all ? [] : ["Cardiology"] }
                    ))
                    if !event.specialties.isEmpty {
                        ForEach(Specialty.all, id: \.self) { s in
                            Toggle(s, isOn: Binding(
                                get: { event.specialties.contains(s) },
                                set: { on in
                                    if on { event.specialties.append(s) } else { event.specialties.removeAll { $0 == s } }
                                    if event.specialties.isEmpty { event.specialties = [s] }
                                }
                            ))
                        }
                    }
                } header: {
                    Text("Who can attend")
                } footer: {
                    Text("Only doctors with these specialties show up when you invite.")
                }
            }
            .navigationTitle(isNew ? "New event" : "Edit event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.upsert(event); dismiss() }
                        .disabled(event.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct EventDetailView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let eventID: UUID
    @State private var tab = 0
    @State private var editing = false
    @State private var search = ""
    @State private var confirmDelete = false

    var body: some View {
        if let e = store.event(eventID) {
            content(e)
                .navigationTitle(e.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true } }
                }
                .sheet(isPresented: $editing) { EventEditView(event: e, isNew: false) }
                .confirmationDialog("Delete this event and its invites?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        dismiss()
                        store.deleteEvent(e.id)
                    }
                }
        } else {
            Text("Event deleted").foregroundStyle(.secondary)
        }
    }

    private func content(_ e: MedEvent) -> some View {
        let invs = store.invites(forEvent: e.id)
        return List {
            header(e, invs)
            Picker("", selection: $tab) {
                Text("Invited").tag(0)
                Text("Invite").tag(1)
                Text("Event day").tag(2)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            if tab == 0 {
                invitedSections(invs)
            } else if tab == 1 {
                inviteSections(e, invs)
            } else {
                eventDaySection(invs)
            }
            shareSection(e, invs)
            Section {
                Button("Delete event", role: .destructive) { confirmDelete = true }
            }
        }
    }

    @ViewBuilder
    private func header(_ e: MedEvent, _ invs: [Invite]) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(Store.longDate.string(from: e.date)).font(.subheadline)
                if !e.venue.isEmpty { Text(e.venue).font(.subheadline).foregroundStyle(.secondary) }
                if !e.cmeHours.isEmpty { Text("CME: \(e.cmeHours) hours").font(.caption) }
                if !e.details.isEmpty { Text(e.details).font(.caption).foregroundStyle(.secondary) }
                Text(e.specialties.isEmpty ? "Open to all specialties" : e.specialties.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                stat("Coming", invs.filter { $0.status == .coming }.count, .green)
                stat("Maybe", invs.filter { $0.status == .maybe }.count, .orange)
                stat("No", invs.filter { $0.status == .no }.count, .red)
                stat("Target", e.target, .primary)
            }
        }
    }

    @ViewBuilder
    private func invitedSections(_ invs: [Invite]) -> some View {
        if invs.isEmpty {
            Text("Nobody invited yet. Use the Invite tab.").foregroundStyle(.secondary)
        }
        ForEach(InviteStatus.allCases) { status in
            statusSection(status, invs.filter { $0.status == status })
        }
    }

    @ViewBuilder
    private func statusSection(_ status: InviteStatus, _ group: [Invite]) -> some View {
        if !group.isEmpty {
            Section("\(status.rawValue) (\(group.count))") {
                ForEach(group) { inv in
                    if let d = store.doctor(inv.doctorID) {
                        NavigationLink {
                            InviteDetailView(inviteID: inv.id)
                        } label: {
                            InviteRowLabel(doctor: d, invite: inv)
                        }
                    }
                }
            }
        }
    }

    private func matches(_ d: Doctor) -> Bool {
        if search.isEmpty { return true }
        if d.name.localizedCaseInsensitiveContains(search) { return true }
        let h = store.hospital(d.hospitalID)?.name ?? ""
        return h.localizedCaseInsensitiveContains(search)
    }

    @ViewBuilder
    private func inviteSections(_ e: MedEvent, _ invs: [Invite]) -> some View {
        let invited = Set(invs.map(\.doctorID))
        let eligible = store.sortedDoctors.filter { d in
            e.allows(d.specialty) && !invited.contains(d.id) && matches(d)
        }
        Section {
            TextField("Search doctor or hospital", text: $search)
        }
        Section("Matching doctors not invited (\(eligible.count))") {
            if eligible.isEmpty {
                Text("No matching doctors left. Add doctors in the Doctors tab.").foregroundStyle(.secondary)
            }
            ForEach(eligible) { d in
                HStack {
                    VStack(alignment: .leading) {
                        HStack(spacing: 6) {
                            Text(d.displayName)
                            if store.isFirstTimer(d.id) {
                                Text("first-timer").font(.caption2.bold()).foregroundStyle(.blue)
                            }
                        }
                        Text("\(d.specialty) - \(store.hospital(d.hospitalID)?.name ?? "No hospital")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Invite") { store.inviteDoctor(d.id, to: e.id) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private func eventDaySection(_ invs: [Invite]) -> some View {
        let active = invs.filter { $0.status != .no }
        Section {
            if active.isEmpty { Text("No one coming or maybe.").foregroundStyle(.secondary) }
            ForEach(active) { inv in
                if let d = store.doctor(inv.doctorID) {
                    AttendanceRow(doctor: d, invite: inv)
                }
            }
        } header: {
            Text("Who came?")
        } footer: {
            Text("Mark each doctor. Thank-you and we-missed-you messages then appear on Today.")
        }
    }

    private func repCount(_ r: Rep, _ invs: [Invite]) -> Int {
        invs.filter { inv in
            guard let d = store.doctor(inv.doctorID), let h = store.hospital(d.hospitalID) else { return false }
            return h.repIDs.contains(r.id)
        }.count
    }

    @ViewBuilder
    private func shareSection(_ e: MedEvent, _ invs: [Invite]) -> some View {
        Section("Share") {
            ExportButton(label: "Share full list as Excel",
                         fileName: "\(e.name) \(e.date.shortText)") { hide in
                store.eventTable(e, hidePhones: hide)
            }
            ForEach(store.data.reps.filter { repCount($0, invs) > 0 }) { r in
                ExportButton(label: "Only \(r.name)'s hospitals (\(repCount(r, invs)))",
                             fileName: "\(e.name) \(e.date.shortText) - \(r.name)") { hide in
                    store.eventTable(e, hidePhones: hide, onlyRep: r.id)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack {
            Text("\(value)").font(.title2.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct InviteRowLabel: View {
    @EnvironmentObject var store: Store
    let doctor: Doctor
    let invite: Invite
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(doctor.displayName).font(.headline)
                Spacer()
                StatusBadge(status: invite.status)
            }
            Text("\(doctor.specialty) - \(store.hospital(doctor.hospitalID)?.name ?? "No hospital")")
                .font(.caption).foregroundStyle(.secondary)
            if invite.status == .no, let r = invite.noReason {
                Text(r.rawValue).font(.caption).foregroundStyle(.red)
            }
            if let rid = invite.askedRepID, let r = store.rep(rid) {
                Text("Asked \(r.name) to help").font(.caption).foregroundStyle(.blue)
            }
            if let last = invite.lastMessaged {
                Text("Last messaged \(last.shortText)").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct AttendanceRow: View {
    @EnvironmentObject var store: Store
    let doctor: Doctor
    let invite: Invite
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(doctor.displayName)
                StatusBadge(status: invite.status)
            }
            Spacer()
            Button {
                set(true)
            } label: {
                Image(systemName: invite.attended == true ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.title2).foregroundStyle(.green)
            }
            Button {
                set(false)
            } label: {
                Image(systemName: invite.attended == false ? "xmark.circle.fill" : "xmark.circle")
                    .font(.title2).foregroundStyle(.red)
            }
        }
        .buttonStyle(.borderless)
    }
    private func set(_ came: Bool) {
        guard var inv = store.invite(invite.id) else { return }
        inv.attended = (inv.attended == came) ? nil : came
        store.upsert(inv)
    }
}

struct InviteDetailView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let inviteID: UUID
    @State private var compose: ComposeItem?

    private var binding: Binding<Invite>? {
        guard let inv = store.invite(inviteID) else { return nil }
        return Binding(get: { store.invite(inviteID) ?? inv }, set: { store.upsert($0) })
    }

    var body: some View {
        if let b = binding, let d = store.doctor(b.wrappedValue.doctorID), let e = store.event(b.wrappedValue.eventID) {
            Form {
                topSection(d, e)
                answerSection(b)
                repSection(b, d)
                messageSection(b, d)
                sentSection(b.wrappedValue)
                Section {
                    Button("Remove from this event", role: .destructive) {
                        dismiss()
                        store.deleteInvite(inviteID)
                    }
                }
            }
            .navigationTitle("Invite")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $compose) { ComposeSheet(item: $0) }
        } else {
            Text("Invite removed").foregroundStyle(.secondary)
        }
    }

    private func topSection(_ d: Doctor, _ e: MedEvent) -> some View {
        Section {
            NavigationLink {
                DoctorDetailView(doctorID: d.id)
            } label: {
                VStack(alignment: .leading) {
                    Text(d.displayName).font(.headline)
                    Text("\(d.specialty) - \(store.hospital(d.hospitalID)?.name ?? "No hospital")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("\(e.name) - \(e.date.shortText)").font(.subheadline)
        }
    }

    private func answerSection(_ b: Binding<Invite>) -> some View {
        Section("His answer") {
            Picker("Status", selection: b.status) {
                ForEach(InviteStatus.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if b.wrappedValue.status == .no {
                Picker("Reason", selection: Binding<NoReason>(
                    get: { b.wrappedValue.noReason ?? .busy },
                    set: { b.wrappedValue.noReason = $0 }
                )) {
                    ForEach(NoReason.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("Reason details (optional)", text: b.reasonNote)
            }
            TextField("Note (what you agreed, who he'll bring...)", text: b.note, axis: .vertical)
                .lineLimit(2...5)
        }
    }

    private func repSection(_ b: Binding<Invite>, _ d: Doctor) -> some View {
        let reps = store.reps(forDoctor: d)
        return Section("Mirror reps") {
            if reps.isEmpty {
                Text("No mirror rep set for his hospital.").foregroundStyle(.secondary)
            }
            ForEach(reps) { r in
                Button {
                    let id = inviteID
                    compose = ComposeItem(to: r.name, phone: r.phone,
                                          text: store.repHelpText(rep: r, invite: b.wrappedValue),
                                          onSent: {
                                              if var inv = store.invite(id) {
                                                  inv.askedRepID = r.id
                                                  store.upsert(inv)
                                              }
                                          })
                } label: {
                    Label("Ask \(r.name) for help", systemImage: "person.2.fill")
                }
            }
            Picker("Helped by", selection: b.helperRepID) {
                Text("Nobody").tag(UUID?.none)
                ForEach(store.data.reps) { r in Text(r.name).tag(UUID?.some(r.id)) }
            }
        }
    }

    private func messageSection(_ b: Binding<Invite>, _ d: Doctor) -> some View {
        Section("Send a message") {
            ForEach(MessageKind.allCases) { kind in
                Button {
                    let id = inviteID
                    compose = ComposeItem(to: d.displayName, phone: d.phone,
                                          text: store.messageText(kind, invite: b.wrappedValue),
                                          onSent: { store.markSent(id, kind) })
                } label: {
                    HStack {
                        Text(kind.title)
                        Spacer()
                        if b.wrappedValue.sent.contains(where: { $0.kind == kind }) {
                            Image(systemName: "checkmark").foregroundStyle(.green)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sentSection(_ inv: Invite) -> some View {
        if !inv.sent.isEmpty {
            Section("Sent") {
                ForEach(Array(inv.sent.enumerated()), id: \.offset) { _, m in
                    HStack {
                        Text(m.kind.title)
                        Spacer()
                        Text(m.date.shortText).foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}
