//
//  RefreshLiveParliamentStatus.swift
//  epac
//

import Foundation

@MainActor
struct RefreshLiveParliamentStatus {
    private let liveParliamentStatusFetching: LiveParliamentStatusFetching
    private let repository: HomeFeedRepository
    
    init(
        liveParliamentStatusFetching: LiveParliamentStatusFetching,
        repository: HomeFeedRepository
    ) {
        self.liveParliamentStatusFetching = liveParliamentStatusFetching
        self.repository = repository
    }
    
    struct Result {
        let liveParliamentStatus: LiveParliamentStatus
        let postSittingHansard: Hansard?
        let parliamentDayStatus: HomeParliamentDayStatus?
    }
    
    func execute() async throws -> Result {
        let status = try await liveParliamentStatusFetching.fetchStatus()
        var postSittingHansard: Hansard? = nil
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
        return Result(
            liveParliamentStatus: status,
            postSittingHansard: postSittingHansard,
            parliamentDayStatus: status.isSitting ? .sitting : nil
        )
    }
}
