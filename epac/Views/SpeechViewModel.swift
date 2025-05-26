//
//  SpeechViewModel.swift
//  epac
//
//  Created by Sunny on 2025-05-24.
//

import Observation
import ExyteChat

@Observable
class SpeechViewModel {
	var messages: [ChatMessage]
	var didFinish = false
	var isResuming = false

	var tapAnywhereOpacity: Double {
		messages.count < 2 || isResuming ? 1 : 0
	}
	
	init(messages: [ChatMessage] = []) {
		Log.debug("init speech view model")
		self.messages = messages
	}

	func append(_ message: ChatMessage) {
		Log.debug("Appending \(message.message.hansardID) to \(messages.count) messages")
		self.messages.append(message)
	}
}
