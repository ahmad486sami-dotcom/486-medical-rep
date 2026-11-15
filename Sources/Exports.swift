import Foundation

extension Store {
    static func percent(_ part: Int, of total: Int) -> String {
        guard total > 0 else { return "-" }
        let p: Double = Double(part) / Double(total) * 100
        return "\(Int(p.rounded()))%"
    }

    private var preparedLine: String {
        "Prepared by \(data.myName) - \(Store.sheetDate.string(from: Date()))"
    }

    private func withText(_ d: Doctor) -> String {
        var parts: [String] = []
        let bring = d.bringingIDs.compactMap { doctor($0)?.displayName }
        let ifs = d.comesIfIDs.compactMap { doctor($0)?.displayName }
        if !bring.isEmpty { parts.append("with " + bring.joined(separator: ", ")) }
        if !ifs.isEmpty { parts.append("if " + ifs.joined(separator: ", ")) }
        return parts.joined(separator: "; ")
    }

    private func statusText(_ inv: Invite) -> String {
        if inv.status == .no, let r = inv.noReason {
            return inv.reasonNote.isEmpty ? "No - \(r.rawValue)" : "No - \(r.rawValue) (\(inv.reasonNote))"
        }
        return inv.status.rawValue
    }

    private func attendedText(_ inv: Invite) -> String {
        switch inv.attended {
        case .some(true): return "Came"
        case .some(false): return "Didn't come"
        case .none: return ""
        }
    }

    private func dateText(_ d: Date?) -> String {
        guard let d = d else { return "" }
        return Store.sheetDate.string(from: d)
    }

    /// Event list, optionally only one mirror rep's hospitals.
    func eventTable(_ e: MedEvent, hidePhones: Bool, onlyRep: UUID? = nil) -> SheetTable {
        let order: [InviteStatus] = [.coming, .maybe, .no]
        var invs = invites(forEvent: e.id).sorted {
            let a = order.firstIndex(of: $0.status) ?? 0, b = order.firstIndex(of: $1.status) ?? 0
            if a != b { return a < b }
            return (doctor($0.doctorID)?.name ?? "") < (doctor($1.doctorID)?.name ?? "")
        }
        if let rid = onlyRep {
            invs = invs.filter { inv in
                guard let d = doctor(inv.doctorID), let h = hospital(d.hospitalID) else { return false }
                return h.repIDs.contains(rid)
            }
        }
        var headers = ["#", "Doctor", "Specialty", "Hospital"]
        if !hidePhones { headers.append("Phone") }
        headers += ["Status", "With", "Mirror rep", "Helped by", "Last messaged", "Attended", "Note"]

        var rows: [[String]] = []
        for (i, inv) in invs.enumerated() {
            guard let d = doctor(inv.doctorID) else { continue }
            var row = [String(i + 1), d.displayName, d.specialty, hospital(d.hospitalID)?.name ?? ""]
            if !hidePhones { row.append(d.phone) }
            row += [statusText(inv), withText(d),
                    reps(forDoctor: d).map(\.name).joined(separator: ", "),
                    rep(inv.helperRepID)?.name ?? "",
                    dateText(inv.lastMessaged), attendedText(inv), inv.note]
            rows.append(row)
        }
        let coming = invs.filter { $0.status == .coming }.count
        let maybe = invs.filter { $0.status == .maybe }.count
        let no = invs.filter { $0.status == .no }.count
        var title = "\(e.name) - \(Store.longDate.string(from: e.date))"
        if !e.venue.isEmpty { title += " - \(e.venue)" }
        let widths: [Double] = hidePhones
            ? [4, 22, 16, 22, 26, 22, 16, 12, 14, 12, 30]
            : [4, 22, 16, 22, 15, 26, 22, 16, 12, 14, 12, 30]
        return SheetTable(title: title,
                          subtitle: "\(preparedLine)   |   Coming \(coming), Maybe \(maybe), No \(no), Target \(e.target)",
                          headers: headers, rows: rows, widths: widths)
    }

    func hospitalTable(_ h: Hospital, hidePhones: Bool) -> SheetTable {
        let upcoming = data.events.filter { $0.date >= Calendar.current.startOfDay(for: Date()) }
        var headers = ["#", "Doctor", "Specialty"]
        if !hidePhones { headers.append("Phone") }
        headers += ["Visits this month", "Upcoming invites", "With", "Notes"]
        var rows: [[String]] = []
        for (i, d) in doctors(inHospital: h.id).enumerated() {
            let inv = upcoming.compactMap { e -> String? in
                guard let x = invite(event: e.id, doctor: d.id) else { return nil }
                return "\(e.name): \(statusText(x))"
            }.joined(separator: "; ")
            var row = [String(i + 1), d.displayName, d.specialty]
            if !hidePhones { row.append(d.phone) }
            row += ["\(visitsThisMonth(d))/\(d.visitsPerMonth)", inv, withText(d), d.notes]
            rows.append(row)
        }
        let repsText = h.repIDs.compactMap { rep($0)?.name }.joined(separator: ", ")
        let widths: [Double] = hidePhones ? [4, 22, 16, 10, 34, 22, 34] : [4, 22, 16, 15, 10, 34, 22, 34]
        return SheetTable(title: "\(h.name)\(h.area.isEmpty ? "" : " - \(h.area)")",
                          subtitle: "\(preparedLine)   |   Mirror reps: \(repsText.isEmpty ? "-" : repsText)",
                          headers: headers, rows: rows, widths: widths)
    }

    func doctorTable(_ d: Doctor, hidePhones: Bool) -> SheetTable {
        let headers = ["#", "Event", "Date", "Status", "Messages sent", "Helped by", "Attended", "Note"]
        let invs = invites(forDoctor: d.id).sorted {
            (event($0.eventID)?.date ?? .distantPast) > (event($1.eventID)?.date ?? .distantPast)
        }
        var rows: [[String]] = []
        for (i, inv) in invs.enumerated() {
            guard let e = event(inv.eventID) else { continue }
            rows.append([String(i + 1), e.name, dateText(e.date), statusText(inv), String(inv.sent.count),
                         rep(inv.helperRepID)?.name ?? "", attendedText(inv), inv.note])
        }
        var info = "\(d.specialty) - \(hospital(d.hospitalID)?.name ?? "No hospital")"
        if !hidePhones && !d.phone.isEmpty { info += " - \(d.phone)" }
        return SheetTable(title: "\(d.displayName) (\(info))",
                          subtitle: "\(preparedLine)   |   Visits this month \(visitsThisMonth(d))/\(d.visitsPerMonth)",
                          headers: headers, rows: rows, widths: [4, 26, 12, 26, 10, 12, 12, 34])
    }

    func reportTable() -> SheetTable {
        let headers = ["#", "Event", "Date", "Invited", "Coming", "Maybe", "No", "Came", "Show rate",
                       "First-timers came", "Helped by reps", "No reasons"]
        var rows: [[String]] = []
        for (i, e) in data.events.sorted(by: { $0.date > $1.date }).enumerated() {
            let invs = invites(forEvent: e.id)
            let coming = invs.filter { $0.status == .coming }
            let came = invs.filter { $0.attended == true }
            let comingCame = came.filter { $0.status == .coming }.count
            let rate = Store.percent(comingCame, of: coming.count)
            let first = came.filter { isFirstTimer($0.doctorID, before: e) }.count
            let helped = invs.filter { $0.helperRepID != nil }.count
            var reasons: [String: Int] = [:]
            for inv in invs where inv.status == .no { reasons[inv.noReason?.rawValue ?? "No reason", default: 0] += 1 }
            let reasonText = reasons.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "; ")
            rows.append([String(i + 1), e.name, dateText(e.date), String(invs.count), String(coming.count),
                         String(invs.filter { $0.status == .maybe }.count), String(invs.filter { $0.status == .no }.count),
                         String(came.count), rate, String(first), String(helped), reasonText])
        }
        let totalCame = data.invites.filter { $0.attended == true }.count
        return SheetTable(title: "Event invitations summary - \(data.myName)",
                          subtitle: "\(preparedLine)   |   Doctors on list \(data.doctors.count), total attended \(totalCame)",
                          headers: headers, rows: rows, widths: [4, 26, 12, 8, 8, 8, 6, 7, 9, 10, 10, 34])
    }

    func backupURL() throws -> URL {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        let raw = try enc.encode(data)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("486 Medical Rep backup \(f.string(from: Date())).json")
        try raw.write(to: url, options: .atomic)
        return url
    }

    func restore(from url: URL) throws {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let raw = try Data(contentsOf: url)
        data = try JSONDecoder().decode(AppData.self, from: raw)
    }
}
