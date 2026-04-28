//
//  SpeechMessageAccessibility.swift
//  epac
//

import ExyteChat
import Foundation

enum SpeechMessageAccessibility {
	static func label(for message: Message, speaker: ParliamentMember?) -> String {
		guard let speaker else {
			return "Unknown speaker: \(message.text)"
		}
		return "\(speaker.name), \(speaker.party.fullName), \(speaker.riding), \(speaker.province.rawValue): \(message.text)"
	}

	static func value(for message: Message, messages: [Message], totalCount: Int) -> String {
		guard let index = messages.firstIndex(where: { $0.id == message.id }) else {
			return "Message"
		}
		let total = max(totalCount, messages.count)
		return "Message \(index + 1) of \(total)"
	}
}
