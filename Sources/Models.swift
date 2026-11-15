import Foundation

enum Specialty {
    static let all = [
        "Cardiology", "Endocrinology", "Nephrology", "Family Medicine",
        "Internal Medicine", "General Practice", "Other"
    ]
}

struct Rep: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var phone: String = ""
}

struct Hospital: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var area: String = ""
    var repIDs: [UUID] = []
}

struct Doctor: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var specialty: String = "Cardiology"
    var hospitalID: UUID?
    var phone: String = ""
    var linkedIn: String = ""
    var notes: String = ""
    var visitsPerMonth: Int = 2
    var visits: [Date] = []
    var bringingIDs: [UUID] = []
    var comesIfIDs: [UUID] = []

    var displayName: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.lowercased().hasPrefix("dr") { return n }
        return "Dr. " + n
    }
}

struct MedEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var date: Date
    var venue: String = ""
    var details: String = ""
    var cmeHours: String = ""
    /// Empty means open to every specialty.
    var specialties: [String] = []
    var target: Int = 5

    func allows(_ specialty: String) -> Bool {
        specialties.isEmpty || specialties.contains(specialty)
    }
}

enum InviteStatus: String, Codable, CaseIterable, Identifiable {
    case maybe = "Maybe"
    case coming = "Coming"
    case no = "No"
    var id: String { rawValue }
}

enum NoReason: String, Codable, CaseIterable, Identifiable {
    case busy = "Working that day"
    case notInterested = "Free but not interested"
    case never = "Will never come"
    case other = "Other"
    var id: String { rawValue }
}

enum MessageKind: String, Codable, CaseIterable, Identifiable {
    case welcome, maybeNudge, weekBefore, twoDays, morning, thankYou, missedYou, goodNews
    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: return "After-visit details"
        case .maybeNudge: return "Follow up on maybe"
        case .weekBefore: return "1 week reminder"
        case .twoDays: return "2 days - ask to confirm"
        case .morning: return "Morning of the event"
        case .thankYou: return "Thank you"
        case .missedYou: return "We missed you"
        case .goodNews: return "Good news - colleague coming"
        }
    }
}

struct SentMessage: Codable, Hashable {
    var kind: MessageKind
    var date: Date
}

struct Invite: Identifiable, Codable, Hashable {
    var id = UUID()
    var eventID: UUID
    var doctorID: UUID
    var status: InviteStatus = .maybe
    var noReason: NoReason?
    var reasonNote: String = ""
    var note: String = ""
    var invitedAt: Date = Date()
    var sent: [SentMessage] = []
    var skipped: [MessageKind] = []
    var askedRepID: UUID?
    var helperRepID: UUID?
    /// nil = not marked yet, true = came, false = didn't come
    var attended: Bool?

    var lastMessaged: Date? { sent.map(\.date).max() }
    func done(_ kind: MessageKind) -> Bool {
        sent.contains { $0.kind == kind } || skipped.contains(kind)
    }
}

struct Occasion: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var date: Date
    var message: String
    var greetedIDs: [UUID] = []
    var estimated: Bool = false
}

struct AppData: Codable {
    var myName: String = "Ahmad"
    var company: String = "Boehringer Ingelheim"
    var reps: [Rep] = []
    var hospitals: [Hospital] = []
    var doctors: [Doctor] = []
    var events: [MedEvent] = []
    var invites: [Invite] = []
    var occasions: [Occasion] = []

    static func starter() -> AppData {
        var d = AppData()
        d.reps = ["Anas", "Lillian", "Abdulrahman", "Abram", "Amir", "Hind"].map { Rep(name: $0) }
        func day(_ y: Int, _ m: Int, _ dd: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: y, month: m, day: dd, hour: 9)) ?? Date()
        }
        let sign = "\n\nAhmad, Boehringer Ingelheim"
        d.occasions = [
            Occasion(name: "UAE National Day", date: day(2026, 12, 2),
                     message: "Happy UAE National Day, {doctor}! Wishing you and your family a wonderful celebration." + sign),
            Occasion(name: "New Year", date: day(2027, 1, 1),
                     message: "Happy New Year, {doctor}! Wishing you a healthy and successful year ahead." + sign),
            Occasion(name: "Ramadan", date: day(2027, 2, 8),
                     message: "Ramadan Kareem, {doctor}! Wishing you and your family a blessed month." + sign,
                     estimated: true),
            Occasion(name: "Eid al-Fitr", date: day(2027, 3, 10),
                     message: "Eid Mubarak, {doctor}! Wishing you and your family a joyful Eid." + sign,
                     estimated: true),
            Occasion(name: "Eid al-Adha", date: day(2027, 5, 16),
                     message: "Eid al-Adha Mubarak, {doctor}! Wishing you and your loved ones a blessed Eid." + sign,
                     estimated: true),
            Occasion(name: "Islamic New Year", date: day(2027, 6, 6),
                     message: "Happy Hijri New Year, {doctor}! Wishing you a blessed year ahead." + sign,
                     estimated: true)
        ]
        return d
    }
}
