//
//  SpeechNavigator.swift
//  epac
//
//  Created by Sunny on 2025-05-23.
//

import Observation

@Observable
class SpeechNavigator {
	var speech: Speech
	var messages: [SpeechMessage]
	init(_ speech: Speech) {
		self.speech = speech
		self.messages = speech.messages.sorted(by: { $0.hansardID.caseInsensitiveCompare($1.hansardID) == .orderedAscending })
	}
	func next() -> SpeechMessage? {
		guard !messages.isEmpty else { return nil }
		return messages.removeFirst()
	}
}

//@Observable class SittingNavigator {
//	var hansard: Hansard
//	
//}

@Observable
class SubjectNavigator {
	var subject: SubjectOfBusiness
	var speeches: [Speech]
	var navigator: SpeechNavigator?
	var navigators: [SpeechNavigator]
	init(_ subject: SubjectOfBusiness) {
		Log.debug("Init subject navigator")
		self.subject = subject
		let speeches = subject.speeches.sorted(by: { lhs, rhs in
			let lmin = lhs.messages.min(by: { $0.hansardID.caseInsensitiveCompare($1.hansardID) == .orderedAscending })
			let rmin = rhs.messages.min(by: { $0.hansardID.caseInsensitiveCompare($1.hansardID) == .orderedAscending })
			if let lmin, let rmin {
				return lmin.hansardID.caseInsensitiveCompare(rmin.hansardID) == .orderedAscending
			} else {
				return lhs.hansardID.caseInsensitiveCompare(rhs.hansardID) == .orderedAscending
			}
		})
		self.speeches = speeches
		self.navigators = speeches.map { SpeechNavigator($0) }
	}

	func reset() {
		self.speeches = subject.speeches.sorted(by: { lhs, rhs in
			let lmin = lhs.messages.min(by: { $0.hansardID.caseInsensitiveCompare($1.hansardID) == .orderedAscending })
			let rmin = rhs.messages.min(by: { $0.hansardID.caseInsensitiveCompare($1.hansardID) == .orderedAscending })
			if let lmin, let rmin {
				return lmin.hansardID.caseInsensitiveCompare(rmin.hansardID) == .orderedAscending
			} else {
				return lhs.hansardID.caseInsensitiveCompare(rhs.hansardID) == .orderedAscending
			}
		})
		self.navigators = speeches.map { SpeechNavigator($0) }
	}
	func next() -> SpeechMessage? {
		if let navigator {
			if let message = navigator.next() {
//				Log.debug("returning message \(navigator.index)/\(navigator.speech.messages.count) \(message.hansardID)")
				return message
			} else {
				if navigators.isEmpty {
					return nil
				} else {
					self.navigator = navigators.removeFirst()
					return next()
				}
			}
		} else {
			navigator = navigators.removeFirst()
			return next()
		}
	}
}
