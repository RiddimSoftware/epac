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
	var messages: [Message] = []
	var speakers: [String: ParliamentMember] = [:]
	var didFinish = false
	var isResuming = false

	var tapAnywhereOpacity: Double {
		messages.count < 2 || isResuming ? 1 : 0
	}

		init(messages: [Message] = []) {

			self.messages = messages

		}

	

		func append(_ message: Message, speaker: ParliamentMember) {

			messages.append(message)

			speakers[message.id] = speaker

		}

	}

	