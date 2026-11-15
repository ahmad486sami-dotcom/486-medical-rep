import Foundation
import SwiftUI

struct DueMessage: Identifiable {
    let invite: Invite
    let kind: MessageKind
    var id: String { invite.id.uuidString + kind.rawValue }
}

struct Suggestion: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
}

final class Store: ObservableObject {
    @Published var data: AppData {
        didSet { save() }
    }

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("486-medical-rep-data.json")
    }

    init() {
        if let raw = try? Data(contentsOf: Store.fileURL),
           let decoded = try? JSONDecoder().decode(AppData.self, from: raw) {
            data = decoded
        } else {
            data = AppData.starter()
        }
    }

    func save() {
        if let raw = try? JSONEncoder().encode(data) {
            try? raw.write(to: Store.fileURL, options: .atomic)
        }
    }

    // MARK: Lookups

    func doctor(_ id: UUID?) -> Doctor? { data.doctors.first { $0.id == id } }
    func hospital(_ id: UUID?) -> Hospital? { data.hospitals.first { $0.id == id } }
    func rep(_ id: UUID?) -> Rep? { data.reps.first { $0.id == id } }
    func event(_ id: UUID?) -> MedEvent? { data.events.first { $0.id == id } }
    func invite(_ id: UUID?) -> Invite? { data.invites.first { $0.id == id } }

    func invites(forEvent id: UUID) -> [Invite] { data.invites.filter { $0.eventID == id } }
    func invites(forDoctor id: UUID) -> [Invite] { data.invites.filter { $0.doctorID == id } }
    func invite(event: UUID, doctor: UUID) -> Invite? {
        data.invites.first { $0.eventID == event && $0.doctorID == doctor }
    }

    func reps(forDoctor d: Doctor) -> [Rep] {
        guard let h = hospital(d.hospitalID) else { return [] }
        return h.repIDs.compactMap { rep($0) }
    }

    func doctors(inHospital id: UUID) -> [Doctor] {
        data.doctors.filter { $0.hospitalID == id }.sorted { $0.name < $1.name }
    }

    var sortedDoctors: [Doctor] { data.doctors.sorted { $0.name.lowercased() < $1.name.lowercased() } }
    var sortedHospitals: [Hospital] { data.hospitals.sorted { $0.name.lowercased() < $1.name.lowercased() } }

    // MARK: Updates

    func upsert(_ d: Doctor) {
        if let i = data.doctors.firstIndex(where: { $0.id == d.id }) { data.doctors[i] = d } else { data.doctors.append(d) }
    }
    func upsert(_ h: Hospital) {
        if let i = data.hospitals.firstIndex(where: { $0.id == h.id }) { data.hospitals[i] = h } else { data.hospitals.append(h) }
    }
    func upsert(_ e: MedEvent) {
        if let i = data.events.firstIndex(where: { $0.id == e.id }) { data.events[i] = e } else { data.events.append(e) }
    }
    func upsert(_ r: Rep) {
        if let i = data.reps.firstIndex(where: { $0.id == r.id }) { data.reps[i] = r } else { data.reps.append(r) }
    }
    func upsert(_ inv: Invite) {
        if let i = data.invites.firstIndex(where: { $0.id == inv.id }) { data.invites[i] = inv } else { data.invites.append(inv) }
    }
    func upsert(_ o: Occasion) {
        if let i = data.occasions.firstIndex(where: { $0.id == o.id }) { data.occasions[i] = o } else { data.occasions.append(o) }
    }

    func deleteDoctor(_ id: UUID) {
        data.doctors.removeAll { $0.id == id }
        data.invites.removeAll { $0.doctorID == id }
    }
    func deleteEvent(_ id: UUID) {
        data.events.removeAll { $0.id == id }
        data.invites.removeAll { $0.eventID == id }
    }
    func deleteHospital(_ id: UUID) {
        data.hospitals.removeAll { $0.id == id }
        for i in data.doctors.indices where data.doctors[i].hospitalID == id { data.doctors[i].hospitalID = nil }
    }
    func deleteInvite(_ id: UUID) { data.invites.removeAll { $0.id == id } }

    /// Invites a doctor, plus anyone he said he's bringing.
    func inviteDoctor(_ doctorID: UUID, to eventID: UUID) {
        guard invite(event: eventID, doctor: doctorID) == nil else { return }
        data.invites.append(Invite(eventID: eventID, doctorID: doctorID))
        if let d = doctor(doctorID) {
            for b in d.bringingIDs where invite(event: eventID, doctor: b) == nil {
                data.invites.append(Invite(eventID: eventID, doctorID: b))
            }
        }
    }

    func markSent(_ inviteID: UUID, _ kind: MessageKind) {
        guard var inv = invite(inviteID) else { return }
        inv.sent.append(SentMessage(kind: kind, date: Date()))
        upsert(inv)
    }
    func skip(_ inviteID: UUID, _ kind: MessageKind) {
        guard var inv = invite(inviteID) else { return }
        inv.skipped.append(kind)
        upsert(inv)
    }

    func logVisit(_ doctorID: UUID) {
        guard var d = doctor(doctorID) else { return }
        d.visits.append(Date())
        upsert(d)
    }

    func visitsThisMonth(_ d: Doctor) -> Int {
        let cal = Calendar.current
        return d.visits.filter { cal.isDate($0, equalTo: Date(), toGranularity: .month) }.count
    }

    /// A doctor who has never attended any event before this one.
    func isFirstTimer(_ doctorID: UUID, before event: MedEvent? = nil) -> Bool {
        !data.invites.contains { inv in
            guard inv.doctorID == doctorID, inv.attended == true, let e = self.event(inv.eventID) else { return false }
            if let event = event { return e.date < event.date && e.id != event.id }
            return true
        }
    }

    // MARK: Reminder schedule

    func dueMessages(now: Date = Date()) -> [DueMessage] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var out: [DueMessage] = []

        for inv in data.invites {
            guard let e = event(inv.eventID), doctor(inv.doctorID) != nil else { continue }
            let eventDay = cal.startOfDay(for: e.date)
            let invitedDay = cal.startOfDay(for: inv.invitedAt)
            let daysToEvent = cal.dateComponents([.day], from: today, to: eventDay).day ?? 0
            var kinds: [MessageKind] = []

            if daysToEvent >= 0 && inv.status != .no {
                // Pre-event messages
                if daysToEvent > 0 { kinds.append(.welcome) }
                if inv.status == .maybe, daysToEvent > 1,
                   let nudge = cal.date(byAdding: .day, value: 3, to: invitedDay), today >= nudge {
                    kinds.append(.maybeNudge)
                }
                if daysToEvent <= 7 && daysToEvent > 2 && (cal.dateComponents([.day], from: invitedDay, to: eventDay).day ?? 0) > 7 {
                    kinds.append(.weekBefore)
                }
                if daysToEvent <= 2 && daysToEvent > 0 { kinds.append(.twoDays) }
                if daysToEvent == 0 { kinds.append(.morning) }
                if inv.status == .maybe, daysToEvent > 0, let d = doctor(inv.doctorID),
                   d.comesIfIDs.contains(where: { invite(event: e.id, doctor: $0)?.status == .coming }) {
                    kinds.append(.goodNews)
                }
                // Don't pile the welcome message on top of later reminders.
                if kinds.contains(.welcome), !inv.done(.welcome), invitedDay < today {
                    if kinds.contains(.twoDays) || kinds.contains(.weekBefore) {
                        kinds.removeAll { $0 == .welcome }
                    }
                }
            }
            if daysToEvent <= 0 {
                if inv.attended == true { kinds.append(.thankYou) }
                if inv.attended == false && inv.status != .no { kinds.append(.missedYou) }
            }

            for k in kinds where !inv.done(k) {
                out.append(DueMessage(invite: inv, kind: k))
            }
        }
        return out.sorted {
            (event($0.invite.eventID)?.date ?? .distantFuture) < (event($1.invite.eventID)?.date ?? .distantFuture)
        }
    }

    // MARK: Suggestions

    func suggestions(now: Date = Date()) -> [Suggestion] {
        var out: [Suggestion] = []
        let cal = Calendar.current
        let upcoming = data.events.filter { $0.date >= cal.startOfDay(for: now) }.sorted { $0.date < $1.date }

        for e in upcoming {
            let invs = invites(forEvent: e.id)
            let coming = invs.filter { $0.status == .coming }.count
            if coming < e.target {
                let invited = Set(invs.map(\.doctorID))
                let available = data.doctors.filter { e.allows($0.specialty) && !invited.contains($0.id) }.count
                let short = e.target - coming
                var text = "\(e.name): \(short) short of your target of \(e.target)."
                if available > 0 { text += " \(available) matching doctor\(available == 1 ? "" : "s") not invited yet." }
                out.append(Suggestion(icon: "target", text: text))
            }

            // Maybes who haven't heard from you in 3+ days
            let quiet = invs.filter { inv in
                guard inv.status == .maybe else { return false }
                let last = inv.lastMessaged ?? inv.invitedAt
                return (cal.dateComponents([.day], from: last, to: now).day ?? 0) >= 3
            }
            if !quiet.isEmpty {
                let names = quiet.compactMap { doctor($0.doctorID)?.displayName }.prefix(3).joined(separator: ", ")
                out.append(Suggestion(icon: "questionmark.bubble",
                                      text: "\(quiet.count) maybe\(quiet.count == 1 ? "" : "s") quiet for 3+ days (\(names)). Message them or ask their mirror rep."))
            }

            // Dependency warnings
            for inv in invs where inv.status != .no {
                guard let d = doctor(inv.doctorID) else { continue }
                for depID in d.comesIfIDs {
                    if let dep = invite(event: e.id, doctor: depID), dep.status == .no, let depDoc = doctor(depID) {
                        out.append(Suggestion(icon: "exclamationmark.triangle",
                                              text: "\(d.displayName) comes only if \(depDoc.displayName) comes, and \(depDoc.displayName) said no. Message \(d.displayName) or find another reason."))
                    }
                }
            }

            // Same hospital, several coming
            var byHospital: [UUID: [String]] = [:]
            for inv in invs where inv.status == .coming {
                if let d = doctor(inv.doctorID), let h = d.hospitalID { byHospital[h, default: []].append(d.displayName) }
            }
            for (hid, names) in byHospital where names.count >= 2 {
                if let h = hospital(hid) {
                    out.append(Suggestion(icon: "person.2",
                                          text: "\(names.joined(separator: " and ")) from \(h.name) are coming to \(e.name). Suggest they come together."))
                }
            }
        }

        // Visits due this month
        let behind = data.doctors.filter { visitsThisMonth($0) < $0.visitsPerMonth }
        if !behind.isEmpty {
            out.append(Suggestion(icon: "figure.walk",
                                  text: "\(behind.count) doctor\(behind.count == 1 ? "" : "s") still need visits this month. Check the Doctors tab."))
        }
        return out
    }

    // MARK: Message texts

    static let longDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE d MMM, h:mm a"; return f
    }()
    static let shortDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f
    }()
    static let timeOnly: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    static let sheetDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"; return f
    }()

    func messageText(_ kind: MessageKind, invite inv: Invite) -> String {
        guard let d = doctor(inv.doctorID), let e = event(inv.eventID) else { return "" }
        let dr = d.displayName
        let me = "\(data.myName), \(data.company)"
        let when = Store.longDate.string(from: e.date)
        let venue = e.venue.isEmpty ? "" : "\nVenue: \(e.venue)"
        let cme = e.cmeHours.isEmpty ? "" : "\nCME: \(e.cmeHours) hours"
        let about = e.details.isEmpty ? "" : "\n\(e.details)"
        let bringing = d.bringingIDs.compactMap { doctor($0)?.displayName }
        let bringLine = bringing.isEmpty ? "" : "\nOf course \(bringing.joined(separator: " and ")) is very welcome too."

        switch kind {
        case .welcome:
            return "Hello \(dr), it's \(me). Thank you for your time today.\n\nHere are the details for \(e.name):\nDate: \(when)\(venue)\(cme)\(about)\n\nI'll keep a seat for you.\(bringLine)"
        case .maybeNudge:
            return "Hello \(dr), it's \(me). Just checking if you had a chance to look at your schedule for \(e.name) on \(Store.shortDate.string(from: e.date)). I'd be happy to keep a seat for you."
        case .weekBefore:
            return "Hello \(dr), a quick reminder that \(e.name) is next week.\nDate: \(when)\(venue)\(cme)\n\nLooking forward to seeing you there.\n\(me)"
        case .twoDays:
            return "Hello \(dr), \(e.name) is in two days.\nDate: \(when)\(venue)\n\nCan I count on you? Just reply yes and I'll confirm your seat.\n\(me)"
        case .morning:
            return "Good morning \(dr), see you today at \(Store.timeOnly.string(from: e.date)) for \(e.name)\(e.venue.isEmpty ? "" : " at \(e.venue)"). Have a safe drive!\n\(me)"
        case .thankYou:
            return "Thank you \(dr) for joining us at \(e.name). It was great to have you there. I'll pass by your clinic this week.\n\(me)"
        case .missedYou:
            return "Hello \(dr), we missed you at \(e.name). I hope everything is well. I'll share a quick summary when I visit you this week.\n\(me)"
        case .goodNews:
            let others = d.comesIfIDs.filter { invite(event: e.id, doctor: $0)?.status == .coming }
                .compactMap { doctor($0)?.displayName }.joined(separator: " and ")
            return "Hello \(dr), good news: \(others) confirmed coming to \(e.name) on \(Store.shortDate.string(from: e.date)). It would be great to have you both there.\n\(me)"
        }
    }

    func repHelpText(rep r: Rep, invite inv: Invite) -> String {
        guard let d = doctor(inv.doctorID), let e = event(inv.eventID) else { return "" }
        let h = hospital(d.hospitalID)?.name ?? "his hospital"
        var status = inv.status.rawValue
        if inv.status == .no, let reason = inv.noReason { status += " (\(reason.rawValue))" }
        let note = inv.note.isEmpty ? "" : "\nNote: \(inv.note)"
        return "Hi \(r.name), it's \(data.myName). I visited \(d.displayName) (\(d.specialty)) at \(h) about \(e.name) on \(Store.shortDate.string(from: e.date)).\nHis answer so far: \(status).\(note)\n\nYou know him better than me. Could you help me with him? Thank you!"
    }

    func occasionText(_ o: Occasion, doctor d: Doctor) -> String {
        o.message.replacingOccurrences(of: "{doctor}", with: d.displayName)
    }
}

enum WhatsApp {
    /// Turns a UAE-style number into international digits (05x... -> 9715x...).
    static func digits(_ phone: String) -> String {
        var s = phone.filter(\.isNumber)
        if s.hasPrefix("00") { s.removeFirst(2) }
        if s.hasPrefix("0") { s = "971" + String(s.dropFirst()) }
        if s.count == 9 && s.hasPrefix("5") { s = "971" + s }
        return s
    }

    static func url(phone: String, text: String) -> URL? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let num = digits(phone)
        if num.isEmpty {
            return URL(string: "https://wa.me/?text=\(encoded)")
        }
        return URL(string: "https://wa.me/\(num)?text=\(encoded)")
    }
}
