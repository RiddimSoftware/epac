//
//  SpeechView2.swift
//  epac
//
//  Created by Sunny on 2024-12-16.
//

import SwiftUI
import ExyteChat
import SwiftData
import ActivityView

struct SpeechView: View {
	@Environment(\.modelContext) var modelContext
	@Environment(\.colorScheme) var colorScheme
	let subject: SubjectOfBusiness
	let length: Int
	@State var speeches: [Speech]
	@State private var index: Int = 0
	@State var messages = [ChatMessage]()
	@State var didFinish = false
	@State var isResuming = false
	@State private var item: ActivityItem?


	init(subject: SubjectOfBusiness) {
		self.subject = subject
		let speeches = subject.speeches.map { speech in
			let speech = speech
			speech.messages = speech.messages.sorted(by: { $0.hansardID < $1.hansardID })
			return speech
		}.sorted(by: { $0.hansardID < $1.hansardID })
		self.speeches = speeches
		self.length = speeches.map { $0.messages.count }.reduce(0, +)
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
			Text(verbatim: subject.title)
				.multilineTextAlignment(.center)
			ProgressView(value: Float(messages.count), total: Float(length))
				.progressViewStyle(.linear)
				.frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1, alignment: .center)
			ChatView(messages: messages) { _ in
				/// didSendMessage
			}
			messageBuilder: { message, positionInGroup, positionInCommentsGroup, showContextMenuClosure, messageActionClosure, showAttachmentClosure in
				HStack(alignment: .bottom) {
					if message.user.isCurrentUser {
						Spacer()
					}
					if (positionInGroup == .last || positionInGroup == .single) && !message.user.isCurrentUser, let speaker = (message as? ChatMessage)?.speaker {
						SpeakerImageView(speaker: speaker)
					} else {
						Spacer(minLength: 51)
					}
					VStack(alignment: message.user.isCurrentUser ? .trailing : .leading) {
						HStack {
							VStack(alignment: .leading) {
								Text(verbatim: message.text)
									.padding(10)
									.background(message.user.isCurrentUser ? Color(UIColor.darkGray) : Color(UIColor.gray) )
									.cornerRadius(10)
									.foregroundStyle(.white)
							}
							Button {
								if let image = ImageRenderer(content: createMessageView((message as! ChatMessage), speaker: (message as! ChatMessage).speaker))
									.uiImage {
									self.item = ActivityItem(
										items: image
									)
								}
							} label: {
								Image(systemName: "square.and.arrow.up")
							}
						}
						if (positionInGroup == .last || positionInGroup == .single) {
							if let speaker = (message as? ChatMessage)?.speaker {
								SpeakerNameView(speaker: speaker, alignment: message.user.isCurrentUser ? .trailing : .leading)
							}
						}
					}
					if (positionInGroup == .last || positionInGroup == .single) && message.user.isCurrentUser, let speaker = (message as? ChatMessage)?.speaker {
						SpeakerImageView(speaker: speaker)
					} else {
						Spacer(minLength: 51)
					}
					if !message.user.isCurrentUser {
						Spacer()
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
			.betweenListAndInputViewBuilder({
				Text("Tap anywhere to continue")
					.foregroundStyle(.gray)
					.font(.system(.callout, design: .rounded, weight: .regular))
					.opacity(messages.count < 2 || isResuming ? 1 : 0)
			})
			.chatTheme(
				colors: .init(
					mainBackground: Color(UIColor.systemBackground),
					myMessage: Color(UIColor.systemBlue),
					friendMessage: Color(UIColor.systemGray6),
					textLightContext: Color(UIColor.lightText),
					textDarkContext: Color(UIColor.darkText)
				)
			)
			if didFinish {
				Text("End")
					.font(.system(.callout, design: .rounded, weight: .regular))
			}
		}
		.simultaneousGesture(
			TapGesture()
				.onEnded {
					nextMessage()
				}
		)
		.task {
			guard self.messages.isEmpty else {
				return
			}
			do {
				try await Task.sleep(nanoseconds: 700_000_000)
				guard self.messages.isEmpty else {
				 return
			 }
				withAnimation {
					nextMessage()
				}
			} catch {
				print("Failed to sleep 0.7s \(error.localizedDescription)")
			}
		}
		.onAppear {
			if let currentSpeech = subject.currentSpeech {
				withAnimation {
					isResuming = true
				}
				index = 0
				var speech: Speech!
				while !speeches.isEmpty {
					speech = speeches.first!
					if speech != currentSpeech {
						for _ in 0..<speech.messages.count {
							nextMessage()
						}
					} else {
						break
					}
					_ = speeches.removeFirst()
					index = 0
				}
				var message: ChatMessage?
				if let currentMessage = speech.currentMessage {
					message = self.messages.last
					while index < speech.messages.count && message?.message.hansardID != currentMessage.hansardID {
						nextMessage()
						message = messages.last!
					}
				}
			}
		}
		.activitySheet($item)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					withAnimation {
						messages.removeAll()
						index = 0
						self.speeches = subject.speeches.map { speech in
							let speech = speech
							speech.messages = speech.messages.sorted(by: { $0.hansardID < $1.hansardID })
							return speech
						}.sorted(by: { $0.hansardID < $1.hansardID })
					}
					Task {
						do {
							try await Task.sleep(nanoseconds: 700_000_000)
							nextMessage()
						} catch {

						}
					}
				} label: {
					Image(systemName: "arrow.clockwise")
				}

			}
		}
	}

	private func nextMessage() {
		guard !speeches.isEmpty else {
			return
		}
		isResuming = false
		let speech: Speech
		if speeches.first!.messages.count == index {
			// end of speech
			if speeches.count > 1 {
				index = 0
				_ = speeches.removeFirst()
				speech = speeches.first!
			} else {
				didFinish = true
				subject.currentSpeech?.currentMessage = nil
				subject.currentSpeech = nil
				return
			}
		} else {
			speech = speeches.first!
		}
		subject.currentSpeech = speech
		let message = speech.messages[index]
		speech.currentMessage = message
		let firstName = message.firstName
		let lastName = message.lastName
		var speaker = try? modelContext.fetch(
			FetchDescriptor<ParliamentMember>(
				predicate: #Predicate { $0.firstName == firstName && $0.lastName == lastName }
			)
		).first
		if speaker == nil {
			speaker = ParliamentMember(
				name: message.firstName + " " + message.lastName,
				lastName: message.lastName,
				firstName: message.firstName,
				photoURL: PhotoProvider.getPhotoURL(lastName: message.lastName, firstName: message.firstName, party: .independent),
				riding: "",
				province: .Ontario,
				party: .independent
			)
		}
		var isCurrentUser: Bool
		if let last = messages.last {
			isCurrentUser = last.user.isCurrentUser
		} else {
			isCurrentUser = speaker!.party == .liberal
		}
		if let last = messages.last, speaker != last.speaker {
			isCurrentUser.toggle()
		}
		messages.append(ChatMessage(message, speaker!, isCurrentUser))
		index += 1
	}

	private func createMessageView(_ message: ChatMessage, speaker: ParliamentMember) -> some View {
		HStack(alignment: .bottom) {
			Spacer()
			VStack(alignment: .trailing) {
				HStack {
					VStack(alignment: .leading) {
						Text(verbatim: message.text)
							.padding(10)
							.background(Color(UIColor.gray) )
							.cornerRadius(10)
							.foregroundStyle(.white)
							.frame(width: 468)
					}
				}
				SpeakerNameView(speaker: speaker, alignment: message.user.isCurrentUser ? .trailing : .leading)
			}
			SpeakerImageView(speaker: speaker)
		}
		.padding()
		.background(.white)
		.fixedSize()
		.padding()
	}
}

class ChatUser: User {
	init(_ speaker: ParliamentMember, isCurrentUser: Bool) {
		super.init(
			id: "\(speaker.persistentModelID)",
			name: speaker.name,
			avatarURL: speaker.photoURL,
			isCurrentUser: isCurrentUser
		)
	}
	required init(from decoder: any Decoder) throws {
		fatalError("init(from:) has not been implemented")
	}
}

class ChatMessage: Message {
	var message: SpeechMessage
	var speaker: ParliamentMember
	init(_ message: SpeechMessage, _ speaker: ParliamentMember, _ isCurrentUser: Bool) {
		self.message = message
		self.speaker = speaker
		super.init(
			id: message.hansardID,
			user: ChatUser(speaker, isCurrentUser: isCurrentUser),
			createdAt: message.timestamp,
			text: message.content
		)
	}
}
