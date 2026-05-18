//
//  ArtifactIngestActor.swift
//  epac
//

import Foundation
import SwiftData

private enum ArtifactDateParser {
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Toronto")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func date(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let date = dayFormatter.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }
}

struct IngestResult: Equatable, Sendable {
    let inserted: Int
    let updated: Int
    let deleted: Int
    let durationMs: Int

    static let zero = IngestResult(inserted: 0, updated: 0, deleted: 0, durationMs: 0)
}

struct MembersArtifact: Codable, Sendable {
    let members: [ParliamentMemberDTO]

    init(members: [ParliamentMemberDTO]) {
        self.members = members
    }

    enum CodingKeys: String, CodingKey {
        case members
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let records = try container.decode([MemberArtifactRecord].self, forKey: .members)
        members = records.map(\.member)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(members, forKey: .members)
    }
}

struct SittingsArtifact: Codable, Sendable {
    let calendars: [SittingCalendarRecord]

    init(calendars: [SittingCalendarRecord]) {
        self.calendars = calendars
    }

    enum CodingKeys: String, CodingKey {
        case calendars
        case sittings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let calendars = try container.decodeIfPresent([SittingCalendarRecord].self, forKey: .calendars) {
            self.calendars = calendars
            return
        }

        let sittings = try container.decode([SittingArtifactRecord].self, forKey: .sittings)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto") ?? .current
        let grouped = Dictionary(grouping: sittings.compactMap(\.date)) {
            calendar.component(.year, from: $0)
        }
        calendars = grouped
            .map { year, dates in SittingCalendarRecord(year: year, sittings: dates) }
            .sorted { $0.year < $1.year }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(calendars, forKey: .calendars)
    }
}

struct SittingCalendarRecord: Codable, Hashable, Sendable {
    let year: Int
    let sittings: [Date]
}

struct BillsArtifact: Codable, Sendable {
    let bills: [Bill]

    init(bills: [Bill]) {
        self.bills = bills
    }

    enum CodingKeys: String, CodingKey {
        case bills
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let records = try container.decode([BillArtifactRecord].self, forKey: .bills)
        bills = records.compactMap(\.bill)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bills, forKey: .bills)
    }
}

struct HansardSubjectsArtifact: Codable, Sendable {
    let hansards: [HansardDTO]
}

struct SittingSpeechesArtifact: Codable, Sendable {
    let dateString: String
    let date: Date
    let speeches: [SittingSpeechArtifactRecord]

    enum CodingKeys: String, CodingKey {
        case dateString = "date"
        case speeches
    }

    init(dateString: String, speeches: [SittingSpeechArtifactRecord]) throws {
        guard let date = ArtifactDateParser.date(from: dateString) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Sitting speeches artifact date must be YYYY-MM-DD"
            ))
        }
        self.dateString = dateString
        self.date = date
        self.speeches = speeches
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dateString = try container.decode(String.self, forKey: .dateString)
        guard let date = ArtifactDateParser.date(from: dateString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .dateString,
                in: container,
                debugDescription: "Sitting speeches artifact date must be YYYY-MM-DD"
            )
        }
        self.date = date
        speeches = try container.decodeIfPresent([SittingSpeechArtifactRecord].self, forKey: .speeches) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dateString, forKey: .dateString)
        try container.encode(speeches, forKey: .speeches)
    }
}

struct SittingSpeechArtifactRecord: Codable, Sendable {
    let id: String
    let speakerName: String?
    let memberID: String?
    let parliamentNum: Int?
    let sessionNum: Int?
    let subjectTitle: String?
    let content: String?
    let sourceURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case speakerName = "speaker_name"
        case memberID = "member_id"
        case parliamentNum = "parliament_num"
        case sessionNum = "session_num"
        case subjectTitle = "subject_title"
        case content
        case sourceURL = "source_url"
    }
}

enum ArtifactIngestError: Error, Equatable, Sendable {
    case unsupportedBillPersistence(recordCount: Int)
}

@ModelActor
actor ArtifactIngestActor {
    func ingestMembers(_ payload: MembersArtifact) async throws -> IngestResult {
        let startedAt = Date()
        var inserted = 0
        var updated = 0
        var deleted = 0

        do {
            let existingMembers = try modelContext.fetch(FetchDescriptor<ParliamentMember>())
            var membersByID: [Int: ParliamentMember] = [:]
            var membersByName: [String: ParliamentMember] = [:]
            for member in existingMembers {
                if member.memberID != 0 {
                    membersByID[member.memberID] = member
                }
                membersByName[member.name] = member
            }

            let incomingIDs = Set(payload.members.map(\.memberID).filter { $0 != 0 })
            for memberDTO in payload.members {
                let existing = membersByID[memberDTO.memberID] ?? membersByName[memberDTO.name]
                if let existing {
                    if update(existing, with: memberDTO) {
                        updated += 1
                    }
                } else {
                    modelContext.insert(ParliamentMember(domain: memberDTO))
                    inserted += 1
                }
            }

            for member in existingMembers where member.memberID != 0 && !incomingIDs.contains(member.memberID) {
                modelContext.delete(member)
                deleted += 1
            }

            try modelContext.save()
            return makeResult(startedAt: startedAt, inserted: inserted, updated: updated, deleted: deleted)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func ingestSittings(_ payload: SittingsArtifact) async throws -> IngestResult {
        let startedAt = Date()
        var inserted = 0
        var updated = 0
        var deleted = 0

        do {
            let existingCalendars = try modelContext.fetch(FetchDescriptor<SittingCalendar>())
            var calendarsByYear: [Int: SittingCalendar] = [:]
            for calendar in existingCalendars {
                calendarsByYear[calendar.year] = calendar
            }

            let incomingYears = Set(payload.calendars.map(\.year))
            for record in payload.calendars {
                let incomingSittings = normalizedSittings(record.sittings)
                if let existing = calendarsByYear[record.year] {
                    let existingSet = Set(normalizedSittings(existing.sittings))
                    let incomingSet = Set(incomingSittings)
                    guard existingSet != incomingSet else { continue }

                    inserted += incomingSet.subtracting(existingSet).count
                    deleted += existingSet.subtracting(incomingSet).count
                    updated += 1
                    existing.sittings = incomingSittings
                } else {
                    modelContext.insert(SittingCalendar(year: record.year, sittings: incomingSittings))
                    inserted += incomingSittings.count
                }
            }

            for calendar in existingCalendars where !incomingYears.contains(calendar.year) {
                deleted += Set(normalizedSittings(calendar.sittings)).count
                modelContext.delete(calendar)
            }

            try modelContext.save()
            return makeResult(startedAt: startedAt, inserted: inserted, updated: updated, deleted: deleted)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func ingestBills(_ payload: BillsArtifact) async throws -> IngestResult {
        let startedAt = Date()

        do {
            guard payload.bills.isEmpty else {
                throw ArtifactIngestError.unsupportedBillPersistence(recordCount: payload.bills.count)
            }
            try modelContext.save()
            return makeResult(startedAt: startedAt, inserted: 0, updated: 0, deleted: 0)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func ingestSittingSpeeches(_ payload: SittingSpeechesArtifact) async throws -> IngestResult {
        let startedAt = Date()
        let date = payload.date

        do {
            let existingMembers = try modelContext.fetch(FetchDescriptor<ParliamentMember>())
            var membersByID: [Int: ParliamentMember] = [:]
            var membersByName: [String: ParliamentMember] = [:]
            for member in existingMembers {
                if member.memberID != 0 {
                    membersByID[member.memberID] = member
                }
                membersByName[member.name] = member
            }
            guard let incoming = hansardDTO(from: payload, membersByID: membersByID, membersByName: membersByName) else {
                return .zero
            }

            let existing = try modelContext.fetch(FetchDescriptor<Hansard>(
                predicate: #Predicate { $0.date == date }
            ))
            if existing.count == 1, existing.first?.domainDTO == incoming {
                return .zero
            }

            for hansard in existing {
                deleteHansardAggregate(hansard)
            }
            modelContext.insert(Hansard(domain: incoming))
            try modelContext.save()

            let inserted = existing.isEmpty ? 1 : 0
            let updated = existing.isEmpty ? 0 : 1
            return makeResult(startedAt: startedAt, inserted: inserted, updated: updated, deleted: 0)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func ingestHansardSubjects(_ payload: HansardSubjectsArtifact) async throws -> IngestResult {
        let startedAt = Date()
        var inserted = 0
        var updated = 0
        var deleted = 0

        do {
            let existingHansards = try modelContext.fetch(FetchDescriptor<Hansard>())
            var hansardsByID: [String: Hansard] = [:]
            for hansard in existingHansards {
                hansardsByID[hansard.hansardID] = hansard
            }

            let incomingIDs = Set(payload.hansards.map(\.hansardID))
            for hansardDTO in payload.hansards {
                if let existing = hansardsByID[hansardDTO.hansardID] {
                    guard existing.domainDTO != hansardDTO else { continue }
                    deleteHansardAggregate(existing)
                    modelContext.insert(Hansard(domain: hansardDTO))
                    updated += 1
                } else {
                    modelContext.insert(Hansard(domain: hansardDTO))
                    inserted += 1
                }
            }

            for hansard in existingHansards where !incomingIDs.contains(hansard.hansardID) {
                deleteHansardAggregate(hansard)
                deleted += 1
            }

            try modelContext.save()
            return makeResult(startedAt: startedAt, inserted: inserted, updated: updated, deleted: deleted)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func update(_ member: ParliamentMember, with dto: ParliamentMemberDTO) -> Bool {
        var changed = false
        assign(&changed, member.name, dto.name) { member.name = dto.name }
        assign(&changed, member.memberID, dto.memberID) { member.memberID = dto.memberID }
        assign(&changed, member.lastName, dto.lastName) { member.lastName = dto.lastName }
        assign(&changed, member.firstName, dto.firstName) { member.firstName = dto.firstName }
        assign(&changed, member.photoURL, dto.photoURL) { member.photoURL = dto.photoURL }
        assign(&changed, member.riding, dto.riding) { member.riding = dto.riding }
        assign(&changed, member.province, dto.province) { member.province = dto.province }
        assign(&changed, member.party, dto.party) { member.party = dto.party }
        assign(&changed, member.websiteURL, dto.websiteURL) { member.websiteURL = dto.websiteURL }
        assign(&changed, member.fromDateTime, dto.fromDateTime) { member.fromDateTime = dto.fromDateTime }
        assign(&changed, member.toDateTime, dto.toDateTime) { member.toDateTime = dto.toDateTime }
        assign(&changed, member.imageData, dto.imageData) { member.imageData = dto.imageData }
        assign(&changed, member.email, dto.email) { member.email = dto.email }
        assign(&changed, member.hillPhone, dto.hillPhone) { member.hillPhone = dto.hillPhone }
        assign(&changed, member.constituencyPhone, dto.constituencyPhone) {
            member.constituencyPhone = dto.constituencyPhone
        }
        assign(&changed, member.constituencyAddress, dto.constituencyAddress) {
            member.constituencyAddress = dto.constituencyAddress
        }
        assign(&changed, member.contactFetched, dto.contactFetched) { member.contactFetched = dto.contactFetched }
        return changed
    }

    private func deleteHansardAggregate(_ hansard: Hansard) {
        for order in hansard.orders {
            for subject in order.subjects {
                for speech in subject.speeches {
                    for message in speech.messages {
                        modelContext.delete(message)
                    }
                    modelContext.delete(speech)
                }
                modelContext.delete(subject)
            }
            modelContext.delete(order)
        }
        modelContext.delete(hansard)
    }

    private func normalizedSittings(_ sittings: [Date]) -> [Date] {
        let calendar = Calendar(identifier: .gregorian)
        return Array(Set(sittings.map { calendar.startOfDay(for: $0) })).sorted()
    }

    private func hansardDTO(
        from payload: SittingSpeechesArtifact,
        membersByID: [Int: ParliamentMember],
        membersByName: [String: ParliamentMember]
    ) -> HansardDTO? {
        var subjects: [(title: String, speeches: [SittingSpeechArtifactRecord])] = []
        for speech in payload.speeches {
            let title = speech.subjectTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Debate"
            if let index = subjects.firstIndex(where: { $0.title == title }) {
                subjects[index].speeches.append(speech)
            } else {
                subjects.append((title: title, speeches: [speech]))
            }
        }

        var subjectDTOs: [SubjectOfBusinessDTO] = []
        for (title, records) in subjects {
            var speeches: [SpeechDTO] = []
            for record in records {
                if let speech = speechDTO(
                    from: record,
                    date: payload.date,
                    membersByID: membersByID,
                    membersByName: membersByName
                ) {
                    speeches.append(speech)
                }
            }
            guard !speeches.isEmpty else { continue }
            subjectDTOs.append(SubjectOfBusinessDTO(
                title: title,
                hansardID: "\(payload.dateString)-subject-\(Self.slug(title))",
                speeches: speeches,
                currentSpeechID: nil
            ))
        }
        guard !subjectDTOs.isEmpty else { return nil }

        return HansardDTO(
            date: payload.date,
            hansardID: "sitting-\(payload.dateString)",
            parliamentNumber: payload.speeches.compactMap(\.parliamentNum).first ?? 0,
            sessionNumber: payload.speeches.compactMap(\.sessionNum).first ?? 0,
            orders: [
                OrderOfBusinessDTO(
                    hansardID: "\(payload.dateString)-order-1",
                    catchline: "Debate",
                    subjects: subjectDTOs
                )
            ]
        )
    }

    private func speechDTO(
        from record: SittingSpeechArtifactRecord,
        date: Date,
        membersByID: [Int: ParliamentMember],
        membersByName: [String: ParliamentMember]
    ) -> SpeechDTO? {
        guard let content = record.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else { return nil }
        let speaker = speakerFields(for: record, membersByID: membersByID, membersByName: membersByName)
        let message = SpeechMessageDTO(
            firstName: speaker.firstName,
            lastName: speaker.lastName,
            partyAbbreviation: speaker.partyAbbreviation,
            ridingName: speaker.ridingName,
            hansardID: "\(record.id)-message-1",
            content: content,
            timestamp: date
        )
        return SpeechDTO(
            messages: [message],
            hansardID: record.id,
            currentMessageID: nil,
            date: date,
            length: 1,
            title: record.subjectTitle ?? "Debate"
        )
    }

    private func speakerFields(
        for record: SittingSpeechArtifactRecord,
        membersByID: [Int: ParliamentMember],
        membersByName: [String: ParliamentMember]
    ) -> (firstName: String, lastName: String, partyAbbreviation: String, ridingName: String) {
        let member = record.memberID.flatMap(Int.init).flatMap { membersByID[$0] }
            ?? record.speakerName.flatMap { membersByName[$0] }
        if let member {
            return (member.firstName, member.lastName, member.party.abbreviation, member.riding)
        }

        let parts = (record.speakerName ?? "Unknown Speaker").split(separator: " ").map(String.init)
        let firstName = parts.dropLast().joined(separator: " ")
        let lastName = parts.last ?? "Speaker"
        return (firstName.isEmpty ? "Unknown" : firstName, lastName, "", "")
    }

    private static func slug(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_CA"))
        let scalars = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        return String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
            .lowercased()
    }

    private func makeResult(startedAt: Date, inserted: Int, updated: Int, deleted: Int) -> IngestResult {
        IngestResult(
            inserted: inserted,
            updated: updated,
            deleted: deleted,
            durationMs: max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
        )
    }

    private func assign<Value: Equatable>(
        _ changed: inout Bool,
        _ current: Value,
        _ incoming: Value,
        set: () -> Void
    ) {
        guard current != incoming else { return }
        set()
        changed = true
    }
}

private struct MemberArtifactRecord: Decodable {
    let member: ParliamentMemberDTO

    init(from decoder: Decoder) throws {
        if let member = try? ParliamentMemberDTO(from: decoder) {
            self.member = member
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = Int(try container.decode(String.self, forKey: .id)) ?? 0
        let name = try container.decode(String.self, forKey: .name)
        let nameParts = Self.nameParts(name)
        let party = Party.partyWithAbbreviation(try container.decodeIfPresent(String.self, forKey: .party) ?? "")
        let province = Self.province(from: try container.decodeIfPresent(String.self, forKey: .province))
        let photoURL = PhotoProvider(parliamentNumber: 45).getPhotoURL(
            lastName: nameParts.lastName,
            firstName: nameParts.firstName,
            party: party
        )

        member = ParliamentMemberDTO(
            name: name,
            memberID: id,
            lastName: nameParts.lastName,
            firstName: nameParts.firstName,
            photoURL: photoURL,
            riding: try container.decodeIfPresent(String.self, forKey: .riding) ?? "",
            province: province,
            party: party,
            websiteURL: nil,
            imageData: nil,
            fromDateTime: nil,
            toDateTime: nil,
            email: nil,
            hillPhone: nil,
            constituencyPhone: nil,
            constituencyAddress: nil,
            contactFetched: false
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case riding
        case province
        case party
    }

    private static func nameParts(_ name: String) -> (firstName: String, lastName: String) {
        let parts = name.split(separator: " ").map(String.init)
        let firstName = parts.dropLast().joined(separator: " ")
        let lastName = parts.last ?? name
        return (firstName.isEmpty ? name : firstName, lastName)
    }

    private static func province(from rawValue: String?) -> Province {
        guard let rawValue else { return .Ontario }
        if let province = Province(rawValue: rawValue) {
            return province
        }
        return Province.allCases.first { $0.shortCode.caseInsensitiveCompare(rawValue) == .orderedSame } ?? .Ontario
    }
}

private struct SittingArtifactRecord: Decodable {
    let date: Date?

    enum CodingKeys: String, CodingKey {
        case date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = ArtifactDateParser.date(from: try container.decodeIfPresent(String.self, forKey: .date))
    }
}

private struct BillArtifactRecord: Decodable {
    let bill: Bill?

    enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case sponsorName = "sponsor_name"
        case status
        case currentStage = "current_stage"
        case introducedOn = "introduced_on"
        case stages
        case sourceURL = "source_url"
        case billType = "bill_type"
        case parliament
        case session
        case legisInfoURL = "legis_info_url"
    }

    init(from decoder: Decoder) throws {
        if let bill = try? Bill(from: decoder) {
            self.bill = bill
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let number = try container.decodeIfPresent(String.self, forKey: .number)
            ?? container.decode(String.self, forKey: .id)
        let urlString = try container.decodeIfPresent(String.self, forKey: .legisInfoURL)
            ?? container.decodeIfPresent(String.self, forKey: .sourceURL)
        guard let urlString,
              let url = URL(string: urlString) else {
            bill = nil
            return
        }

        bill = Bill(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? number,
            number: number,
            title: try container.decode(String.self, forKey: .title),
            sponsorName: try container.decodeIfPresent(String.self, forKey: .sponsorName) ?? "",
            status: BillStatus(rawValue: try container.decodeIfPresent(String.self, forKey: .status) ?? "") ?? .unknown,
            currentStage: try container.decodeIfPresent(String.self, forKey: .currentStage) ?? "",
            introducedDate: ArtifactDateParser.date(from: try container.decodeIfPresent(String.self, forKey: .introducedOn)),
            stages: (try container.decodeIfPresent([BillStageArtifactRecord].self, forKey: .stages) ?? []).map(\.stage),
            legisInfoURL: url,
            billType: BillType(rawValue: try container.decodeIfPresent(String.self, forKey: .billType) ?? "") ?? .unknown,
            parliament: try container.decodeIfPresent(Int.self, forKey: .parliament) ?? 0,
            session: try container.decodeIfPresent(Int.self, forKey: .session) ?? 0
        )
    }
}

private struct BillStageArtifactRecord: Decodable {
    let stage: BillStage

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case completedDate = "completed_date"
        case isCompleted = "is_completed"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stage = BillStage(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
            completedDate: ArtifactDateParser.date(from: try container.decodeIfPresent(String.self, forKey: .completedDate)),
            isCompleted: try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        )
    }
}
