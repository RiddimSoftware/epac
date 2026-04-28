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
}
