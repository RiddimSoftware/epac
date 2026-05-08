import Foundation
import SwiftData

@MainActor
struct SwiftDataHansardSearchStore: HansardSearchStore {
    let modelContext: ModelContext

    func loadDocuments() throws -> [HansardSearchDocument] {
        let descriptor = FetchDescriptor<Hansard>(sortBy: [SortDescriptor(\Hansard.date, order: .reverse)])
        let hansards = try modelContext.fetch(descriptor)

        return hansards.flatMap { hansard in
            hansard.orders.flatMap { order in
                order.subjects.compactMap { subject in
                    guard !subject.speeches.isEmpty else { return nil }
                    return HansardSearchDocument(
                        subjectID: subject.hansardID,
                        subjectTitle: subject.title,
                        hansardDate: hansard.date
                    )
                }
            }
        }
    }
}
