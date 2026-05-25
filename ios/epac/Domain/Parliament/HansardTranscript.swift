//
//  HansardTranscript.swift
//  epac
//

import Foundation

enum Jurisdiction: String, Sendable, Codable, CaseIterable, Equatable {
	case federal
	case alberta
	case britishColumbia
	case manitoba
	case newBrunswick
	case newfoundlandAndLabrador
	case novaScotia
	case ontario
	case princeEdwardIsland
	case quebec
	case saskatchewan
}

struct HansardTranscript: Sendable, Equatable {
	let jurisdiction: Jurisdiction
	let sittingDate: Date
	let parliamentNumber: Int?
	let sessionNumber: Int?
	let legislatureNumber: Int?
	let sourceURL: URL
	let language: Locale
	let subjects: [SubjectOfBusinessRecord]
}

struct SubjectOfBusinessRecord: Sendable, Equatable {
	let id: String
	let title: String
	let speeches: [SpeechMessageRecord]
}

struct SpeechMessageRecord: Sendable, Equatable {
	let interventionID: String
	let speakerName: String
	let speakerMemberID: String?
	let text: String
	let timestamp: Date?
	let wordCount: Int

	init(
		interventionID: String,
		speakerName: String,
		speakerMemberID: String?,
		text: String,
		timestamp: Date?,
		wordCount: Int? = nil
	) {
		self.interventionID = interventionID
		self.speakerName = speakerName
		self.speakerMemberID = speakerMemberID
		self.text = text
		self.timestamp = timestamp
		self.wordCount = wordCount ?? Self.countWords(in: text)
	}

	private static func countWords(in text: String) -> Int {
		text.split { $0.isWhitespace }.count
	}
}
