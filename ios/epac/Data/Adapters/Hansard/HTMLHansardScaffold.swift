//
//  HTMLHansardScaffold.swift
//  epac
//

import Foundation

protocol HTMLHansardScaffold {
	var jurisdiction: Jurisdiction { get }
	var language: Locale { get }
}

extension HTMLHansardScaffold {
	var language: Locale { Locale(identifier: "en-CA") }

	func makeTranscript(
		sittingDate: Date,
		legislatureNumber: Int?,
		sourceURL: URL,
		subjects: [SubjectOfBusinessRecord]
	) -> HansardTranscript {
		HansardTranscript(
			jurisdiction: jurisdiction,
			sittingDate: sittingDate,
			parliamentNumber: nil,
			sessionNumber: nil,
			legislatureNumber: legislatureNumber,
			sourceURL: sourceURL,
			language: language,
			subjects: subjects
		)
	}

	func makeSubject(
		id: String,
		title: String,
		speeches: [SpeechMessageRecord]
	) -> SubjectOfBusinessRecord {
		SubjectOfBusinessRecord(
			id: normalizedIdentifier(id),
			title: normalizedText(title),
			speeches: speeches
		)
	}

	func makeSpeech(
		interventionID: String,
		speakerText: String,
		speakerMemberID: String?,
		text: String,
		timestamp: Date? = nil
	) -> SpeechMessageRecord {
		let speaker = HansardSpeakerParser.parse(speakerText)
		let displayName = [speaker.firstName, speaker.lastName]
			.compactMap { $0 }
			.filter { !$0.isEmpty }
			.joined(separator: " ")
		return SpeechMessageRecord(
			interventionID: normalizedIdentifier(interventionID),
			speakerName: displayName.isEmpty ? normalizedText(speakerText) : displayName,
			speakerMemberID: speakerMemberID,
			text: normalizedText(strippingHTMLTags(from: text)),
			timestamp: timestamp
		)
	}

	func normalizedText(_ text: String) -> String {
		text
			.replacingOccurrences(of: "\u{00a0}", with: " ")
			.split { $0.isWhitespace }
			.joined(separator: " ")
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	func normalizedIdentifier(_ text: String) -> String {
		let identifier = normalizedText(text)
		return identifier.isEmpty ? "unknown" : identifier
	}

	func strippingHTMLTags(from html: String) -> String {
		html.replacing(/<[^>]+>/, with: " ")
	}
}
