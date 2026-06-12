@testable import epac
import Foundation
import Testing

struct NewSchemaTests {
    @Test func parseNewHospitalitySchema() async throws {
        let csvContent = """
"Members – Detailed Hospitality Expenditures Report – Acan, Sima – Q2 2026"
Date,Location,Total of Attendees,Purpose of Hospitality,Supplier,Amount,Total
2025-06-22,Burlington,2,To host a business meeting,COSTCO WHOLESALE,69.63,69.63
2025-07-02,Oakville Office,6,To meet visitors to the Member's office,FreshCo,13.72,13.72
"""
        let parser = CSVParser(content: csvContent)
        let stream = HospitalityExpenditure.fromCSV(parser)
        let results = await stream.collect()

        #expect(results.count == 2)
        #expect(results[0].supplier == "COSTCO WHOLESALE")
        #expect(results[0].total == 69.63)
        #expect(results[1].supplier == "FreshCo")
        #expect(results[1].total == 13.72)
    }

    @Test func parseNewTravelSchema() async throws {
        let csvContent = """
"Members – Detailed Travel Expenditures Report – Acan, Sima – Q2 2026"
Travel start date,Travel end date,Departure,Places Visited,Purpose of Travel,Traveller Name,Traveller Type,Transportation,Accommodations,Meals and Incidentals,Total
2025-05-21,2025-05-30,Oakville,Ottawa,Parliamentary session or related activities in Ottawa,"Acan, Sima",Member,470.75,0,0,470.75
2025-09-07,2025-09-12,Oakville,"Toronto, Edmonton",Attend a national caucus meeting,"Acan, Sima",Member,3298.89,1013.66,692.52,5005.07
"""
        let parser = CSVParser(content: csvContent)
        let stream = TravelClaim.fromCSV(parser)
        let results = await stream.collect()

        #expect(results.count == 2)
        #expect(results[0].transportation == 470.75)
        #expect(results[1].total == 5005.07)
        #expect(results[1].details.count == 1)
        #expect(results[1].details[0].destination == "Toronto, Edmonton")
    }
}
