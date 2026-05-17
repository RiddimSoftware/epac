//
//  ArtifactIngestActor.swift
//  epac
//

import Foundation
import SwiftData

struct IngestResult: Equatable, Sendable {
    let inserted: Int
    let updated: Int
    let deleted: Int
    let durationMs: Int

    static let zero = IngestResult(inserted: 0, updated: 0, deleted: 0, durationMs: 0)
}

struct MembersArtifact: Codable, Sendable {
    let members: [ParliamentMemberDTO]
}

struct SittingsArtifact: Codable, Sendable {
    let calendars: [SittingCalendarRecord]
}

struct SittingCalendarRecord: Codable, Hashable, Sendable {
    let year: Int
    let sittings: [Date]
}

struct BillsArtifact: Codable, Sendable {
    let bills: [Bill]
}

struct HansardSubjectsArtifact: Codable, Sendable {
    let hansards: [HansardDTO]
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
