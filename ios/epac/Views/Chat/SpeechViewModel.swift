//
//  SpeechViewModel.swift
//  epac
//
//  Created by Sunny on 2025-05-24.
//

import Observation
import ExyteChat
import SwiftData
import ActivityView
import SwiftUI

@MainActor
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

	func reset(navigator: SubjectNavigator, subject: SubjectOfBusiness) {
		messages.removeAll()
		speakers.removeAll()
		didFinish = false
		subject.currentSpeech?.currentMessage = nil
		subject.currentSpeech?.currentMessageID = nil
		subject.currentSpeech = nil
		subject.currentSpeechID = nil
		navigator.reset()
	}

	func prepareResume(navigator: SubjectNavigator, subject: SubjectOfBusiness, hansard: Hansard, modelContext: ModelContext, fetch: Fetch) {
		guard messages.isEmpty else { return }
		let savedSpeechID = subject.currentSpeechID ?? subject.currentSpeech?.hansardID
		let savedMessageID = subject.currentSpeech?.currentMessageID ?? subject.currentSpeech?.currentMessage?.hansardID

		if let savedSpeechID {
			while !didFinish && (navigator.navigator == nil || navigator.navigator?.speech.hansardID != savedSpeechID) {
				nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: modelContext, fetch: fetch)
			}
			if let savedMessageID {
				while !didFinish && messages.last?.id != savedMessageID {
					nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: modelContext, fetch: fetch)
				}
			}
			isResuming = !didFinish
		}
	}

	func nextMessage(navigator: SubjectNavigator, subject: SubjectOfBusiness, hansard: Hansard, modelContext: ModelContext, fetch: Fetch) {
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

		let speaker = MemberResolver().resolve(
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
	func shareLast5Messages(navigator: SubjectNavigator, subject: SubjectOfBusiness, hansard: Hansard) -> ActivityItem? {
		let last5 = Array(messages.suffix(5))
		let baseURL = "https://epac.riddimsoftware.com/app?date=\(hansard.date.ISO8601Format())&subjectID=\(subject.hansardID)"
		let url: URL
		if didFinish {
			url = URL(string: baseURL)!
		} else if let nav = navigator.navigator, let firstMessage = nav.speech.messages.first {
			url = URL(string: "\(baseURL)&speechID=\(nav.speech.hansardID)&messageID=\(firstMessage.hansardID)")!
		} else {
			url = URL(string: baseURL)!
		}

		let shareView = MultiMessageShareView(messages: last5, speakers: speakers, parliamentNumber: hansard.parliamentNumber, subjectTitle: subject.title, date: hansard.date)
		let renderer = ImageRenderer(content: shareView)
		renderer.scale = UIScreen.main.scale
		if let image = renderer.uiImage {
			let source = ShareActivityItemSource(image: image, title: subject.title, url: url)
			return ActivityItem(items: source, url)
		} else {
			return ActivityItem(items: url)
		}
	}

	private func createMessageView(_ message: Message, speaker: ParliamentMember, subject: SubjectOfBusiness, hansard: Hansard) -> some View {
		VStack(alignment: .leading, spacing: 16) {
			VStack(alignment: .leading, spacing: 4) {
				Text(subject.title)
					.font(.system(.headline, design: .rounded))
					.foregroundStyle(.gray)
				Text(hansard.date.formatted(date: .long, time: .omitted))
					.font(.system(.subheadline, design: .rounded))
					.foregroundStyle(.gray.opacity(0.8))
			}
			.padding(.bottom, 8)

			HStack(alignment: .bottom) {
				if message.user.isCurrentUser {
					Spacer()
				}
				if !message.user.isCurrentUser {
					SpeakerImageView(speaker: speaker, parliamentNumber: hansard.parliamentNumber)
				}
				VStack(alignment: message.user.isCurrentUser ? .trailing : .leading) {
					VStack(alignment: .leading, spacing: 4) {
						VStack(alignment: .leading, spacing: 0) {
							Text(speaker.name)
								.font(.system(.caption, design: .rounded, weight: .bold))
							Text("\(speaker.riding), \(speaker.province.rawValue)")
								.font(.system(.caption2, design: .rounded))
						}
						.foregroundStyle(.white.opacity(0.8))
						Text(verbatim: message.text)
							.lineSpacing(4)
					}
					.padding(10)
					.background(message.user.isCurrentUser ? Color(UIColor.darkGray) : Color(UIColor.gray))
					.cornerRadius(10)
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
		.frame(width: 400)
	}
}


	