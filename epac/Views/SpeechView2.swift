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
						HStack {
							if message.user.isCurrentUser {
								Spacer()
							}
							VStack {
								HStack {
									if message.user.isCurrentUser {
										if let image = (message as? ChatMessage)?.speaker.party.image {
											Image(uiImage: image)
												.resizable()
												.frame(width: 40, height: 40)
										}
									}
									VStack {
										if let name = (message as? ChatMessage)?.speaker.name {
											Text(verbatim: name)
										}
										if let riding = (message as? ChatMessage)?.speaker.riding {
											Text(verbatim: riding)
										}
										if let province = (message as? ChatMessage)?.speaker.province {
											Text(verbatim: province.rawValue)
										}
									}
									if !message.user.isCurrentUser {
										if let image = (message as? ChatMessage)?.speaker.party.image {
											Image(uiImage: image)
												.resizable()
												.frame(width: 40, height: 40)
										}
									}
								}
								HStack {
									if let url = (message as? ChatMessage)?.speaker.photoURL {
										AsyncImage(url: url) { image in
											image
												.resizable()
												.scaledToFit()
											//										.frame(width: 142, height: 230)
												.frame(width: 46, height: 77)
										} placeholder: {
											Image(systemName: "person.circle.fill")
										}
									} else {
										Image(systemName: "person.circle.fill")
									}
								}
							}
							.font(.system(.footnote, design: .default, weight: .regular))
							if !message.user.isCurrentUser {
								Spacer()
							}
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

//#Preview {
//	SpeechView2(
//		subject: .init(
//			title: "Government Policies",
//			hansardID: "13061430",
//			speeches: [
//				Speech(
//					messages: [
//						.init(speaker: .init(name: "Shannon Stubbs", riding: "Lakeland", party: Party.partyWithAbbreviation("CPC")), hansardID: "8784879", content: "Mr. Speaker, after nine years, Canadians are paying the price for the NDP-Liberals' economic vandalism. The carbon tax and job-killing oil and gas cap hurt rural people and non-profits the most.", timestamp: .now),
//						.init(speaker: .init(name: "Shannon Stubbs", riding: "Lakeland", party: Party.partyWithAbbreviation("CPC")), hansardID: "8784879", content: "The Dewberry Agricultural Society paid over $5,000 in carbon taxes in just six months and cannot afford to heat its hockey rink much longer. The NDP-Liberals said small business owners are tax cheats. The reckless capital gains tax hike and shameless, temporary two-month tax trick prove it.", timestamp: .now),
//						.init(speaker: .init(name: "Shannon Stubbs", riding: "Lakeland", party: Party.partyWithAbbreviation("CPC")), hansardID: "8784879", content: "Sheryl, an accountant from Vegreville, says the tax hike will slash nearly 10% of savings when owners sell their life's work and the labours of love they rely on for their retirement. Ron from Glendon says the cost to switch his store's items to be GST-exempt and back could cripple his business at the most important time of year.", timestamp: .now),
//						.init(speaker: .init(name: "Shannon Stubbs", riding: "Lakeland", party: Party.partyWithAbbreviation("CPC")), hansardID: "8784879", content: "Canada's promise is that anyone from anywhere can work hard for a powerful paycheque and pension, living in safe and healthy communities, but the NDP-Liberals broke it. Common-sense Conservatives will restore it, axe the tax, spike the hike and turn hurt into hope for all.", timestamp: .now)
//					],
//					hansardID: "13061431",
//					date: .now,
//					title: "Government Policies"
//				)
//			]
//		),
//		messages: [],
//		index: 0
//	)
//}
