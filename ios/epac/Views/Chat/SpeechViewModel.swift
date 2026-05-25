//
//  SpeechViewModel.swift
//  epac
//
//  Created by Sunny on 2025-05-24.
//

import ActivityView
import ExyteChat
import Observation
import SwiftData
import SwiftUI

enum SpeechViewModelLayout {
	static let tapHintMessageThreshold = 2
	static let tapHintVisibleOpacity = 1.0
	static let tapHintHiddenOpacity = 0.0
	static let shareMessageLimit = 5
	static let shareRootSpacing = EpacSpacing.m
	static let shareHeaderSpacing = EpacSpacing.xs
	static let shareHeaderOpacity = 0.8
	static let shareHeaderBottomPadding = EpacSpacing.s
	static let shareMessageSpacing = EpacSpacing.xs
	static let shareSpeakerOpacity = 0.8
	static let shareLineSpacing = EpacSpacing.xs
	static let shareBubblePadding: CGFloat = 10
	static let shareBubbleCornerRadius: CGFloat = 10
	static let shareWidth: CGFloat = 400
}

private struct ChatMessageInput {
	let firstName: String
	let lastName: String
	let partyAbbreviation: String
	let ridingName: String
	let id: String
	let text: String
	let timestamp: Date
}

@MainActor
@Observable
class SpeechViewModel {
	var messages: [Message] = []
	var speakers: [String: ParliamentMember] = [:]
	var didFinish = false
	var isResuming = false
	var isSpeechLoaded = false

	// Injected resolver dependency. Defaults to CachingMemberResolver (production)
	// so callers don't need to supply one. In unit tests, pass a mock conforming
	// to MemberResolving to avoid SwiftData/network I/O.
	private let resolver: any MemberResolving
	private var readHansardSpeech: (any ReadHansardSpeechUseCase)?
	private var orderedSpeechMessages: [SpeechMessageRecord] = []
	private var nextSpeechMessageIndex = 0

	var tapAnywhereOpacity: Double {
		messages.count < SpeechViewModelLayout.tapHintMessageThreshold || isResuming
			? SpeechViewModelLayout.tapHintVisibleOpacity
			: SpeechViewModelLayout.tapHintHiddenOpacity
	}

	init(
		messages: [Message] = [],
		readHansardSpeech: (any ReadHansardSpeechUseCase)? = nil,
		resolver: any MemberResolving = CachingMemberResolver()
	) {
		self.messages = messages
		self.readHansardSpeech = readHansardSpeech
		self.resolver = resolver
	}

	func configure(readHansardSpeech: any ReadHansardSpeechUseCase) {
		self.readHansardSpeech = readHansardSpeech
	}

	func loadSpeech(jurisdiction: Jurisdiction, sittingDate: Date, subjectID: String) async throws {
		guard let readHansardSpeech else {
			throw SpeechViewModelError.missingReadHansardSpeech
		}
		orderedSpeechMessages = try await readHansardSpeech.execute(
			jurisdiction: jurisdiction,
			sittingDate: sittingDate,
			subjectID: subjectID
		)
		nextSpeechMessageIndex = 0
		isSpeechLoaded = true
		didFinish = orderedSpeechMessages.isEmpty
	}

	func append(_ message: Message, speaker: ParliamentMember) {
		messages.append(message)
		speakers[message.id] = speaker
	}

	func reset(subject: SubjectOfBusiness) {
		messages.removeAll()
		speakers.removeAll()
		didFinish = false
		isResuming = false
		nextSpeechMessageIndex = 0
		resolver.resetCache()
		subject.currentSpeech?.currentMessage = nil
		subject.currentSpeech?.currentMessageID = nil
		subject.currentSpeech = nil
		subject.currentSpeechID = nil
	}

	func prepareResume(
		subject: SubjectOfBusiness,
		hansard: Hansard,
		modelContext: ModelContext,
		fetch: Fetch,
		resolver: (any MemberResolving)? = nil
	) {
		guard isSpeechLoaded, messages.isEmpty else { return }
		let savedSpeechID = subject.currentSpeechID ?? subject.currentSpeech?.hansardID
		let savedMessageID = subject.currentSpeech?.currentMessageID ?? subject.currentSpeech?.currentMessage?.hansardID

		if let savedSpeechID {
			while !didFinish && subject.currentSpeechID != savedSpeechID {
				nextMessage(
					subject: subject,
					hansard: hansard,
					modelContext: modelContext,
					fetch: fetch,
					resolver: resolver
				)
			}
			if let savedMessageID {
				while !didFinish && messages.last?.id != savedMessageID {
					nextMessage(
						subject: subject,
						hansard: hansard,
						modelContext: modelContext,
						fetch: fetch,
						resolver: resolver
					)
				}
			}
			isResuming = !didFinish
		}
	}

	func nextMessage(
		subject: SubjectOfBusiness,
		hansard: Hansard,
		modelContext: ModelContext,
		fetch: Fetch,
		resolver: (any MemberResolving)? = nil
	) {
		isResuming = false
		guard isSpeechLoaded, !didFinish else { return }
		guard nextSpeechMessageIndex < orderedSpeechMessages.count else {
			didFinish = true
			return
		}

		let message = orderedSpeechMessages[nextSpeechMessageIndex]
		nextSpeechMessageIndex += 1
		if let currentSpeech = subject.speeches.first(where: { speech in
			speech.messages.contains { $0.hansardID == message.interventionID }
		}) {
			subject.currentSpeech = currentSpeech
			subject.currentSpeechID = currentSpeech.hansardID
			currentSpeech.currentMessage = currentSpeech.messages.first { $0.hansardID == message.interventionID }
			currentSpeech.currentMessageID = message.interventionID
		}

		appendChatMessage(message, hansard: hansard, modelContext: modelContext, fetch: fetch, resolver: resolver)
	}

	private func appendChatMessage(
		_ message: SpeechMessageRecord,
		hansard: Hansard,
		modelContext: ModelContext,
		fetch: Fetch,
		resolver: (any MemberResolving)?
	) {
		let speakerComponents = Self.speakerComponents(from: message.speakerName)
		appendChatMessage(
			ChatMessageInput(
				firstName: speakerComponents.firstName,
				lastName: speakerComponents.lastName,
				partyAbbreviation: "",
				ridingName: "",
				id: message.interventionID,
				text: message.text,
				timestamp: message.timestamp ?? hansard.date
			),
			hansard: hansard,
			modelContext: modelContext,
			fetch: fetch,
			resolver: resolver
		)
	}

	private func appendChatMessage(
		_ input: ChatMessageInput,
		hansard: Hansard,
		modelContext: ModelContext,
		fetch: Fetch,
		resolver: (any MemberResolving)?
	) {
		// Use the method-level override when provided (e.g. tests); fall back to
		// the injected stored resolver.
		let activeResolver = resolver ?? self.resolver
		let speaker = activeResolver.resolve(
			firstName: input.firstName,
			lastName: input.lastName,
			partyAbbreviation: input.partyAbbreviation,
			ridingName: input.ridingName,
			parliamentNumber: hansard.parliamentNumber,
			modelContext: modelContext,
			fetch: fetch
		)

		var isCurrentUser: Bool
		if let last = messages.last {
			isCurrentUser = last.user.isCurrentUser
		} else {
			isCurrentUser = speaker.party == .liberal
		}
		if let last = messages.last, let lastSpeaker = speakers[last.id], speaker != lastSpeaker {
			isCurrentUser.toggle()
		}

		append(Message(
			id: input.id,
			user: User(
				id: "\(speaker.persistentModelID)",
				name: speaker.name,
				avatarURL: speaker.photoURL,
				isCurrentUser: isCurrentUser
			),
			createdAt: input.timestamp,
			text: input.text
		), speaker: speaker)
	}

	var nextSpeechMessage: SpeechMessageRecord? {
		guard nextSpeechMessageIndex < orderedSpeechMessages.count else { return nil }
		return orderedSpeechMessages[nextSpeechMessageIndex]
	}

	func speechID(containing messageID: String, in subject: SubjectOfBusiness) -> String? {
		subject.speeches.first { speech in
			speech.messages.contains { $0.hansardID == messageID }
		}?.hansardID
	}

	private static let fullNameComponentCount = 2

	private static func speakerComponents(from name: String) -> (firstName: String, lastName: String) {
		let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
		guard parts.count == fullNameComponentCount else {
			return ("", name)
		}
		return (parts[0], parts[1])
	}

}

extension SpeechViewModel {
	func reset(navigator: SubjectNavigator, subject: SubjectOfBusiness) {
		reset(subject: subject)
		navigator.reset()
	}

	func prepareResume(
		navigator: SubjectNavigator,
		subject: SubjectOfBusiness,
		hansard: Hansard,
		modelContext: ModelContext,
		fetch: Fetch,
		resolver: (any MemberResolving)? = nil
	) {
		guard messages.isEmpty else { return }
		let savedSpeechID = subject.currentSpeechID ?? subject.currentSpeech?.hansardID
		let savedMessageID = subject.currentSpeech?.currentMessageID ?? subject.currentSpeech?.currentMessage?.hansardID

		if let savedSpeechID {
			while !didFinish
				&& (navigator.navigator == nil || navigator.navigator?.speech.hansardID != savedSpeechID) {
				nextMessage(
					navigator: navigator,
					subject: subject,
					hansard: hansard,
					modelContext: modelContext,
					fetch: fetch,
					resolver: resolver
				)
			}
			if let savedMessageID {
				while !didFinish && messages.last?.id != savedMessageID {
					nextMessage(
						navigator: navigator,
						subject: subject,
						hansard: hansard,
						modelContext: modelContext,
						fetch: fetch,
						resolver: resolver
					)
				}
			}
			isResuming = !didFinish
		}
	}

	func nextMessage(
		navigator: SubjectNavigator,
		subject: SubjectOfBusiness,
		hansard: Hansard,
		modelContext: ModelContext,
		fetch: Fetch,
		resolver: (any MemberResolving)? = nil
	) {
		isResuming = false
		guard !didFinish else { return }
		guard let message = navigator.next() else {
			didFinish = true
			return
		}

		if let currentSpeech = navigator.navigator?.speech {
			subject.currentSpeech = currentSpeech
			subject.currentSpeechID = currentSpeech.hansardID
			currentSpeech.currentMessage = message
			currentSpeech.currentMessageID = message.hansardID
		}

		appendChatMessage(
			ChatMessageInput(
				firstName: message.firstName,
				lastName: message.lastName,
				partyAbbreviation: message.partyAbbreviation,
				ridingName: message.ridingName,
				id: message.hansardID,
				text: message.content,
				timestamp: message.timestamp
			),
			hansard: hansard,
			modelContext: modelContext,
			fetch: fetch,
			resolver: resolver
		)
	}
}

enum SpeechViewModelError: Error {
	case missingReadHansardSpeech
}
