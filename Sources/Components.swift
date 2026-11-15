import SwiftUI
import UIKit

struct ComposeItem: Identifiable {
    let id = UUID()
    var to: String
    var phone: String
    var text: String
    var onSent: () -> Void = {}
}

/// Edit the message, then open WhatsApp with it ready to send.
struct ComposeSheet: View {
    let item: ComposeItem
    @State private var text: String
    @State private var copied = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(item: ComposeItem) {
        self.item = item
        _text = State(initialValue: item.text)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("To") {
                    Text(item.to).font(.headline)
                    Text(item.phone.isEmpty ? "No number saved - WhatsApp will ask you to pick a chat" : item.phone)
                        .foregroundStyle(.secondary)
                }
                Section("Message (edit anything)") {
                    TextEditor(text: $text).frame(minHeight: 240)
                }
                Section {
                    Button {
                        if let url = WhatsApp.url(phone: item.phone, text: text) {
                            item.onSent()
                            openURL(url)
                            dismiss()
                        }
                    } label: {
                        Label("Open in WhatsApp", systemImage: "paperplane.fill").font(.headline)
                    }
                    Button {
                        UIPasteboard.general.string = text
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy text", systemImage: "doc.on.doc")
                    }
                    Button("Mark as sent without opening") {
                        item.onSent()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// "Share as Excel" button with a hide-numbers switch.
struct ExportButton: View {
    let label: String
    let fileName: String
    let make: (Bool) -> SheetTable
    @State private var askOptions = false
    @State private var hidePhones = false
    @State private var share: ShareFile?
    @State private var errorText: String?

    var body: some View {
        Button {
            askOptions = true
        } label: {
            Label(label, systemImage: "tablecells")
        }
        .confirmationDialog("Share as Excel", isPresented: $askOptions, titleVisibility: .visible) {
            Button("With phone numbers") { run(hide: false) }
            Button("Hide phone numbers") { run(hide: true) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $share) { f in ActivityView(url: f.url) }
        .alert("Couldn't make the file", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func run(hide: Bool) {
        do {
            let url = try XLSX.write(make(hide), fileName: fileName)
            share = ShareFile(url: url)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Pick several doctors (used for "bringing" and "comes if").
struct DoctorMultiPicker: View {
    @EnvironmentObject var store: Store
    let title: String
    let excluding: UUID
    @Binding var selection: [UUID]
    @State private var search = ""

    var body: some View {
        List {
            ForEach(store.sortedDoctors.filter { $0.id != excluding && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }) { d in
                Button {
                    if let i = selection.firstIndex(of: d.id) { selection.remove(at: i) } else { selection.append(d.id) }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(d.displayName).foregroundStyle(.primary)
                            Text("\(d.specialty) - \(store.hospital(d.hospitalID)?.name ?? "No hospital")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selection.contains(d.id) { Image(systemName: "checkmark").foregroundStyle(.green) }
                    }
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle(title)
    }
}

struct StatusBadge: View {
    let status: InviteStatus
    var body: some View {
        Text(status.rawValue)
            .font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
    var color: Color {
        switch status {
        case .coming: return .green
        case .maybe: return .orange
        case .no: return .red
        }
    }
}

extension Date {
    var shortText: String { Store.shortDate.string(from: self) }
}
