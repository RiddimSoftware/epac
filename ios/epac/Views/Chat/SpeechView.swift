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
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(NavigationRouter.self) var router
	@EnvironmentObject var fetch: Fetch
	@State var navigator: SubjectNavigator

	let hansard: Hansard
	let subject: SubjectOfBusiness
	let length: Int

	@State var viewModel: SpeechViewModel
	@State private var item: ActivityItem?
	@State private var followStore = MemberFollowStore.shared

	init(hansard: Hansard, subject: SubjectOfBusiness) {
		self.hansard = hansard
		self.subject = subject
		navigator = SubjectNavigator(subject)
		self.length = subject.speeches.map { $0.messages.count }.reduce(0, +)
		self.viewModel = SpeechViewModel()
	}

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
							.accessibilityAddTraits(.isButton)
							.accessibilityHint("View member profile")
					} else {
						Spacer(minLength: 51)
					}
					VStack(alignment: message.user.isCurrentUser ? .trailing : .leading) {
						HStack {
							VStack(alignment: .leading, spacing: 4) {
								if let speaker = viewModel.speakers[message.id] {
									VStack(alignment: .leading, spacing: 0) {
										Text(speaker.name)
											.font(.system(.caption, design: .rounded).bold())
										Text("\(speaker.riding), \(speaker.province.rawValue)")
											.font(.system(.caption2, design: .rounded))
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
					.contextMenu {
						if let speaker = viewModel.speakers[message.id] {
							Button {
								item = viewModel.shareMessage(message, subject: subject, hansard: hansard)
							} label: {
								Label(NSLocalizedString("speech.share", comment: ""), systemImage: "square.and.arrow.up")
							}
							Button {
								if followStore.isFollowing(speaker.memberID) {
									followStore.unfollow(speaker.memberID)
								} else {
									followStore.follow(speaker.memberID)
								}
							} label: {
								Label(
									followStore.isFollowing(speaker.memberID)
										? String(format: NSLocalizedString("speech.unfollow", comment: ""), speaker.firstName)
										: String(format: NSLocalizedString("speech.follow", comment: ""), speaker.firstName),
									systemImage: followStore.isFollowing(speaker.memberID) ? "person.badge.minus" : "person.badge.plus"
								)
							}
							Button {
								router.selectedMember = speaker
								router.selectedTab = .members
							} label: {
								Label(String(format: NSLocalizedString("speech.goToProfile", comment: ""), speaker.firstName), systemImage: "person.circle")
							}
							Button {
								UIPasteboard.general.string = message.text
							} label: {
								Label(NSLocalizedString("speech.copyQuote", comment: ""), systemImage: "doc.on.doc")
							}
						}
					}
					.accessibilityElement(children: .combine)
					.accessibilityLabel({
						if let speaker = viewModel.speakers[message.id] {
							return "\(speaker.name), \(speaker.party.fullName): \(message.text)"
						}
						return message.text
					}())
					.accessibilityAction(named: NSLocalizedString("speech.copyQuote", comment: "")) {
						UIPasteboard.general.string = message.text
					}
					if (positionInGroup == .last || positionInGroup == .single) && message.user.isCurrentUser, let speaker = viewModel.speakers[message.id] {
						SpeakerImageView(speaker: speaker, parliamentNumber: hansard.parliamentNumber)
							.onTapGesture {
								router.selectedMember = speaker
								router.selectedTab = .members
							}
							.accessibilityAddTraits(.isButton)
							.accessibilityHint("View member profile")
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
					mainBG: Color.appBackground,
					messageMyBG: Color(UIColor.systemBlue),
					messageFriendBG: Color(UIColor.systemGray6)
				)
			)
			if viewModel.didFinish {
				Text("End")
					.font(.system(.callout, design: .rounded, weight: .regular))
			}
			HStack {
				Spacer()
				DataSourceBadge(source: .hansard())
			}
			.padding(.horizontal)
			.padding(.bottom, 4)
		}
		.simultaneousGesture(
			TapGesture()
				.onEnded {
					withAnimation(reduceMotion ? nil : .default) {
						viewModel.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: modelContext, fetch: fetch)
					}
				}
		)
		.task {
			guard viewModel.messages.isEmpty else { return }
			do {
				try await Task.sleep(nanoseconds: 700_000_000)
				guard viewModel.messages.isEmpty else { return }
				withAnimation(reduceMotion ? nil : .default) {
					viewModel.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: modelContext, fetch: fetch)
				}
			} catch {
				Log.debug("Failed to sleep 0.7s \(error.localizedDescription)")
			}
		}
		.onAppear {
			viewModel.prepareResume(navigator: navigator, subject: subject, hansard: hansard, modelContext: modelContext, fetch: fetch)
		}
		.activitySheet($item)
		.toolbar {
			ToolbarItem(placement: .topBarLeading) {
				if let url = URL(string: "https://openparliament.ca/debates/\(hansard.parliamentNumber)/\(hansard.sessionNumber)/\(DateUtils.getCSVStringFromDate(hansard.date))/") {
					Link(destination: url) {
						Image(systemName: "safari")
					}
					.accessibilityLabel("Open in openparliament.ca")
				}
			}
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					withAnimation(reduceMotion ? nil : .default) {
						viewModel.reset(navigator: navigator, subject: subject)
					}
					Task {
						do {
							try await Task.sleep(nanoseconds: 700_000_000)
							viewModel.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: modelContext, fetch: fetch)
						} catch {}
					}
				} label: {
					Image(systemName: "arrow.clockwise")
				}
				.accessibilityLabel("Restart debate")
			}
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					item = viewModel.shareLast5Messages(navigator: navigator, subject: subject, hansard: hansard)
				} label: {
					Image(systemName: "square.and.arrow.up")
				}
				.accessibilityLabel("Share recent messages")
			}
		}
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
									.font(.system(.caption, design: .rounded, weight: .bold))
								Text("\(group.speaker.riding), \(group.speaker.province.rawValue)")
									.font(.system(.caption2, design: .rounded))
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
		.background(Color.appBackground)
		.fixedSize(horizontal: false, vertical: true)
		.frame(width: 400)
	}
}
