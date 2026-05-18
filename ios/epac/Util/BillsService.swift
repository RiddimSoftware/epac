//
//  BillsService.swift
//  epac
//
//  Created on 2026-04-27.
//
//  Fetches bills from the published S3 artifact generated from LEGISinfo.
//  Data traces entirely to parl.ca — an authoritative Parliament source.
//  No AI-generated content.
//

import Foundation

struct BillsService {

    // MARK: - Public

    /// Fetches all bills for the given Parliament and session.
    /// Defaults to Parliament 45, session 1 (current as of the app's inception date).
    static func fetchBills(
        parliament: Int = 45,
        session: Int = 1,
        artifacts: any ArtifactFetching = ArtifactService.shared
    ) async throws -> [Bill] {
        let payload = try await artifacts.fetch(.billsAll, as: BillsArtifact.self)
        return payload.bills
            .filter { $0.parliament == parliament && $0.session == session }
            .sorted { lhs, rhs in
                (lhs.introducedDate ?? .distantPast) > (rhs.introducedDate ?? .distantPast)
            }
    }
}
