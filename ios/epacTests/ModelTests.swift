@testable import epac
import Foundation
import Testing
import UIKit

struct ModelTests {
    @Test func partyAbbreviationMatching() {
        #expect(Party.partyWithAbbreviation("Lib") == .liberal)
        #expect(Party.partyWithAbbreviation("LIBERAL") == .liberal)
        #expect(Party.partyWithAbbreviation("CPC") == .conservative)
        #expect(Party.partyWithAbbreviation("Conservative") == .conservative)
        #expect(Party.partyWithAbbreviation("SK") == .saskatchewanParty)
        #expect(Party.partyWithAbbreviation("SK Party") == .saskatchewanParty)
        #expect(Party.partyWithAbbreviation("Saskatchewan Party") == .saskatchewanParty)
        #expect(Party.partyWithAbbreviation("NDP") == .newdemocratic)
        #expect(Party.partyWithAbbreviation("New Democratic Party") == .newdemocratic)
        #expect(Party.partyWithAbbreviation("BQ") == .bloc)
        #expect(Party.partyWithAbbreviation("Bloc Québécois") == .bloc)
        #expect(Party.partyWithAbbreviation("GP") == .green)
        #expect(Party.partyWithAbbreviation("Green Party") == .green)
        #expect(Party.partyWithAbbreviation("Ind") == .independent)
        #expect(Party.partyWithAbbreviation("Unknown") == .independent)
    }

    @Test func provinceMatching() {
        // Test accented characters matching in XMLBro.parseMembers context
        // This is indirectly tested by XMLBroTests.testParsingAcrossParliaments
        // but adding explicit checks here for the enum raw values.
        #expect(Province(rawValue: "Ontario") == .Ontario)
        #expect(Province(rawValue: "British Columbia") == .BC)
        #expect(Province(rawValue: "Quebec") == .Quebec)
        #expect(Province(rawValue: "Saskatchewan") == .Saskatchewan)
    }

    @Test func senateTopicAvailableForAppointmentNotifications() {
        let senate = ParliamentaryTopic.all.first { $0.id == "senate" }

        #expect(senate?.nameKey == "topic.senate")
        #expect(senate?.keywords.contains("senator") == true)
        #expect(ParliamentaryTopic.matching("The PM has appointed a new senator").map(\.id).contains("senate"))
    }

    @Test func senatorOpenAPIParserIncludesAppointmentFacts() throws {
        let payload = """
        {
          "items": [
            {
              "PersonOfficialFirstName": "Jane",
              "PersonOfficialLastName": "Senator",
              "ProvinceName": "Ontario",
              "CaucusAbbreviationEn": "ISG",
              "CaucusNameEn": "Independent Senators Group",
              "PersonPageUrl": "https://sencanada.ca/en/senators/jane-senator",
              "appointment": {
                "appointment_date": "2024-12-19",
                "appointing_prime_minister": "Justin Trudeau",
                "declared_affiliation": "Independent Senators Group",
                "orders_in_council_url": "https://pco-bcp.gc.ca/oic-ddc.asp?lang=eng&Page=secretariats&txtOICID=2024-1300"
              }
            }
          ]
        }
        """.data(using: .utf8)
        let data = try #require(payload)

        let senator = try #require(SenatorsService.parseOpenAPISenators(from: data)?.first)
        let appointment = try #require(senator.appointment)

        #expect(senator.province == "ON")
        #expect(appointment.appointingPrimeMinister == "Justin Trudeau")
        #expect(appointment.declaredAffiliation == "Independent Senators Group")
        #expect(appointment.province == "ON")
        #expect(appointment.sourceURL.absoluteString.contains("pco-bcp.gc.ca/oic-ddc.asp"))
        #expect(senator.appointmentDate == appointment.date)
    }
}
