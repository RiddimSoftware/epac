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
import Observation

struct SpeechView: View {
	@Environment(\.modelContext) var modelContext
	@Environment(\.colorScheme) var colorScheme
	@Environment(NavigationRouter.self) var router
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
			messageBuilder: { message, positionInGroup, positionInMessagesSection, positionInCommentsGroup, showContextMenuClosure, messageActionClosure, showAttachmentClosure in
				HStack(alignment: .bottom) {
					if message.user.isCurrentUser {
						Spacer()
					}
					if (positionInGroup == .last || positionInGroup == .single) && !message.user.isCurrentUser, let speaker = viewModel.speakers[message.id] {
						SpeakerImageView(speaker: speaker, parliamentNumber: hansard.parliamentNumber)
							.onTapGesture {
								router.selectedMember = speaker
								router.selectedTab = .members
							}
					} else {
						Spacer(minLength: 51)
					}
					VStack(alignment: message.user.isCurrentUser ? .trailing : .leading) {
						HStack {
							VStack(alignment: .leading, spacing: 4) {
								if let speaker = viewModel.speakers[message.id] {
									VStack(alignment: .leading, spacing: 0) {
										Text(speaker.name)
											.font(.system(size: 12, weight: .bold, design: .rounded))
										Text("\(speaker.riding), \(speaker.province.rawValue)")
											.font(.system(size: 10, weight: .regular, design: .rounded))
									}
									.foregroundStyle(.white.opacity(0.8))
								}
								Text(verbatim: message.text)
									.lineSpacing(4)
							}
							.padding(10)
							.background(message.user.isCurrentUser ? Color(UIColor.darkGray) : Color(UIColor.gray) )
							.cornerRadius(10)
							.foregroundStyle(.white)
						}
					}
					// TODO: Why is the context menu rotating the bubble 180 vertically when long pressing?
//					.contextMenu {
//						Button {
//							shareMessage(message)
//						} label: {
//							Label("Share", systemImage: "square.and.arrow.up")
//						}
//					}
					if (positionInGroup == .last || positionInGroup == .single) && message.user.isCurrentUser, let speaker = viewModel.speakers[message.id] {
						SpeakerImageView(speaker: speaker, parliamentNumber: hansard.parliamentNumber)
							.onTapGesture {
								router.selectedMember = speaker
								router.selectedTab = .members
							}
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
					mainBG: Color(UIColor.systemBackground),
					messageMyBG: Color(UIColor.systemBlue),
					messageFriendBG: Color(UIColor.systemGray6)
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
			guard viewModel.messages.isEmpty else { return }
			let savedSpeechID = subject.currentSpeechID ?? subject.currentSpeech?.hansardID
			let savedMessageID = subject.currentSpeech?.currentMessageID ?? subject.currentSpeech?.currentMessage?.hansardID
			
			if let savedSpeechID {
				while !viewModel.didFinish && (navigator.navigator == nil || navigator.navigator?.speech.hansardID != savedSpeechID) {
					nextMessage()
				}
				if let savedMessageID {
					// Load messages until we reach the saved message ID
					while !viewModel.didFinish && viewModel.messages.last?.id != savedMessageID {
						nextMessage()
					}
				}
				withAnimation {
					viewModel.isResuming = !viewModel.didFinish
				}
			}
		}
		.activitySheet($item)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					withAnimation {
						viewModel.messages.removeAll()
						viewModel.speakers.removeAll()
						viewModel.didFinish = false
						subject.currentSpeech?.currentMessage = nil
						subject.currentSpeech?.currentMessageID = nil
						subject.currentSpeech = nil
						subject.currentSpeechID = nil
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
					shareLast5Messages()
				} label: {
					Image(systemName: "square.and.arrow.up")
				}
			}
		}
	}

	@MainActor
	private func shareMessage(_ message: Message) {
		guard let speaker = viewModel.speakers[message.id] else { return }
		let renderer = ImageRenderer(content: createMessageView(message, speaker: speaker))
		renderer.scale = UIScreen.main.scale
		if let image = renderer.uiImage {
			let source = ShareActivityItemSource(image: image, title: subject.title)
			self.item = ActivityItem(items: source)
		}
	}

	@MainActor
	private func shareLast5Messages() {
		let last5 = Array(viewModel.messages.suffix(5))
		let url: URL
		if viewModel.didFinish {
			url = URL(string: "https://epac.riddimsoftware.com/app?date=\(hansard.date.ISO8601Format())&subjectID=\(subject.hansardID)")!
		} else {
			url = URL(string: "https://epac.riddimsoftware.com/app?date=\(hansard.date.ISO8601Format())&subjectID=\(subject.hansardID)&speechID=\(navigator.navigator!.speech.hansardID)&messageID=\(navigator.navigator!.speech.messages.first!.hansardID)")!
		}

		let shareView = MultiMessageShareView(messages: last5, speakers: viewModel.speakers, parliamentNumber: hansard.parliamentNumber, subjectTitle: subject.title, date: hansard.date)
		let renderer = ImageRenderer(content: shareView)
		renderer.scale = UIScreen.main.scale
		if let image = renderer.uiImage {
			let source = ShareActivityItemSource(image: image, title: subject.title, url: url)
			self.item = ActivityItem(items: source, url)
		} else {
			self.item = ActivityItem(items: url)
		}
	}

	private func nextMessage() {
		viewModel.isResuming = false
		guard !viewModel.didFinish else {
			return
		}
		guard let message = navigator.next() else {
			viewModel.didFinish = true
			return
		}

		if let currentSpeech = navigator.navigator?.speech {
			subject.currentSpeech = currentSpeech
			subject.currentSpeechID = currentSpeech.hansardID
			currentSpeech.currentMessage = message
			currentSpeech.currentMessageID = message.hansardID
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
			modelContext.insert(speaker!)
			try? modelContext.save()
		}
		var isCurrentUser: Bool
		if let last = viewModel.messages.last {
			isCurrentUser = last.user.isCurrentUser
		} else {
			isCurrentUser = speaker!.party == .liberal
		}
		if let last = viewModel.messages.last, let lastSpeaker = viewModel.speakers[last.id], speaker != lastSpeaker {
			isCurrentUser.toggle()
		}

		let chatMessage = Message(
			id: message.hansardID,
			user: User(
				id: "\(speaker!.persistentModelID)",
				name: speaker!.name,
				avatarURL: speaker!.photoURL,
				isCurrentUser: isCurrentUser
			),
			createdAt: message.timestamp,
			text: message.content
		)
		viewModel.append(chatMessage, speaker: speaker!)
	}

	    private func createMessageView(_ message: Message, speaker: ParliamentMember) -> some View {
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
									.font(.system(size: 12, weight: .bold, design: .rounded))
								Text("\(speaker.riding), \(speaker.province.rawValue)")
									.font(.system(size: 10, weight: .regular, design: .rounded))
							}
							.foregroundStyle(.white.opacity(0.8))
							Text(verbatim: message.text)
								.lineSpacing(4)
						}
						.padding(10)
						.background(message.user.isCurrentUser ? Color(UIColor.darkGray) : Color(UIColor.gray) )
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
	        .background(Color(UIColor.systemBackground))
	        .fixedSize(horizontal: false, vertical: true)
			.frame(width: 400)
	    }
}

struct MultiMessageShareView: View {
	let messages: [Message]
	let speakers: [String: ParliamentMember]
	let parliamentNumber: Int
	let subjectTitle: String
	let date: Date

	struct MessageGroup: Identifiable {
		let id: String
		let speaker: ParliamentMember
		let isCurrentUser: Bool
		var texts: [String]
	}

	var groupedMessages: [MessageGroup] {
		var groups: [MessageGroup] = []
		for message in messages {
			guard let speaker = speakers[message.id] else { continue }
			if let lastIndex = groups.indices.last, groups[lastIndex].speaker.name == speaker.name {
				groups[lastIndex].texts.append(message.text)
			} else {
				groups.append(MessageGroup(id: message.id, speaker: speaker, isCurrentUser: message.user.isCurrentUser, texts: [message.text]))
			}
		}
		return groups
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			VStack(alignment: .leading, spacing: 4) {
				Text(subjectTitle)
					.font(.system(.headline, design: .rounded))
					.foregroundStyle(.gray)
				Text(date.formatted(date: .long, time: .omitted))
					.font(.system(.subheadline, design: .rounded))
					.foregroundStyle(.gray.opacity(0.8))
			}
			.padding(.bottom, 8)

			ForEach(groupedMessages) { group in
				HStack(alignment: .bottom) {
					if !group.isCurrentUser {
						SpeakerImageView(speaker: group.speaker, parliamentNumber: parliamentNumber)
					} else {
						Spacer()
					}

					VStack(alignment: group.isCurrentUser ? .trailing : .leading, spacing: 4) {
						if !group.isCurrentUser {
							VStack(alignment: .leading, spacing: 0) {
								Text(group.speaker.name)
									.font(.system(size: 12, weight: .bold, design: .rounded))
								Text("\(group.speaker.riding), \(group.speaker.province.rawValue)")
									.font(.system(size: 10, weight: .regular, design: .rounded))
							}
							.foregroundStyle(.white.opacity(0.8))
						}

						VStack(alignment: .leading, spacing: 4) {
							ForEach(group.texts, id: \.self) { text in
								Text(verbatim: text)
									.lineSpacing(4)
							}
						}
						.padding(10)
						.background(group.isCurrentUser ? Color(UIColor.darkGray) : Color(UIColor.gray))
						.cornerRadius(10)
						.foregroundStyle(.white)
					}

					if group.isCurrentUser {
						SpeakerImageView(speaker: group.speaker, parliamentNumber: parliamentNumber)
					} else {
						Spacer()
					}
				}
			}
		}
		.padding()
		.background(Color(UIColor.systemBackground))
		.fixedSize(horizontal: false, vertical: true)
		.frame(width: 400)
	}
}
