//
//  SpeechView2.swift
//  epac
//
//  Created by Sunny on 2024-12-16.
//

import SwiftUI
import ExyteChat
import SwiftData

struct SpeechView2: View {
	@Environment(\.modelContext) var modelContext
	let subject: SubjectOfBusiness
	@State var speeches: [Speech]
	@State private var index: Int = 0
	@State var messages = [ChatMessage]()
	@State var didFinish = false

	init(subject: SubjectOfBusiness) {
		self.subject = subject
		self.speeches = subject.speeches.map { speech in
			let speech = speech
			speech.messages = speech.messages.sorted(by: { $0.hansardID < $1.hansardID })
			return speech
		}.sorted(by: { $0.hansardID < $1.hansardID })
	}
#if DEBUG
	init(subject: SubjectOfBusiness, messages: [ChatMessage] = [], index: Int = 0) {
		self.init(subject: subject)
		self.messages = messages
		self.index = index
	}
#endif

	var body: some View {
		VStack {
			ChatView(messages: messages) { _ in
				/// didSendMessage
			}
			messageBuilder: { message, positionInGroup, positionInCommentsGroup, showContextMenuClosure, messageActionClosure, showAttachmentClosure in
				VStack {
					HStack(alignment: .bottom) {
						VStack(alignment: .leading) {
							Text(verbatim: message.text)
								.padding(10)
								.background(Color(UIColor.systemGray6))
								.cornerRadius(10)
						}
					}
					if positionInGroup ==  .last || positionInGroup == .single {
						if let speaker = (message as? ChatMessage)?.speaker, let chatMessage = (message as? ChatMessage)?.message {
							SpeakerView(speaker: speaker, message: chatMessage)
						}
					}
				}
				.padding()
			}
			inputViewBuilder: { text, attachments, inputViewState, inputViewStyle, inputViewActionClosure, dismissKeyboardClosure in
				EmptyView()
			}
			.showMessageMenuOnLongPress(false)
			.showMessageTimeView(false)
			.showNetworkConnectionProblem(false)
			.chatTheme(
				colors: .init(
					mainBackground: Color(UIColor.systemBackground),
					myMessage: Color(UIColor.systemBlue),
					friendMessage: Color(UIColor.systemGray6),
					textLightContext: Color(UIColor.lightText),
					textDarkContext: Color(UIColor.darkText)
				)
			)
		}
		.simultaneousGesture(
			TapGesture()
				.onEnded {
					if index > 0, speeches.first!.messages.count == index {
						if speeches.count > 1 {
							_ = speeches.removeFirst()
							let speech = speeches.first!
							withAnimation {
								let message = speech.messages.first!
								let firstName = message.firstName
								let lastName = message.lastName
								let speaker = try? modelContext.fetch(
									FetchDescriptor<ParliamentMember>(
										predicate: #Predicate { $0.firstName == firstName && $0.lastName == lastName }
									)
								).first
								if let speaker {
									messages.append(ChatMessage(message, speaker))
									index = 1
								}
							}
						}
					} else {
						let speech = speeches.first!
						withAnimation {
							let message = speech.messages[index]
							let firstName = message.firstName
							let lastName = message.lastName
							let speaker = try? modelContext.fetch(
								FetchDescriptor<ParliamentMember>(
									predicate: #Predicate { $0.firstName == firstName && $0.lastName == lastName }
								)
							).first
							if let speaker {
								messages.append(ChatMessage(message, speaker))
								index += 1
							}
						}
					}
				}
		)
		.task {
			do {
				try await Task.sleep(nanoseconds: 700_000_000)
				withAnimation {
					let message = speeches.first!.messages.first!
					let firstName = message.firstName
					let lastName = message.lastName
					let speaker = try? modelContext.fetch(
						FetchDescriptor<ParliamentMember>(
							predicate: #Predicate { $0.firstName == firstName && $0.lastName == lastName }
						)
					).first
					if let speaker {
						messages.append(ChatMessage(message, speaker))
						index += 1
					}
				}
			} catch {
				print("Failed to sleep 0.7s \(error.localizedDescription)")
			}
		}
	}
}

class ChatUser: User {
	init(_ speaker: ParliamentMember) {
		super.init(
			id: "\(speaker.persistentModelID)",
			name: speaker.name,
			avatarURL: speaker.photoURL,
			isCurrentUser: speaker.party == .liberal
		)
	}
	required init(from decoder: any Decoder) throws {
		fatalError("init(from:) has not been implemented")
	}
}

class ChatMessage: Message {
	var message: SpeechMessage
	var speaker: ParliamentMember
	init(_ message: SpeechMessage, _ speaker: ParliamentMember) {
		self.message = message
		self.speaker = speaker
		super.init(
			id: message.hansardID,
			user: ChatUser(speaker),
			createdAt: message.timestamp,
			text: message.content
		)
	}
}
