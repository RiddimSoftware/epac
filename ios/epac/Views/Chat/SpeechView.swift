//
//  SpeechView2.swift
//  epac
//
//  Created by Sunny on 2024-12-16.
//

import ActivityView
import ExyteChat
import Observation
import SwiftData
import SwiftUI

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
	@State private var userProvinceCode = ""

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
			consumerPriceIndexDebateContext
			employmentInsuranceDebateContext
			cppOasDebateContext
			ChatView(messages: viewModel.messages) { _ in
				/// didSendMessage
			}
			messageBuilder: { message, positionInGroup, _, _, _, _, _ in
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
			inputViewBuilder: { _, _, _, _, _, _ in
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
			.accessibilityIdentifier("speech-view-scroll")
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
			resolveSavedMemberProvince()
		}
		.activitySheet($item)
		.toolbar {
			ToolbarItem(placement: .topBarLeading) {
				Menu {
					if let url = URL(string: "https://openparliament.ca/debates/\(hansard.parliamentNumber)/\(hansard.sessionNumber)/\(DateUtils.getCSVStringFromDate(hansard.date))/") {
						Link(destination: url) {
							Label(NSLocalizedString("speech.openOpenParliament", comment: ""), systemImage: "safari")
						}
					}
					if let url = ParlVULinkBuilder.houseDebateURL(for: hansard.date) {
						Link(destination: url) {
							Label(NSLocalizedString("speech.watchParlVU", comment: ""), systemImage: "play.rectangle")
						}
					}
				} label: {
					Image(systemName: "link")
				}
				.accessibilityLabel(NSLocalizedString("speech.sourceLinks", comment: ""))
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

	@ViewBuilder
	private var consumerPriceIndexDebateContext: some View {
		if isConsumerPriceIndexRelevant,
		   let cpi = ConsumerPriceIndexStatisticsDatabase.statistic(for: userProvinceCode) {
			VStack(alignment: .leading, spacing: 6) {
				HStack {
					Label("Inflation context", systemImage: "chart.line.uptrend.xyaxis")
						.font(.caption.bold())
					Spacer()
					Text(ConsumerPriceIndexStatisticsDatabase.monthLabel(cpi.referenceMonth))
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
				HStack(spacing: 12) {
					statPill("All-items", yearOverYearLabel(cpi.allItemsYearOverYearPercent))
					statPill("Food", yearOverYearLabel(cpi.foodYearOverYearPercent))
					statPill("Canada", yearOverYearLabel(cpi.nationalAllItemsYearOverYearPercent))
				}
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 10)
			.background(Color(.secondarySystemGroupedBackground))
			.clipShape(RoundedRectangle(cornerRadius: 8))
			.padding(.horizontal)
		}
	}

	@ViewBuilder
	private var employmentInsuranceDebateContext: some View {
		if isEmploymentInsuranceRelevant,
		   let ei = EmploymentInsuranceStatisticsDatabase.statistic(for: userProvinceCode) {
			VStack(alignment: .leading, spacing: 6) {
				HStack {
					Label("EI context", systemImage: "briefcase.fill")
						.font(.caption.bold())
					Spacer()
					Text(EmploymentInsuranceStatisticsDatabase.monthLabel(ei.referenceMonth))
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
				HStack(spacing: 12) {
					statPill("Beneficiaries", ei.beneficiaries.formatted())
					statPill(
						"Avg. benefit",
						ei.averageWeeklyBenefit.formatted(.currency(code: "CAD").precision(.fractionLength(0)))
					)
					if let change = ei.claimsYearOverYearChangePercent {
						statPill("Claims YoY", yearOverYearLabel(change))
					}
				}
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 10)
			.background(Color(.secondarySystemGroupedBackground))
			.clipShape(RoundedRectangle(cornerRadius: 8))
			.padding(.horizontal)
		}
	}

	private var isEmploymentInsuranceRelevant: Bool {
		ParliamentaryTopic.matching(subject.title).contains { $0.id == "labour" }
	}

	private var isConsumerPriceIndexRelevant: Bool {
		let topicIDs = ParliamentaryTopic.matching(subject.title).map(\.id)
		if topicIDs.contains("economy") || topicIDs.contains("agriculture") {
			return true
		}
		let title = subject.title.localizedLowercase
		return title.contains("affordability")
			|| title.contains("cost of living")
			|| title.contains("inflation")
			|| title.contains("grocery")
			|| title.contains("food")
	}

	@ViewBuilder
	private var cppOasDebateContext: some View {
		if isCPPOASRelevant,
		   let stat = CPPOASStatisticsDatabase.statistic(for: userProvinceCode) {
			VStack(alignment: .leading, spacing: 6) {
				Label("Pensions context", systemImage: "person.text.rectangle.fill")
					.font(.caption.bold())
				HStack(spacing: 12) {
					if let cpp = stat.cppRetirementRecipients {
						statPill("CPP recipients", cpp.formatted())
					}
					if let oas = stat.oasPensionRecipients {
						statPill("OAS recipients", oas.formatted())
					}
				}
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 10)
			.background(Color(.secondarySystemGroupedBackground))
			.clipShape(RoundedRectangle(cornerRadius: 8))
			.padding(.horizontal)
		}
	}

	private var isCPPOASRelevant: Bool {
		ParliamentaryTopic.matching(subject.title).contains { $0.id == "seniors" }
	}

	private func statPill(_ label: String, _ value: String) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(label)
				.font(.caption2)
				.foregroundStyle(.secondary)
			Text(value)
				.font(.caption.monospacedDigit().weight(.semibold))
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private func resolveSavedMemberProvince() {
		guard userProvinceCode.isEmpty else { return }
		let allMembers = (try? modelContext.fetch(FetchDescriptor<ParliamentMember>())) ?? []
		if let savedName = PostalCodeViewModel.savedMemberName,
		   let member = allMembers.first(where: { $0.name == savedName }) {
			userProvinceCode = member.province.shortCode
			return
		}
		if let savedRiding = PostalCodeViewModel.savedRidingName,
		   let member = allMembers.first(where: { $0.riding == savedRiding }) {
			userProvinceCode = member.province.shortCode
		}
	}

	private func yearOverYearLabel(_ value: Double) -> String {
		if value > 0 {
			return "+\(value.formatted(.number.precision(.fractionLength(1))))%"
		}
		return "\(value.formatted(.number.precision(.fractionLength(1))))%"
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
