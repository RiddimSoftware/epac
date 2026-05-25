@testable import epac
import Testing

struct HansardSpeakerParserTests {
	@Test func parsesStandardEnglishHonourable() {
		let result = HansardSpeakerParser.parse("Hon. Mark Carney (Nepean, Lib.)")

		#expect(result.firstName == "Mark")
		#expect(result.lastName == "Carney")
		#expect(result.partyAbbreviation == "Lib")
		#expect(result.ridingName == "Nepean")
	}

	@Test func parsesMrPrefix() {
		let result = HansardSpeakerParser.parse("Mr. Pierre Poilievre (Carleton, CPC)")

		#expect(result.firstName == "Pierre")
		#expect(result.lastName == "Poilievre")
		#expect(result.partyAbbreviation == "CPC")
		#expect(result.ridingName == "Carleton")
	}

	@Test func parsesMsPrefix() {
		let result = HansardSpeakerParser.parse("Ms. Jenny Kwan (Vancouver East, NDP)")

		#expect(result.firstName == "Jenny")
		#expect(result.lastName == "Kwan")
		#expect(result.partyAbbreviation == "NDP")
		#expect(result.ridingName == "Vancouver East")
	}

	@Test func parsesFrenchHonourableWithApostrophe() {
		let result = HansardSpeakerParser.parse("L'hon. Marc Garneau (Notre-Dame-de-Grâce—Westmount, Lib.)")

		#expect(result.firstName == "Marc")
		#expect(result.lastName == "Garneau")
		#expect(result.partyAbbreviation == "Lib")
		#expect(result.ridingName == "Notre-Dame-de-Grâce\u{2014}Westmount")
	}

	@Test func parsesFrenchHonourableWithSmartApostrophe() {
		let result = HansardSpeakerParser.parse("L\u{2019}hon. Marc Garneau (Notre-Dame-de-Grâce—Westmount, Lib.)")

		#expect(result.firstName == "Marc")
		#expect(result.lastName == "Garneau")
		#expect(result.partyAbbreviation == "Lib")
	}

	@Test func parsesFrenchMonsieurPrefix() {
		let result = HansardSpeakerParser.parse("M. Yves-François Blanchet (Beloeil—Chambly, BQ)")

		#expect(result.firstName == "Yves-François")
		#expect(result.lastName == "Blanchet")
		#expect(result.partyAbbreviation == "BQ")
		#expect(result.ridingName == "Beloeil\u{2014}Chambly")
	}

	@Test func parsesFrenchMadamePrefix() {
		let result = HansardSpeakerParser.parse("Mme Claude DeBellefeuille (Salaberry—Suroît, BQ)")

		#expect(result.firstName == "Claude")
		#expect(result.lastName == "DeBellefeuille")
		#expect(result.partyAbbreviation == "BQ")
	}

	@Test func parsesDrPrefix() {
		let result = HansardSpeakerParser.parse("Dr. Hedy Fry (Vancouver Centre, Lib.)")

		#expect(result.firstName == "Hedy")
		#expect(result.lastName == "Fry")
		#expect(result.partyAbbreviation == "Lib")
	}

	@Test func parsesNameWithoutParentheses() {
		let result = HansardSpeakerParser.parse("The Speaker")

		#expect(result.firstName == "")
		#expect(result.lastName == "Speaker")
		#expect(result.partyAbbreviation == "")
		#expect(result.ridingName == "")
	}

	@Test func parsesRightHonourable() {
		let result = HansardSpeakerParser.parse("Rt. Hon. Justin Trudeau (Papineau, Lib.)")

		#expect(result.firstName == "Justin")
		#expect(result.lastName == "Trudeau")
		#expect(result.partyAbbreviation == "Lib")
	}

	@Test func parsesRoleWithRiding() {
		let result = HansardSpeakerParser.parse("Hon. Ruby Sahota (Secretary of State (Combatting Crime), Lib.)")

		#expect(result.firstName == "Ruby")
		#expect(result.lastName == "Sahota")
		#expect(result.partyAbbreviation == "Lib")
	}
}
