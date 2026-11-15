import SwiftUI
import UniformTypeIdentifiers

struct MoreView: View {
    @EnvironmentObject var store: Store
    @State private var share: ShareFile?
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Me") {
                    TextField("Your name", text: $store.data.myName)
                    TextField("Company", text: $store.data.company)
                }
                Section {
                    NavigationLink { RepsView() } label: { Label("Mirror reps", systemImage: "person.2") }
                    NavigationLink { OccasionsView() } label: { Label("Occasions & greetings", systemImage: "gift") }
                    NavigationLink { WinsView() } label: { Label("Wins & report", systemImage: "chart.bar") }
                }
                Section {
                    Button {
                        do { share = ShareFile(url: try store.backupURL()) } catch { message = error.localizedDescription }
                    } label: {
                        Label("Save a backup", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("Restore from backup", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Everything is stored only on this iPhone. Save a backup to Files now and then, so a phone reset doesn't wipe your list.")
                }
            }
            .navigationTitle("More")
            .sheet(item: $share) { ActivityView(url: $0.url) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do { try store.restore(from: url); message = "Backup restored." } catch { message = "That file isn't a valid backup." }
                case .failure(let err):
                    message = err.localizedDescription
                }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}

struct RepsView: View {
    @EnvironmentObject var store: Store
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                ForEach($store.data.reps) { $r in
                    VStack(alignment: .leading) {
                        TextField("Name", text: $r.name).font(.headline)
                        TextField("WhatsApp number (05...)", text: $r.phone).keyboardType(.phonePad)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { idx in store.data.reps.remove(atOffsets: idx) }
            } footer: {
                Text("Swipe left to remove a rep.")
            }
            Section("Add rep") {
                HStack {
                    TextField("Name", text: $newName)
                    Button("Add") {
                        let n = newName.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty else { return }
                        store.data.reps.append(Rep(name: n))
                        newName = ""
                    }
                }
            }
        }
        .navigationTitle("Mirror reps")
    }
}

struct OccasionsView: View {
    @EnvironmentObject var store: Store
    @State private var editing: Occasion?

    var body: some View {
        List {
            Section {
                ForEach(store.data.occasions.sorted { $0.date < $1.date }) { o in
                    NavigationLink {
                        GreetingsView(occasionID: o.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(o.name).font(.headline)
                            Text(Store.sheetDate.string(from: o.date) + (o.estimated ? " (estimated - edit after moon sighting)" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                            Text("\(o.greetedIDs.count) greeted").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Edit") { editing = o }.tint(.blue)
                        Button("Delete", role: .destructive) { store.data.occasions.removeAll { $0.id == o.id } }
                    }
                }
            } footer: {
                Text("Swipe left to edit or delete. Use {doctor} in the message and it becomes his name.")
            }
        }
        .navigationTitle("Occasions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = Occasion(name: "", date: Date(), message: "Dear {doctor}, \n\n\(store.data.myName), \(store.data.company)")
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { OccasionEditView(occasion: $0) }
    }
}

struct OccasionEditView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var occasion: Occasion

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $occasion.name)
                DatePicker("Date", selection: $occasion.date, displayedComponents: .date)
                Toggle("Date is an estimate", isOn: $occasion.estimated)
                Section("Message") {
                    TextEditor(text: $occasion.message).frame(minHeight: 160)
                }
                Section {
                    Button("Reset who was greeted") { occasion.greetedIDs = [] }
                }
            }
            .navigationTitle("Occasion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.upsert(occasion); dismiss() }
                        .disabled(occasion.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct WinsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let invites = store.data.invites
        let came = invites.filter { $0.attended == true }
        let confirmed = invites.filter { $0.status == .coming && $0.attended != nil }
        let confirmedCame = confirmed.filter { $0.attended == true }.count
        let firstTimers = came.filter { inv in store.isFirstTimer(inv.doctorID, before: store.event(inv.eventID)) }
        let helped = came.filter { $0.helperRepID != nil }
        List {
            Section("Totals") {
                LabeledContent("Doctors on your list", value: "\(store.data.doctors.count)")
                LabeledContent("Invites sent", value: "\(invites.count)")
                LabeledContent("Doctors who came", value: "\(came.count)")
                LabeledContent("Show rate (confirmed who came)",
                               value: Store.percent(confirmedCame, of: confirmed.count))
                LabeledContent("First-timers who came", value: "\(firstTimers.count)")
                LabeledContent("Came with a mirror rep's help", value: "\(helped.count)")
                LabeledContent("WhatsApp messages sent", value: "\(invites.reduce(0) { $0 + $1.sent.count })")
            }
            if !firstTimers.isEmpty {
                Section("First-timers") {
                    ForEach(firstTimers) { inv in
                        if let d = store.doctor(inv.doctorID), let e = store.event(inv.eventID) {
                            LabeledContent(d.displayName, value: e.name)
                        }
                    }
                }
            }
            if !helped.isEmpty {
                Section("Teamwork") {
                    ForEach(helped) { inv in
                        if let d = store.doctor(inv.doctorID), let r = store.rep(inv.helperRepID) {
                            LabeledContent(d.displayName, value: "with \(r.name)")
                        }
                    }
                }
            }
            Section("Share") {
                ExportButton(label: "Share report as Excel", fileName: "Event report \(Date().shortText)") { _ in
                    store.reportTable()
                }
            }
        }
        .navigationTitle("Wins & report")
    }
}
