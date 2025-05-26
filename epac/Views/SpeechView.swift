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
	@EnvironmentObject var fetch: Fetch
	@State var navigator: SubjectNavigator

	let hansard: Hansard
	let subject: SubjectOfBusiness
	let length: Int

	@State var viewModel: SpeechViewModel
	@State private var item: ActivityItem?

	init(hansard: Hansard, subject: SubjectOfBusiness) {
		self.hansard = hansard
		self.subject = subject
		navigator = SubjectNavigator(subject)
		self.length = subject.speeches.map { $0.messages.count }.reduce(0, +)
		self.viewModel = SpeechViewModel()
	}
//#if DEBUG
//	init(hansard: Hansard, subject: SubjectOfBusiness, messages: [ChatMessage] = []) {
//		self.init(hansard: hansard, subject: subject)
//		self.messages = messages
//	}
//#endif

	var body: some View {
		VStack {
			Text(verbatim: subject.title)
				.multilineTextAlignment(.center)
			ProgressView(value: Float(viewModel.messages.count), total: Float(length))
				.progressViewStyle(.linear)
				.frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1, alignment: .center)
			ChatView(messages: viewModel.messages) { _ in
				/// didSendMessage
			}
			messageBuilder: { message, positionInGroup, positionInCommentsGroup, showContextMenuClosure, messageActionClosure, showAttachmentClosure in
				HStack(alignment: .bottom) {
					if message.user.isCurrentUser {
						Spacer()
					}
					if (positionInGroup == .last || positionInGroup == .single) && !message.user.isCurrentUser, let speaker = (message as? ChatMessage)?.speaker {
						SpeakerImageView(speaker: speaker, parliamentNumber: hansard.parliamentNumber)
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
						SpeakerImageView(speaker: speaker, parliamentNumber: hansard.parliamentNumber)
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
					.opacity(viewModel.tapAnywhereOpacity)
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
			if viewModel.didFinish {
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
			guard viewModel.messages.isEmpty else {
				return
			}
			do {
				try await Task.sleep(nanoseconds: 700_000_000)
				guard viewModel.messages.isEmpty else {
				 return
			 }
				withAnimation {
					nextMessage()
				}
			} catch {
				Log.debug("Failed to sleep 0.7s \(error.localizedDescription)")
			}
		}
		.onAppear {
			/// TODO: Deal with resuming a speech using SubjectNavigator
			if let currentSpeech = subject.currentSpeech {
				while navigator.navigator?.speech.hansardID != currentSpeech.hansardID {
					nextMessage()
				}
				withAnimation {
					viewModel.isResuming = true
				}
//				if let currentMessage = currentSpeech.currentMessage {
//					if let speechNav = navigator.navigator {
//						while speechNav.speech.messages[speechNav.index].hansardID != currentMessage.hansardID {
//							nextMessage()
//						}
//					}
//				}
			}
		}
		.activitySheet($item)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					withAnimation {
						viewModel.messages.removeAll()
						navigator.reset()
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
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					if viewModel.didFinish {
						let url = URL(string: "https://epac.riddimsoftware.com/app?date=\(hansard.date.ISO8601Format())&subjectID=\(subject.hansardID)")!
						self.item = ActivityItem(
							items: url
						)
					} else {
//						let url = URL(string: "https://epac.riddimsoftware.com/app?date=\(hansard.date.ISO8601Format())&subjectID=\(subject.hansardID)&speechID=\(speeches.first!.hansardID)&messageID=\(speeches.first!.messages.first!.hansardID)")!
//						self.item = ActivityItem(
//							items: url
//						)
					}
				} label: {
					Image(systemName: "square.and.arrow.up")
				}
			}
		}
	}

	private func nextMessage() {
		guard !viewModel.didFinish else {
			return
		}
		guard let message = navigator.next() else {
			viewModel.didFinish = true
			return
		}

		let firstName = message.firstName
		let lastName = message.lastName
		var speaker = try? modelContext.fetch(
			FetchDescriptor<ParliamentMember>(
				predicate: #Predicate { $0.firstName == firstName && $0.lastName == lastName }
			)
		).first
		if speaker == nil {
			Task {
				try? await fetch.downloadMember(firstName, lastName)
			}
			let provider = PhotoProvider(parliamentNumber: hansard.parliamentNumber)
			let riding = message.ridingName
			let constituency = try? modelContext.fetch(
				FetchDescriptor<Constituency>(
					predicate: #Predicate { !riding.isEmpty && ($0.name == riding || $0.name.starts(with: riding)) }
				)
			).first
			speaker = ParliamentMember(
				name: message.firstName + " " + message.lastName,
				lastName: message.lastName,
				firstName: message.firstName,
				photoURL: provider.getPhotoURL(lastName: message.lastName, firstName: message.firstName, party: Party.partyWithAbbreviation(message.partyAbbreviation)),
				riding: constituency?.name ?? riding,
				province: constituency?.province ?? .Ontario,
				party: Party.partyWithAbbreviation(message.partyAbbreviation)
			)
		}
		var isCurrentUser: Bool
		if let last = viewModel.messages.last {
			isCurrentUser = last.user.isCurrentUser
		} else {
			isCurrentUser = speaker!.party == .liberal
		}
		if let last = viewModel.messages.last, speaker != last.speaker {
			isCurrentUser.toggle()
		}
		viewModel.append(ChatMessage(message, speaker!, isCurrentUser))
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
			SpeakerImageView(speaker: speaker, parliamentNumber: hansard.parliamentNumber)
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
