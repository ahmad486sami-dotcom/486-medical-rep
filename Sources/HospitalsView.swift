import SwiftUI

struct HospitalsView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                if store.data.hospitals.isEmpty {
                    Text("No hospitals yet. Tap + to add one and pick its mirror reps.").foregroundStyle(.secondary)
                }
                ForEach(store.sortedHospitals) { h in
                    NavigationLink {
                        HospitalDetailView(hospitalID: h.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(h.name).font(.headline)
                            Text([h.area, "\(store.doctors(inHospital: h.id).count) doctors"]
                                    .filter { !$0.isEmpty }.joined(separator: " - "))
                                .font(.caption).foregroundStyle(.secondary)
                            let reps = h.repIDs.compactMap { store.rep($0)?.name }
                            if !reps.isEmpty {
                                Text("Mirror: " + reps.joined(separator: ", ")).font(.caption2).foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Hospitals")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $adding) { HospitalEditView(hospital: Hospital(name: ""), isNew: true) }
        }
    }
}

struct HospitalEditView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var hospital: Hospital
    let isNew: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Hospital") {
                    TextField("Name", text: $hospital.name)
                    TextField("Area (e.g. Ruwais, Madinat Zayed)", text: $hospital.area)
                }
                Section {
                    ForEach(store.data.reps) { r in
                        Toggle(r.name, isOn: Binding(
                            get: { hospital.repIDs.contains(r.id) },
                            set: { on in
                                if on { hospital.repIDs.append(r.id) } else { hospital.repIDs.removeAll { $0 == r.id } }
                            }
                        ))
                    }
                } header: {
                    Text("Mirror reps covering it")
                } footer: {
                    Text("Add or edit reps (and their numbers) in More > Mirror reps.")
                }
            }
            .navigationTitle(isNew ? "New hospital" : "Edit hospital")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.upsert(hospital); dismiss() }
                        .disabled(hospital.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Pre-visit brief: everyone at this hospital, their latest status and notes.
struct HospitalDetailView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let hospitalID: UUID
    @State private var editing = false
    @State private var adding = false
    @State private var confirmDelete = false

    var body: some View {
        if let h = store.hospital(hospitalID) {
            List {
                Section("Mirror reps") {
                    let reps = h.repIDs.compactMap { store.rep($0) }
                    if reps.isEmpty { Text("None set. Tap Edit.").foregroundStyle(.secondary) }
                    ForEach(reps) { r in
                        LabeledContent(r.name, value: r.phone.isEmpty ? "No number" : r.phone)
                    }
                }
                Section("Before your visit") {
                    let docs = store.doctors(inHospital: h.id)
                    if docs.isEmpty { Text("No doctors here yet.").foregroundStyle(.secondary) }
                    ForEach(docs) { d in
                        NavigationLink {
                            DoctorDetailView(doctorID: d.id)
                        } label: {
                            BriefRow(doctor: d)
                        }
                    }
                    Button {
                        adding = true
                    } label: {
                        Label("Add doctor here", systemImage: "plus")
                    }
                }
                Section("Share") {
                    ExportButton(label: "Share hospital brief as Excel", fileName: h.name) { hide in
                        store.hospitalTable(h, hidePhones: hide)
                    }
                }
                Section {
                    Button("Delete hospital", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(h.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true } }
            }
            .sheet(isPresented: $editing) { HospitalEditView(hospital: h, isNew: false) }
            .sheet(isPresented: $adding) {
                DoctorEditView(doctor: Doctor(name: "", hospitalID: h.id), isNew: true)
            }
            .confirmationDialog("Delete \(h.name)? Its doctors stay in your list.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    dismiss()
                    store.deleteHospital(h.id)
                }
            }
        } else {
            Text("Hospital deleted").foregroundStyle(.secondary)
        }
    }
}

struct BriefRow: View {
    @EnvironmentObject var store: Store
    let doctor: Doctor
    var body: some View {
        let start = Calendar.current.startOfDay(for: Date())
        let pending = store.invites(forDoctor: doctor.id).filter { inv in
            (store.event(inv.eventID)?.date ?? .distantPast) >= start
        }
        VStack(alignment: .leading, spacing: 3) {
            Text(doctor.displayName).font(.headline)
            Text("\(doctor.specialty) - visits \(store.visitsThisMonth(doctor))/\(doctor.visitsPerMonth)")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(pending) { inv in
                if let e = store.event(inv.eventID) {
                    HStack {
                        Text(e.name).font(.caption)
                        StatusBadge(status: inv.status)
                    }
                }
            }
            if !doctor.notes.isEmpty {
                Text(doctor.notes).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}
