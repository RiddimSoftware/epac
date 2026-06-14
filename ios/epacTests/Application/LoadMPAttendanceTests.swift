//
//  LoadMPAttendanceTests.swift
//  epacTests
//
//  Tests for LoadMPAttendance use case (EPAC-897).
//

@testable import epac
import Foundation
import Testing

@MainActor
struct LoadMPAttendanceTests {
    @Test func returnsNilWhenTallyIsEmptyOrZeroDivisions() async throws {
        let port = MPAttendanceQueryPortSpy()
        let useCase = LoadMPAttendance(port: port)

        let result = try await useCase.execute(memberID: 1)
        #expect(result == nil)
    }

    @Test func computesCorrectAttendanceRates() async throws {
        let port = MPAttendanceQueryPortSpy()
        let swornInDate = Date()
        port.tallies = [
            MemberDivisionTally(
                memberID: 1,
                party: .liberal,
                yea: 10,
                nay: 5,
                paired: 3,
                totalDivisions: 20,
                denominatorStartDate: swornInDate
            )
        ]
        let useCase = LoadMPAttendance(port: port)

        let result = try await useCase.execute(memberID: 1)
        #expect(result != nil)
        let record = result!.record
        #expect(record.totalDivisions == 20)
        #expect(record.yea == 10)
        #expect(record.nay == 5)
        #expect(record.paired == 3)
        #expect(record.present == 15)
        #expect(record.absent == 2) // 20 - 15 - 3
        #expect(record.attendanceRate == 15.0 / 20.0)
        #expect(record.denominatorStartDate == swornInDate)
    }

    @Test func computesComparisonCorrectly() async throws {
        let port = MPAttendanceQueryPortSpy()
        let target = MemberDivisionTally(memberID: 1, party: .liberal, yea: 8, nay: 2, paired: 0, totalDivisions: 10, denominatorStartDate: nil)
        let peer1 = MemberDivisionTally(memberID: 2, party: .liberal, yea: 9, nay: 0, paired: 1, totalDivisions: 10, denominatorStartDate: nil) // rate: 0.9
        let peer2 = MemberDivisionTally(memberID: 3, party: .conservative, yea: 5, nay: 0, paired: 0, totalDivisions: 10, denominatorStartDate: nil) // rate: 0.5
        let peerTooFew = MemberDivisionTally(memberID: 4, party: .liberal, yea: 3, nay: 0, paired: 0, totalDivisions: 3, denominatorStartDate: nil) // excluded (< 5 divisions)

        port.tallies = [target, peer1, peer2, peerTooFew]
        let useCase = LoadMPAttendance(port: port)

        let result = try await useCase.execute(memberID: 1)
        #expect(result != nil)
        let comparison = result!.comparison
        #expect(comparison != nil)
        #expect(comparison!.party == .liberal)
        #expect(comparison!.nationalSampleSize == 2) // peer1 and peer2
        #expect(comparison!.partySampleSize == 1) // peer1
        #expect(comparison!.nationalAverageRate == 0.7) // (0.9 + 0.5) / 2
        #expect(comparison!.partyAverageRate == 0.9) // peer1
    }
}

@MainActor
private final class MPAttendanceQueryPortSpy: MPAttendanceQueryPort {
    var tallies: [MemberDivisionTally] = []

    func tally(forMemberID memberID: Int) async throws -> MemberDivisionTally? {
        tallies.first { $0.memberID == memberID }
    }

    func allTallies() async throws -> [MemberDivisionTally] {
        tallies
    }
}
