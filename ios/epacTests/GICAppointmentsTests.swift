@testable import epac
import Foundation
import Testing

struct GICAppointmentsTests {
	@Test func decodesSnapshot() throws {
		let json = """
		{
		  "generated_at": "2026-04-28T23:58:00Z",
		  "retrieved_at": "2026-04-28",
		  "source": {
		    "title": "Federal Organizations — Governor in Council appointees",
		    "url": "https://federal-organizations.canada.ca/",
		    "appointments_index_url": "https://federal-organizations.canada.ca/gindex.php?t=3&GicGuideFlg=1&lang=en",
		    "orders_in_council_url": "https://orders-in-council.canada.ca/",
		    "salary_ranges_url": "https://www.canada.ca/en/privy-council/programs/appointments/governor-council-appointments/compensation-terms-conditions-employment/salary-ranges-performance-pay.html"
		  },
		  "coverage": {
		    "profiles_scraped": 201,
		    "current_or_recent_records_found": 1133,
		    "records_bundled": 1,
		    "note": "Sample"
		  },
		  "appointments": [
		    {
		      "id": "sample",
		      "name": "Bouchard, Marie-Philippe",
		      "organization": "Canadian Broadcasting Corporation",
		      "organization_id": "CBC",
		      "organization_category": "Crown Corporation",
		      "responsible_minister": "Minister of Canadian Identity and Culture",
		      "position": "President",
		      "classification_level": "CEO 7",
		      "appointment_type": "Full-Time Appointment",
		      "tenure": "During Good Behaviour",
		      "current_appointment_date": "2025-01-03",
		      "expiry_date": "2030-01-02",
		      "profile_url": "https://federal-organizations.canada.ca/profil.php?OrgID=CBC&lang=en#PersonID_sample",
		      "compensation": {
		        "kind": "salary_range",
		        "source_year": "2025-26",
		        "label": "CEO 7 salary range",
		        "minimum": "$478,300",
		        "maximum": "$562,700",
		        "maximum_performance_award": "28.00%"
		      },
		      "order_in_council": {
		        "pc_number": "2024-1342",
		        "date_made": "2024-12-13",
		        "department": "PCH",
		        "act": "Broadcasting Act",
		        "subject": "Appointment of the President of the Canadian Broadcasting Corporation",
		        "precis": "Appointment of Marie-Philippe Bouchard as President.",
		        "registration": "N/A",
		        "attachment_url": "https://orders-in-council.canada.ca/attachment.php?attach=46917&lang=en"
		      }
		    }
		  ]
		}
		"""

		let snapshot = try GICAppointmentsDatabase.decode(data: Data(json.utf8))
		let appointment = try #require(snapshot.appointments.first)

		#expect(snapshot.coverage.profilesScraped == 201)
		#expect(appointment.displayName == "Marie-Philippe Bouchard")
		#expect(appointment.compensation?.displayValue == "$478,300-$562,700")
		#expect(appointment.orderInCouncil?.pcNumber == "2024-1342")
		#expect(appointment.isCurrent(referenceDate: try #require(GICAppointmentsDatabase.dateFormatter.date(from: "2026-04-28"))))
	}

	@Test func bundledSnapshotHasRecentFirstLoadAndCrownCorporationExamples() throws {
		let snapshot = try #require(GICAppointmentsDatabase.snapshot())
		let appointments = snapshot.appointments

		#expect(snapshot.source.title == "Federal Organizations — Governor in Council appointees")
		#expect(appointments.count >= 20)
		#expect(appointments.prefix(20).allSatisfy { !$0.name.isEmpty && !$0.position.isEmpty })
		#expect(appointments.contains { $0.organization == "Canadian Broadcasting Corporation" })
		#expect(appointments.contains { $0.organization == "Canada Post Corporation" })
		#expect(appointments.contains { $0.orderInCouncil != nil })
		#expect(appointments.contains { $0.compensation != nil })
	}

	@Test func filtersBySearchOrganizationAndStatus() throws {
		let referenceDate = try #require(GICAppointmentsDatabase.dateFormatter.date(from: "2026-04-28"))
		let cbc = GICAppointmentsDatabase.filteredAppointments(
			searchText: "CBC",
			organization: "Canadian Broadcasting Corporation",
			status: .all,
			referenceDate: referenceDate
		)
		let canadaPost = GICAppointmentsDatabase.filteredAppointments(
			searchText: "Canada Post",
			organization: nil,
			status: .all,
			referenceDate: referenceDate
		)
		let current = GICAppointmentsDatabase.filteredAppointments(
			searchText: "",
			organization: nil,
			status: .current,
			referenceDate: referenceDate
		)

		#expect(cbc.contains { $0.organization == "Canadian Broadcasting Corporation" })
		#expect(canadaPost.contains { $0.organization == "Canada Post Corporation" })
		#expect(current.count >= 20)
		#expect(current.allSatisfy { $0.isCurrent(referenceDate: referenceDate) })
	}
}
