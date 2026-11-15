import SwiftUI

struct DoctorsView: View {
    @EnvironmentObject var store: Store
    @State private var search = ""
    @State private var specialty = "All"
    @State private var onlyDue = false
    @State private var adding = false

    private func matches(_ d: Doctor) -> Bool {
        if specialty != "All" && d.specialty != specialty { return false }
        if onlyDue && store.visitsThisMonth(d) >= d.visitsPerMonth { return false }
        if search.isEmpty { return true }
        if d.name.localizedCaseInsensitiveContains(search) { return true }
        return (store.hospital(d.hospitalID)?.name ?? "").localizedCaseInsensitiveContains(search)
    }

    var body: some View {
        NavigationStack {
            List {
                let list = store.sortedDoctors.filter { matches($0) }
                Section {
                    Picker("Specialty", selection: $specialty) {
                        Text("All").tag("All")
                        ForEach(Specialty.all, id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("Only visits due this month", isOn: $onlyDue)
                }
                Section("\(list.count) doctor\(list.count == 1 ? "" : "s")") {
                    if store.data.doctors.isEmpty {
                        Text("No doctors yet. Tap + after your first visit.").foregroundStyle(.secondary)
                    }
                    ForEach(list) { d in
                        NavigationLink {
                            DoctorDetailView(doctorID: d.id)
                        } label: {
                            DoctorRowLabel(doctor: d)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Doctor or hospital")
            .navigationTitle("Doctors")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $adding) {
                DoctorEditView(doctor: Doctor(name: ""), isNew: true)
            }
        }
    }
}

struct DoctorRowLabel: View {
    @EnvironmentObject var store: Store
    let doctor: Doctor
    var body: some View {
        let visits = store.visitsThisMonth(doctor)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(doctor.displayName).font(.headline)
                if store.isFirstTimer(doctor.id) {
                    Text("first-timer").font(.caption2.bold()).foregroundStyle(.blue)
                }
            }
            Text("\(doctor.specialty) - \(store.hospital(doctor.hospitalID)?.name ?? "No hospital")")
                .font(.caption).foregroundStyle(.secondary)
            Text("Visits this month: \(visits)/\(doctor.visitsPerMonth)")
                .font(.caption2)
                .foregroundStyle(visits >= doctor.visitsPerMonth ? Color.green : Color.orange)
        }
    }
}

struct DoctorEditView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var doctor: Doctor
    let isNew: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Doctor") {
                    TextField("Name", text: $doctor.name)
                    Picker("Specialty", selection: $doctor.specialty) {
                        ForEach(Specialty.all, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Hospital", selection: $doctor.hospitalID) {
                        Text("None").tag(UUID?.none)
                        ForEach(store.sortedHospitals) { h in Text(h.name).tag(UUID?.some(h.id)) }
                    }
                    TextField("WhatsApp number (05...)", text: $doctor.phone).keyboardType(.phonePad)
                    TextField("LinkedIn link (optional)", text: $doctor.linkedIn)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Visits") {
                    Stepper("Required: \(doctor.visitsPerMonth) per month", value: $doctor.visitsPerMonth, in: 0...10)
                }
                Section {
                    NavigationLink {
                        DoctorMultiPicker(title: "Bringing", excluding: doctor.id, selection: $doctor.bringingIDs)
                    } label: {
                        LabeledContent("Usually brings", value: names(doctor.bringingIDs))
                    }
                    NavigationLink {
                        DoctorMultiPicker(title: "Comes if", excluding: doctor.id, selection: $doctor.comesIfIDs)
                    } label: {
                        LabeledContent("Comes only if", value: names(doctor.comesIfIDs))
                    }
                } header: {
                    Text("Colleagues")
                } footer: {
                    Text("\"Brings\" adds them to events together. \"Comes only if\" warns you when that colleague says no.")
                }
                Section("Notes") {
                    TextField("Anything useful (shifts, interests...)", text: $doctor.notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                if store.data.hospitals.isEmpty {
                    Section {
                        Text("Tip: add hospitals in the Hospitals tab so each doctor gets his mirror rep.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(isNew ? "New doctor" : "Edit doctor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.upsert(doctor); dismiss() }
                        .disabled(doctor.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func names(_ ids: [UUID]) -> String {
        let n = ids.compactMap { store.doctor($0)?.displayName }
        return n.isEmpty ? "None" : n.joined(separator: ", ")
    }
}

struct DoctorDetailView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let doctorID: UUID
    @State private var editing = false
    @State private var compose: ComposeItem?
    @State private var confirmDelete = false

    var body: some View {
        if let d = store.doctor(doctorID) {
            List {
                infoSection(d)
                linksSection(d)
                historySection(d)
                Section("Share") {
                    ExportButton(label: "Share his history as Excel", fileName: d.displayName) { hide in
                        store.doctorTable(d, hidePhones: hide)
                    }
                }
                Section {
                    Button("Delete doctor", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(d.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true } }
            }
            .sheet(isPresented: $editing) { DoctorEditView(doctor: d, isNew: false) }
            .sheet(item: $compose) { ComposeSheet(item: $0) }
            .confirmationDialog("Delete \(d.displayName) and his invites?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    dismiss()
                    store.deleteDoctor(d.id)
                }
            }
        } else {
            Text("Doctor deleted").foregroundStyle(.secondary)
        }
    }

    private func infoSection(_ d: Doctor) -> some View {
        let visits = store.visitsThisMonth(d)
        return Section {
            LabeledContent("Specialty", value: d.specialty)
            LabeledContent("Hospital", value: store.hospital(d.hospitalID)?.name ?? "None")
            if !d.phone.isEmpty { LabeledContent("WhatsApp", value: d.phone) }
            LabeledContent("Visits this month", value: "\(visits)/\(d.visitsPerMonth)")
            if let last = d.visits.max() { LabeledContent("Last visit", value: last.shortText) }
            Button {
                store.logVisit(d.id)
            } label: {
                Label("Log a visit today", systemImage: "figure.walk")
            }
            Button {
                compose = ComposeItem(to: d.displayName, phone: d.phone,
                                      text: "Hello \(d.displayName), it's \(store.data.myName), \(store.data.company). ")
            } label: {
                Label("Message him", systemImage: "message.fill")
            }
            if !d.linkedIn.isEmpty {
                Button {
                    let raw = d.linkedIn.trimmingCharacters(in: .whitespaces)
                    let full = raw.lowercased().hasPrefix("http") ? raw : "https://" + raw
                    if let url = URL(string: full) { openURL(url) }
                } label: {
                    Label("Open LinkedIn", systemImage: "link")
                }
            }
            if !d.notes.isEmpty {
                Text(d.notes).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func linksSection(_ d: Doctor) -> some View {
        let reps = store.reps(forDoctor: d)
        let bring = d.bringingIDs.compactMap { store.doctor($0) }
        let ifs = d.comesIfIDs.compactMap { store.doctor($0) }
        if !reps.isEmpty || !bring.isEmpty || !ifs.isEmpty {
            Section("People") {
                if !reps.isEmpty {
                    LabeledContent("Mirror reps", value: reps.map(\.name).joined(separator: ", "))
                }
                ForEach(bring) { b in
                    NavigationLink { DoctorDetailView(doctorID: b.id) } label: {
                        Label("Brings \(b.displayName)", systemImage: "person.badge.plus")
                    }
                }
                ForEach(ifs) { b in
                    NavigationLink { DoctorDetailView(doctorID: b.id) } label: {
                        Label("Comes if \(b.displayName) comes", systemImage: "link")
                    }
                }
            }
        }
    }

    private func historySection(_ d: Doctor) -> some View {
        let invs = store.invites(forDoctor: d.id).sorted {
            (store.event($0.eventID)?.date ?? .distantPast) > (store.event($1.eventID)?.date ?? .distantPast)
        }
        return Section("Events history") {
            if invs.isEmpty { Text("Not invited to anything yet.").foregroundStyle(.secondary) }
            ForEach(invs) { inv in
                if let e = store.event(inv.eventID) {
                    NavigationLink {
                        InviteDetailView(inviteID: inv.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(e.name)
                                Text(e.date.shortText + attendedText(inv)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusBadge(status: inv.status)
                        }
                    }
                }
            }
        }
    }

    private func attendedText(_ inv: Invite) -> String {
        switch inv.attended {
        case .some(true): return " - came"
        case .some(false): return " - didn't come"
        case .none: return ""
        }
    }
}
