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

private enum SpeechViewModelLayout {
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

	func reset(navigator: SubjectNavigator, subject: SubjectOfBusiness) {
		reset(subject: subject)
		navigator.reset()
	}

	func prepareResume(subject: SubjectOfBusiness, hansard: Hansard, modelContext: ModelContext, fetch: Fetch, resolver: (any MemberResolving)? = nil) {
		guard isSpeechLoaded, messages.isEmpty else { return }
		let savedSpeechID = subject.currentSpeechID ?? subject.currentSpeech?.hansardID
		let savedMessageID = subject.currentSpeech?.currentMessageID ?? subject.currentSpeech?.currentMessage?.hansardID

		if let savedSpeechID {
			while !didFinish && currentSpeechID != savedSpeechID {
				nextMessage(subject: subject, hansard: hansard, modelContext: modelContext, fetch: fetch, resolver: resolver)
			}
			if let savedMessageID {
				while !didFinish && messages.last?.id != savedMessageID {
					nextMessage(subject: subject, hansard: hansard, modelContext: modelContext, fetch: fetch, resolver: resolver)
				}
			}
			isResuming = !didFinish
		}
	}

	func prepareResume(navigator: SubjectNavigator, subject: SubjectOfBusiness, hansard: Hansard, modelContext: ModelContext, fetch: Fetch, resolver: (any MemberResolving)? = nil) {
		guard messages.isEmpty else { return }
		let savedSpeechID = subject.currentSpeechID ?? subject.currentSpeech?.hansardID
		let savedMessageID = subject.currentSpeech?.currentMessageID ?? subject.currentSpeech?.currentMessage?.hansardID

		if let savedSpeechID {
			while !didFinish && (navigator.navigator == nil || navigator.navigator?.speech.hansardID != savedSpeechID) {
				nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: modelContext, fetch: fetch, resolver: resolver)
			}
			if let savedMessageID {
				while !didFinish && messages.last?.id != savedMessageID {
					nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: modelContext, fetch: fetch, resolver: resolver)
				}
			}
			isResuming = !didFinish
		}
	}

	func nextMessage(subject: SubjectOfBusiness, hansard: Hansard, modelContext: ModelContext, fetch: Fetch, resolver: (any MemberResolving)? = nil) {
		isResuming = false
		guard isSpeechLoaded, !didFinish else { return }
		guard nextSpeechMessageIndex < orderedSpeechMessages.count else {
			didFinish = true
			return
		}

		let message = orderedSpeechMessages[nextSpeechMessageIndex]
		nextSpeechMessageIndex += 1
		if let currentSpeech = subject.speeches.first(where: { $0.hansardID == message.speechID }) {
			subject.currentSpeech = currentSpeech
			subject.currentSpeechID = currentSpeech.hansardID
			currentSpeech.currentMessage = currentSpeech.messages.first { $0.hansardID == message.hansardID }
			currentSpeech.currentMessageID = message.hansardID
		}

		appendChatMessage(message, hansard: hansard, modelContext: modelContext, fetch: fetch, resolver: resolver)
	}

	func nextMessage(navigator: SubjectNavigator, subject: SubjectOfBusiness, hansard: Hansard, modelContext: ModelContext, fetch: Fetch, resolver: (any MemberResolving)? = nil) {
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

		appendChatMessage(message.record(speechID: navigator.navigator?.speech.hansardID ?? ""), hansard: hansard, modelContext: modelContext, fetch: fetch, resolver: resolver)
	}

	private func appendChatMessage(
		_ message: SpeechMessageRecord,
		hansard: Hansard,
		modelContext: ModelContext,
		fetch: Fetch,
		resolver: (any MemberResolving)?
	) {
		// Use the method-level override when provided (e.g. tests); fall back to
		// the injected stored resolver.
		let activeResolver = resolver ?? self.resolver
		let speaker = activeResolver.resolve(
			firstName: message.firstName,
			lastName: message.lastName,
			partyAbbreviation: message.partyAbbreviation,
			ridingName: message.ridingName,
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
			id: message.hansardID,
			user: User(
				id: "\(speaker.persistentModelID)",
				name: speaker.name,
				avatarURL: speaker.photoURL,
				isCurrentUser: isCurrentUser
			),
			createdAt: message.timestamp,
			text: message.content
		), speaker: speaker)
	}

	@MainActor
	func shareMessage(_ message: Message, subject: SubjectOfBusiness, hansard: Hansard) -> ActivityItem? {
		guard let speaker = speakers[message.id] else { return nil }
		let renderer = ImageRenderer(content: createMessageView(message, speaker: speaker, subject: subject, hansard: hansard))
		renderer.scale = UIScreen.main.scale
		if let image = renderer.uiImage {
			let source = ShareActivityItemSource(image: image, title: subject.title)
			return ActivityItem(items: source)
		}
		return nil
	}

	@MainActor
	func shareLast5Messages(subject: SubjectOfBusiness, hansard: Hansard) -> ActivityItem? {
		let lastMessages = Array(messages.suffix(SpeechViewModelLayout.shareMessageLimit))
		let baseURL = "https://epac.riddimsoftware.com/app?date=\(hansard.date.ISO8601Format())&subjectID=\(subject.hansardID)"
		let url: URL
		if didFinish {
			url = URL(string: baseURL)!
		} else if let nextMessage = nextSpeechMessage {
			url = URL(string: "\(baseURL)&speechID=\(nextMessage.speechID)&messageID=\(nextMessage.hansardID)")!
		} else {
			url = URL(string: baseURL)!
		}

		let shareView = MultiMessageShareView(messages: lastMessages, speakers: speakers, parliamentNumber: hansard.parliamentNumber, subjectTitle: subject.title, date: hansard.date)
		let renderer = ImageRenderer(content: shareView)
		renderer.scale = UIScreen.main.scale
		if let image = renderer.uiImage {
			let source = ShareActivityItemSource(image: image, title: subject.title, url: url)
			return ActivityItem(items: source, url)
		} else {
			return ActivityItem(items: url)
		}
	}

	private var currentSpeechID: String? {
		guard nextSpeechMessageIndex > 0 else { return nil }
		return orderedSpeechMessages[nextSpeechMessageIndex - 1].speechID
	}

	private var nextSpeechMessage: SpeechMessageRecord? {
		guard nextSpeechMessageIndex < orderedSpeechMessages.count else { return nil }
		return orderedSpeechMessages[nextSpeechMessageIndex]
	}

	private func createMessageView(_ message: Message, speaker: ParliamentMember, subject: SubjectOfBusiness, hansard: Hansard) -> some View {
		VStack(alignment: .leading, spacing: SpeechViewModelLayout.shareRootSpacing) {
			VStack(alignment: .leading, spacing: SpeechViewModelLayout.shareHeaderSpacing) {
				Text(subject.title)
					.font(.system(.headline, design: .rounded))
					.foregroundStyle(.gray)
				Text(hansard.date.formatted(date: .long, time: .omitted))
					.font(.system(.subheadline, design: .rounded))
					.foregroundStyle(.gray.opacity(SpeechViewModelLayout.shareHeaderOpacity))
			}
			.padding(.bottom, SpeechViewModelLayout.shareHeaderBottomPadding)

			HStack(alignment: .bottom) {
				if message.user.isCurrentUser {
					Spacer()
				}
				if !message.user.isCurrentUser {
					SpeakerImageView(speaker: speaker, parliamentNumber: hansard.parliamentNumber)
				}
				VStack(alignment: message.user.isCurrentUser ? .trailing : .leading) {
					VStack(alignment: .leading, spacing: SpeechViewModelLayout.shareMessageSpacing) {
						VStack(alignment: .leading, spacing: 0) {
							Text(speaker.name)
								.font(.system(.caption, design: .rounded, weight: .bold))
							Text("\(speaker.riding), \(speaker.province.rawValue)")
								.font(.system(.caption2, design: .rounded))
						}
						.foregroundStyle(.white.opacity(SpeechViewModelLayout.shareSpeakerOpacity))
						Text(verbatim: message.text)
							.lineSpacing(SpeechViewModelLayout.shareLineSpacing)
					}
					.padding(SpeechViewModelLayout.shareBubblePadding)
					.background(message.user.isCurrentUser ? Color(UIColor.darkGray) : Color(UIColor.gray))
					.cornerRadius(SpeechViewModelLayout.shareBubbleCornerRadius)
					.foregroundStyle(.white)
				}
				if message.user.isCurrentUser {
					SpeakerImageView(speaker: speaker, parliamentNumber: hansard.parliamentNumber)
				}
				if !message.user.isCurrentUser {
					Spacer()
				}
			}
		}
		.padding()
		.background(Color.appBackground)
		.fixedSize(horizontal: false, vertical: true)
		.frame(width: SpeechViewModelLayout.shareWidth)
	}
}

enum SpeechViewModelError: Error {
	case missingReadHansardSpeech
}
