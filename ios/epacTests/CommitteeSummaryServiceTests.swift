import Foundation
import Testing
@testable import epac

struct CommitteeSummaryServiceTests {
	@Test func filtersWitnessInterventionsOnly() {
		let interventions = [
			intervention(id: "chair", role: "Chair", isMP: false, affiliation: "", content: longText("I call this meeting to order and thank you, colleagues, for joining us today.")),
			intervention(id: "member", role: "Member", isMP: true, affiliation: "Liberal", content: longText("Can the witness explain the fiscal impact of the proposal on rural communities?")),
			intervention(id: "witness", role: "Witness", isMP: false, affiliation: "Canadian Medical Association", content: longText("Our association recommends stable federal funding, better workforce planning, and transparent reporting for health transfers."))
		]

		let witnesses = CommitteeSummaryService.witnessInterventions(from: interventions)

		#expect(witnesses.map(\.id) == ["witness"])
	}

	@Test func generatesWitnessDigestsAndCachesByMeetingVersion() async throws {
		let generator = RecordingSummaryGenerator(responses: [
			"The witness said federal funding should be stable.",
			"The witness said reporting should be transparent.",
			"The witness emphasized stable funding and transparent reporting."
		])
		let service = CommitteeSummaryService(generator: generator)
		let meeting = committeeMeeting()
		let interventions = [
			intervention(id: "w1", content: longText("Stable federal funding would let provinces plan staffing and services over several years.")),
			intervention(id: "w2", content: longText("Transparent reporting would help the public understand whether money reaches front-line care."))
		]

		let first = try await service.witnessDigests(for: meeting, interventions: interventions)
		let second = try await service.witnessDigests(for: meeting, interventions: interventions)

		#expect(first == second)
		#expect(first.count == 1)
		#expect(first.first?.witnessName == "Dr. Jane Smith")
		#expect(first.first?.interventionCount == 2)
		#expect(await generator.promptCount() == 3)
	}

	@Test func hearingOverviewIsGeneratedOnDemandAndCached() async throws {
		let generator = RecordingSummaryGenerator(responses: [
			"Intervention summary.",
			"Witness digest.",
			"Hearing overview."
		])
		let service = CommitteeSummaryService(generator: generator)
		let meeting = committeeMeeting()
		let interventions = [intervention(content: longText("The program needs stable funding and clear public reporting to be useful."))]

		let overview = try await service.hearingOverview(for: meeting, interventions: interventions)
		let cached = try await service.hearingOverview(for: meeting, interventions: interventions)

		#expect(overview == "Hearing overview.")
		#expect(cached == overview)
		#expect(await generator.promptCount() == 3)
	}

	@Test func transcriptCorrectionsInvalidateDigestCache() async throws {
		let generator = RecordingSummaryGenerator(responses: [
			"Original intervention summary.",
			"Original witness digest.",
			"Corrected intervention summary.",
			"Corrected witness digest."
		])
		let service = CommitteeSummaryService(generator: generator)
		let meeting = committeeMeeting()
		let original = [intervention(content: longText("Original testimony emphasized stable funding for rural care."))]
		let corrected = [intervention(content: longText("Corrected testimony emphasized stable funding and public reporting for rural care."))]

		let first = try await service.witnessDigests(for: meeting, interventions: original)
		let second = try await service.witnessDigests(for: meeting, interventions: corrected)

		#expect(first.first?.summary == "Original witness digest.")
		#expect(second.first?.summary == "Corrected witness digest.")
		#expect(await generator.promptCount() == 4)
	}

	private func committeeMeeting() -> CommitteeMeeting {
		CommitteeMeeting(
			id: "FINA-45-1-10",
			committee: "FINA",
			committeeName: "Standing Committee on Finance",
			meetingNumber: 10,
			sessionNumber: 1,
			parliament: 45,
			date: nil,
			agendaItems: ["Federal budget"],
			webcastURL: nil,
			publicationURL: nil,
			evidenceURL: nil
		)
	}

	private func intervention(
		id: String = "witness",
		role: String = "Witness",
		isMP: Bool = false,
		affiliation: String = "Canadian Medical Association",
		content: String
	) -> CommitteeIntervention {
		CommitteeIntervention(
			id: id,
			speakerName: "Dr. Jane Smith",
			speakerRole: role,
			affiliation: affiliation,
			isMP: isMP,
			content: content,
			timestamp: nil
		)
	}

	private func longText(_ seed: String) -> String {
		"\(seed) This testimony includes enough detail to avoid procedural filtering and to represent a substantive witness intervention before the committee."
	}
}

private actor RecordingSummaryGenerator: CommitteeSummaryGenerating {
	private var responses: [String]
	private var prompts: [String] = []

	init(responses: [String]) {
		self.responses = responses
	}

	func summarize(prompt: String) async throws -> String {
		prompts.append(prompt)
		if responses.isEmpty {
			return "Summary \(prompts.count)"
		}
		return responses.removeFirst()
	}

	func promptCount() -> Int {
		prompts.count
	}
}
