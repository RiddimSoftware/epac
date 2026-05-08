//
//  RefreshLiveParliamentStatus.swift
//  epac
//

import Foundation

@MainActor
struct RefreshLiveParliamentStatus {
    private let liveParliamentStatusFetching: LiveParliamentStatusFetching
    private let repository: HomeFeedRepository
    private let clock: Clock

    init(
        liveParliamentStatusFetching: LiveParliamentStatusFetching,
        repository: HomeFeedRepository,
        clock: Clock = SystemClock()
    ) {
        self.liveParliamentStatusFetching = liveParliamentStatusFetching
        self.repository = repository
        self.clock = clock
    }

    struct Result {
        let liveParliamentStatus: LiveParliamentStatus
        let liveCardDecision: HomeLiveCardDecision
        let parliamentDayStatus: HomeParliamentDayStatus?
    }

    func execute() async throws -> Result {
        let status = try await liveParliamentStatusFetching.fetchStatus()
        let ottawaTodayString = makeOttawaTodayString(from: clock.now)
        var postSittingHansard: HomeHansardRecord?
        if !status.isSitting, let sittingDate = status.sittingDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "America/Toronto")
            if let date = formatter.date(from: sittingDate) {
                let start = Calendar.current.startOfDay(for: date)
                if let end = Calendar.current.date(byAdding: .day, value: 1, to: start) {
                    let matchingHansards = try? await repository.fetchHansards(between: start, and: end)
                    postSittingHansard = matchingHansards?.first
                }
            }
        }
        let liveCardDecision = computeLiveCardDecision(
            status: status,
            postSittingHansard: postSittingHansard,
            ottawaTodayString: ottawaTodayString
        )
        return Result(
            liveParliamentStatus: status,
            liveCardDecision: liveCardDecision,
            parliamentDayStatus: status.isSitting ? .sitting : nil
        )
    }

    private func makeOttawaTodayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/Toronto")
        return formatter.string(from: date)
    }

    private func computeLiveCardDecision(
        status: LiveParliamentStatus,
        postSittingHansard: HomeHansardRecord?,
        ottawaTodayString: String
    ) -> HomeLiveCardDecision {
        if status.isSitting { return .live(status) }
        guard let sittingDate = status.sittingDate, sittingDate == ottawaTodayString else {
            return .hidden
        }
        if let hansard = postSittingHansard {
            let subjectTitle = hansard.subjectRecords.first?.title ?? ""
            return .todayPublished(hansardID: hansard.hansardID, date: hansard.date, subjectTitle: subjectTitle)
        }
        return .todayPending
    }
}
