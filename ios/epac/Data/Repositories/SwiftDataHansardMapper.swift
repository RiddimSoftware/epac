//
//  SwiftDataHansardMapper.swift
//  epac
//

import Foundation

enum SwiftDataHansardMapper {
	static let federalEnglishLocale = Locale(identifier: "en-CA")
	private static let fullNameComponentCount = 2

	static func transcript(
		from hansard: Hansard,
		sourceURL: URL? = nil,
		language: Locale = federalEnglishLocale
	) -> HansardTranscript {
		HansardTranscript(
			jurisdiction: .federal,
			sittingDate: hansard.date,
			parliamentNumber: optionalMetadataNumber(hansard.parliamentNumber),
			sessionNumber: optionalMetadataNumber(hansard.sessionNumber),
			legislatureNumber: nil,
			sourceURL: sourceURL ?? defaultFederalSourceURL(for: hansard),
			language: language,
			subjects: subjectRecords(from: hansard)
		)
	}

	static func hansard(
		from transcript: HansardTranscript,
		hansardID: String? = nil
	) -> Hansard {
		let resolvedHansardID = hansardID ?? transcriptHansardID(from: transcript)
		let order = OrderOfBusiness(
			hansardID: "\(resolvedHansardID)-order",
			catchline: "Hansard",
			subjects: transcript.subjects.map { subjectModel(from: $0, sittingDate: transcript.sittingDate) }
		)
		return Hansard(
			date: transcript.sittingDate,
			hansardID: resolvedHansardID,
			parliamentNumber: transcript.parliamentNumber ?? 0,
			sessionNumber: transcript.sessionNumber ?? 0,
			orders: [order]
		)
	}

	private static func subjectRecords(from hansard: Hansard) -> [SubjectOfBusinessRecord] {
		hansard.orders.flatMap { order in
			order.subjects.map(subjectRecord(from:))
		}
	}

	private static func subjectRecord(from subject: SubjectOfBusiness) -> SubjectOfBusinessRecord {
		SubjectOfBusinessRecord(
			id: subject.hansardID,
			title: subject.title,
			speeches: subject.speeches.flatMap(speechMessageRecords(from:))
		)
	}

	private static func speechMessageRecords(from speech: Speech) -> [SpeechMessageRecord] {
		speech.messages.map { message in
			SpeechMessageRecord(
				interventionID: message.hansardID,
				speakerName: speakerName(firstName: message.firstName, lastName: message.lastName),
				speakerMemberID: nil,
				text: message.content,
				timestamp: message.timestamp
			)
		}
	}

	private static func subjectModel(
		from record: SubjectOfBusinessRecord,
		sittingDate: Date
	) -> SubjectOfBusiness {
		SubjectOfBusiness(
			title: record.title,
			hansardID: record.id,
			speeches: record.speeches.map { speechModel(from: $0, sittingDate: sittingDate, title: record.title) }
		)
	}

	private static func speechModel(
		from record: SpeechMessageRecord,
		sittingDate: Date,
		title: String
	) -> Speech {
		let speaker = speakerComponents(from: record.speakerName)
		let message = SpeechMessage(
			firstName: speaker.firstName,
			lastName: speaker.lastName,
			partyAbbreviation: "",
			ridingName: "",
			hansardID: record.interventionID,
			content: record.text,
			timestamp: record.timestamp ?? sittingDate
		)
		return Speech(
			messages: [message],
			hansardID: record.interventionID,
			date: sittingDate,
			title: title
		)
	}

	private static func speakerName(firstName: String, lastName: String) -> String {
		[firstName, lastName]
			.filter { !$0.isEmpty }
			.joined(separator: " ")
	}

	private static func optionalMetadataNumber(_ value: Int) -> Int? {
		value > 0 ? value : nil
	}

	private static func speakerComponents(from name: String) -> (firstName: String, lastName: String) {
		let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
		guard parts.count == fullNameComponentCount else {
			return ("", name)
		}
		return (parts[0], parts[1])
	}

	private static func defaultFederalSourceURL(for hansard: Hansard) -> URL {
		var components = URLComponents()
		components.scheme = "https"
		components.host = "www.ourcommons.ca"
		components.path = "/documentviewer/en/\(hansard.parliamentNumber)-\(hansard.sessionNumber)/house/hansard"
		components.queryItems = [URLQueryItem(name: "hansardId", value: hansard.hansardID)]
		return components.url!
	}

	private static func transcriptHansardID(from transcript: HansardTranscript) -> String {
		let queryItems = URLComponents(
			url: transcript.sourceURL,
			resolvingAgainstBaseURL: false
		)?.queryItems
		if let hansardID = queryItems?.first(where: { $0.name == "hansardId" })?.value {
			return hansardID
		}
		return "\(transcript.jurisdiction.rawValue)-\(transcript.sittingDate.timeIntervalSince1970)"
	}
}
