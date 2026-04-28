import CryptoKit
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct CommitteeWitnessDigest: Identifiable, Equatable, Sendable {
	let id: String
	let witnessName: String
	let affiliation: String
	let interventionCount: Int
	let summary: String
}

struct CommitteeHearingDigest: Equatable, Sendable {
	let meetingID: String
	let cacheVersion: String
	let witnessDigests: [CommitteeWitnessDigest]
	let overview: String?
}

enum CommitteeSummaryServiceError: Error, Equatable {
	case modelUnavailable
	case noWitnessInterventions
}

protocol CommitteeSummaryGenerating: Sendable {
	func summarize(prompt: String) async throws -> String
}

actor CommitteeSummaryService {
	static let shared = CommitteeSummaryService(generator: CommitteeSummaryService.makeDefaultGenerator())
	static let label = "AI Summary · on-device · May contain errors"

	private let generator: (any CommitteeSummaryGenerating)?
	private var cache: [String: CommitteeHearingDigest] = [:]

	init(generator: (any CommitteeSummaryGenerating)?) {
		self.generator = generator
	}

	static var isAvailable: Bool {
		#if canImport(FoundationModels)
		if #available(iOS 26.0, macOS 26.0, *) {
			return SystemLanguageModel.default.isAvailable
		}
		#endif
		return false
	}

	func witnessDigests(
		for meeting: CommitteeMeeting,
		interventions: [CommitteeIntervention]
	) async throws -> [CommitteeWitnessDigest] {
		let version = Self.cacheVersion(for: interventions)
		if let cached = cache[meeting.id], cached.cacheVersion == version {
			return cached.witnessDigests
		}

		guard let generator else { throw CommitteeSummaryServiceError.modelUnavailable }

		let witnessGroups = Self.witnessGroups(from: interventions)
		guard !witnessGroups.isEmpty else { throw CommitteeSummaryServiceError.noWitnessInterventions }

		var digests: [CommitteeWitnessDigest] = []
		for group in witnessGroups {
			var interventionSummaries: [String] = []
			for intervention in group.interventions {
				let prompt = Self.interventionPrompt(meeting: meeting, intervention: intervention)
				let summary = try await generator.summarize(prompt: prompt)
				let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
				if !trimmed.isEmpty {
					interventionSummaries.append(trimmed)
				}
			}

			guard !interventionSummaries.isEmpty else { continue }
			let witnessPrompt = Self.witnessPrompt(
				meeting: meeting,
				witnessName: group.name,
				affiliation: group.affiliation,
				interventionSummaries: interventionSummaries
			)
			let witnessSummary = try await generator.summarize(prompt: witnessPrompt)
				.trimmingCharacters(in: .whitespacesAndNewlines)
			if !witnessSummary.isEmpty {
				digests.append(
					CommitteeWitnessDigest(
						id: group.id,
						witnessName: group.name,
						affiliation: group.affiliation,
						interventionCount: group.interventions.count,
						summary: witnessSummary
					)
				)
			}
		}

		let existingOverview = cache[meeting.id]?.overview
		cache[meeting.id] = CommitteeHearingDigest(
			meetingID: meeting.id,
			cacheVersion: version,
			witnessDigests: digests,
			overview: existingOverview
		)
		return digests
	}

	func hearingOverview(
		for meeting: CommitteeMeeting,
		interventions: [CommitteeIntervention]
	) async throws -> String {
		let version = Self.cacheVersion(for: interventions)
		if let cached = cache[meeting.id],
		   cached.cacheVersion == version,
		   let overview = cached.overview {
			return overview
		}

		guard let generator else { throw CommitteeSummaryServiceError.modelUnavailable }

		let digests = try await witnessDigests(for: meeting, interventions: interventions)
		let prompt = Self.hearingOverviewPrompt(meeting: meeting, witnessDigests: digests)
		let overview = try await generator.summarize(prompt: prompt)
			.trimmingCharacters(in: .whitespacesAndNewlines)

		cache[meeting.id] = CommitteeHearingDigest(
			meetingID: meeting.id,
			cacheVersion: version,
			witnessDigests: digests,
			overview: overview
		)
		return overview
	}

	static func witnessInterventions(from interventions: [CommitteeIntervention]) -> [CommitteeIntervention] {
		interventions.filter(isWitnessIntervention)
	}

	private static func isWitnessIntervention(_ intervention: CommitteeIntervention) -> Bool {
		guard !intervention.isMP else { return false }

		let role = intervention.speakerRole.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		let affiliation = intervention.affiliation.trimmingCharacters(in: .whitespacesAndNewlines)
		let content = intervention.content.trimmingCharacters(in: .whitespacesAndNewlines)
		guard content.split(whereSeparator: \.isWhitespace).count >= 20 else { return false }

		if role.contains("chair")
			|| role.contains("member")
			|| role.contains("clerk")
			|| role.contains("analyst")
			|| role.contains("secretary") {
			return false
		}

		let lowerContent = content.lowercased()
		let proceduralFragments = [
			"i call this meeting",
			"meeting is adjourned",
			"we will suspend",
			"the motion is adopted",
			"point of order",
			"thank you, colleagues"
		]
		if content.count < 220 && proceduralFragments.contains(where: lowerContent.contains) {
			return false
		}

		return role.contains("witness") || !affiliation.isEmpty
	}

	private static func witnessGroups(from interventions: [CommitteeIntervention]) -> [WitnessGroup] {
		var groupsByKey: [String: WitnessGroup] = [:]
		for intervention in witnessInterventions(from: interventions) {
			let name = intervention.speakerName.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !name.isEmpty else { continue }
			let affiliation = intervention.affiliation.trimmingCharacters(in: .whitespacesAndNewlines)
			let key = "\(name.lowercased())|\(affiliation.lowercased())"
			var group = groupsByKey[key] ?? WitnessGroup(
				id: key.replacingOccurrences(of: " ", with: "-"),
				name: name,
				affiliation: affiliation,
				interventions: []
			)
			group.interventions.append(intervention)
			groupsByKey[key] = group
		}

		return groupsByKey.values.sorted { lhs, rhs in
			if lhs.name == rhs.name {
				return lhs.affiliation < rhs.affiliation
			}
			return lhs.name < rhs.name
		}
	}

	private static func cacheVersion(for interventions: [CommitteeIntervention]) -> String {
		let versionInput = interventions
			.map { intervention in
				[
					intervention.id,
					intervention.speakerName,
					intervention.speakerRole,
					intervention.affiliation,
					String(intervention.isMP),
					intervention.content
				].joined(separator: "\u{1F}")
			}
			.joined(separator: "\u{1E}")
		let digest = SHA256.hash(data: Data(versionInput.utf8))
		return digest.map { String(format: "%02x", $0) }.joined()
	}

	private static func interventionPrompt(
		meeting: CommitteeMeeting,
		intervention: CommitteeIntervention
	) -> String {
		"""
		Summarize the following testimony from a parliamentary committee hearing in 1-2 sentences.
		Only include information present in the text. Do not add interpretation.

		Committee: \(meeting.committeeName)
		Meeting: \(meeting.meetingNumber)
		Witness: \(intervention.speakerName), \(intervention.affiliation)

		\(intervention.content)
		"""
	}

	private static func witnessPrompt(
		meeting: CommitteeMeeting,
		witnessName: String,
		affiliation: String,
		interventionSummaries: [String]
	) -> String {
		"""
		The following are summaries of testimony given by \(witnessName) (\(affiliation)) at \(meeting.committeeName), meeting \(meeting.meetingNumber).
		Write a 3-4 sentence summary of their overall position and key points.
		Only use information from the summaries below.

		\(interventionSummaries.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
		"""
	}

	private static func hearingOverviewPrompt(
		meeting: CommitteeMeeting,
		witnessDigests: [CommitteeWitnessDigest]
	) -> String {
		"""
		The following are witness digests from \(meeting.committeeName), meeting \(meeting.meetingNumber).
		Write a 5-7 sentence overview of the hearing's main themes.
		Only use information from the witness digests below.

		\(witnessDigests.map { "\($0.witnessName) (\($0.affiliation)): \($0.summary)" }.joined(separator: "\n\n"))
		"""
	}

	private static func makeDefaultGenerator() -> (any CommitteeSummaryGenerating)? {
		#if canImport(FoundationModels)
		if #available(iOS 26.0, macOS 26.0, *) {
			guard SystemLanguageModel.default.isAvailable else { return nil }
			return FoundationModelsCommitteeSummarizer()
		}
		#endif
		return nil
	}
}

private struct WitnessGroup: Sendable {
	let id: String
	let name: String
	let affiliation: String
	var interventions: [CommitteeIntervention]
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
private struct FoundationModelsCommitteeSummarizer: CommitteeSummaryGenerating {
	func summarize(prompt: String) async throws -> String {
		let session = LanguageModelSession(
			instructions: """
			You summarize Canadian parliamentary committee evidence for civic users.
			Keep summaries factual, concise, neutral, and grounded only in the provided text.
			Do not infer motives, positions, or facts that are not explicitly present.
			"""
		)
		let response = try await session.respond(to: prompt)
		return response.content
	}
}
#endif
