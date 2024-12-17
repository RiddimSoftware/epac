//
//  SpeechView2.swift
//  epac
//
//  Created by Sunny on 2024-12-16.
//

import SwiftUI
import ExyteChat

struct SpeechView2: View {
	let subject: SubjectOfBusiness
	@State var speeches: [Speech]
	@State private var index: Int = 0
	@State var messages = [Message]()
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
	init(subject: SubjectOfBusiness, messages: [Message] = [], index: Int = 0) {
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
							Spacer()
							VStack {
								if let name = message.user.name.split(separator: "(").first?.trimmingCharacters(in: .whitespaces) {
										Text(verbatim: name)
									.font(.system(.footnote, design: .default, weight: .regular))
								}
								if let riding = message.user.name.split(separator: "(").last?.trimmingCharacters(in: .whitespaces).dropLast() {
									Text(verbatim: String(riding))
										.font(.system(.footnote, design: .default, weight: .regular))
								}
							}
							Spacer()
						}
						if let name = message.user.name.split(separator: "(").first, let last = name.split(separator: /\s/).last, let first = name.split(separator: /\s/).first, last != first {
							AsyncImage(
								url: PhotoProvider.getPhotoURL(lastName: String(last), firstName: String(first), partyAbbreviation: message.user.id)) { image in
									image
										.resizable()
										.scaledToFit()
									//										.frame(width: 142, height: 230)
										.frame(width: 46, height: 77)
								} placeholder: {
									Image(systemName: "person.circle.fill")
								}
						} else {
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
								messages.append(Message(speech.messages.first!))
								index = 1
							}
						}
					} else {
						let speech = speeches.first!
						withAnimation {
							messages.append(Message(speech.messages[index]))
							index += 1
						}
					}
				}
		)
		.task {
			do {
				try await Task.sleep(nanoseconds: 700_000_000)
				withAnimation {
					let message = Message(speeches.first!.messages.first!)
					messages.append(message)
					index += 1
				}
			} catch {
				print("Failed to sleep 0.7s \(error.localizedDescription)")
			}
		}
		.onAppear {
			print(PhotoProvider.getPhotoURL(lastName: "Trudeau", firstName: "Justin", partyAbbreviation: "Lib"))
		}
	}
}

extension Message {
	init(_ message: SpeechMessage) {
		let speaker = message.speaker
		let user = User(id: speaker.party.abbreviation, name: "\(speaker.name) (\(speaker.riding))", avatarURL: speaker.photoURL, isCurrentUser: false)
		self.init(id: message.hansardID, user: user, createdAt: message.timestamp, text: message.content)
	}
}

#Preview {
	SpeechView2(
		subject: .init(
			title: "Government Policies",
			hansardID: "13061430",
			speeches: [
				Speech(
					messages: [
						.init(speaker: .init(name: "Shannon Stubbs", riding: "Lakeland", party: Party.partyWithAbbreviation("CPC")), hansardID: "8784879", content: "Mr. Speaker, after nine years, Canadians are paying the price for the NDP-Liberals' economic vandalism. The carbon tax and job-killing oil and gas cap hurt rural people and non-profits the most.", timestamp: .now),
						.init(speaker: .init(name: "Shannon Stubbs", riding: "Lakeland", party: Party.partyWithAbbreviation("CPC")), hansardID: "8784879", content: "The Dewberry Agricultural Society paid over $5,000 in carbon taxes in just six months and cannot afford to heat its hockey rink much longer. The NDP-Liberals said small business owners are tax cheats. The reckless capital gains tax hike and shameless, temporary two-month tax trick prove it.", timestamp: .now),
						.init(speaker: .init(name: "Shannon Stubbs", riding: "Lakeland", party: Party.partyWithAbbreviation("CPC")), hansardID: "8784879", content: "Sheryl, an accountant from Vegreville, says the tax hike will slash nearly 10% of savings when owners sell their life's work and the labours of love they rely on for their retirement. Ron from Glendon says the cost to switch his store's items to be GST-exempt and back could cripple his business at the most important time of year.", timestamp: .now),
						.init(speaker: .init(name: "Shannon Stubbs", riding: "Lakeland", party: Party.partyWithAbbreviation("CPC")), hansardID: "8784879", content: "Canada's promise is that anyone from anywhere can work hard for a powerful paycheque and pension, living in safe and healthy communities, but the NDP-Liberals broke it. Common-sense Conservatives will restore it, axe the tax, spike the hike and turn hurt into hope for all.", timestamp: .now)
					],
					hansardID: "13061431",
					date: .now,
					title: "Government Policies"
				)
			]
		),
		messages: [],
		index: 0
	)
}
