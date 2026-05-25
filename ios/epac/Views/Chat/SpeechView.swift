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

private enum SpeechLayout {
	static let speakerPlaceholderWidth: CGFloat = 51
	static let speakerMetadataSpacing = EpacSpacing.xs
	static let speakerMetadataOpacity = 0.8
	static let messageLineSpacing = EpacSpacing.xs
	static let messageBubblePadding: CGFloat = 10
	static let messageBubbleCornerRadius: CGFloat = 10
	static let bottomBadgePadding = EpacSpacing.xs
	static let messageAdvanceDelayNanoseconds: UInt64 = 700_000_000
	static let contextSpacing: CGFloat = 6
	static let contextHorizontalPadding: CGFloat = 12
	static let contextVerticalPadding: CGFloat = 10
	static let contextCornerRadius = EpacCornerRadius.s
	static let statPillSpacing = EpacSpacing.xxs
	static let statPillRowSpacing: CGFloat = 12
	static let statPillColumnSpacing = EpacSpacing.s
	static let shareRootSpacing = EpacSpacing.m
	static let shareHeaderSpacing = EpacSpacing.xs
	static let shareHeaderOpacity = 0.8
	static let shareHeaderBottomPadding = EpacSpacing.s
	static let shareGroupSpacing = EpacSpacing.xs
	static let shareWidth: CGFloat = 400
}

struct SpeechView: View {
	@Environment(\.modelContext) var modelContext
	@Environment(\.colorScheme) var colorScheme
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(NavigationRouter.self) var router
	@EnvironmentObject var fetch: Fetch
	@State private var navigator: SubjectNavigator

	let hansard: Hansard
	let subject: SubjectOfBusiness
	let length: Int

	@State private var viewModel: SpeechViewModel
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
			studentFinanceDebateContext
			correctionsDebateContext
			employmentInsuranceDebateContext
			cppOasDebateContext
			veteransAffairsDebateContext
			transportationSafetyDebateContext
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
								openSpeakerProfile(speaker)
							}
							.accessibilityHidden(true)
					} else {
						Spacer(minLength: SpeechLayout.speakerPlaceholderWidth)
					}
					VStack(alignment: message.user.isCurrentUser ? .trailing : .leading) {
						HStack {
							VStack(alignment: .leading, spacing: SpeechLayout.speakerMetadataSpacing) {
								if let speaker = viewModel.speakers[message.id] {
									VStack(alignment: .leading, spacing: 0) {
										Text(speaker.name)
											.font(.system(.caption, design: .rounded).bold())
										Text("\(speaker.riding), \(speaker.province.rawValue)")
											.font(.system(.caption2, design: .rounded))
									}
									.foregroundStyle(.white.opacity(SpeechLayout.speakerMetadataOpacity))
								}
								Text(verbatim: message.text)
									.lineSpacing(SpeechLayout.messageLineSpacing)
							}
							.padding(SpeechLayout.messageBubblePadding)
							.background(message.user.isCurrentUser ? Color(UIColor.darkGray) : Color(UIColor.gray) )
							.cornerRadius(SpeechLayout.messageBubbleCornerRadius)
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
					.accessibilityLabel(messageAccessibilityLabel(message))
					.accessibilityValue(messageAccessibilityValue(message))
					.accessibilityAddTraits(.isStaticText)
					.accessibilityHint(NSLocalizedString("speech.messageActionsHint", comment: ""))
					.accessibilityAction(named: NSLocalizedString("speech.copyQuote", comment: "")) {
						UIPasteboard.general.string = message.text
					}
					.accessibilityAction(named: NSLocalizedString("View member profile", comment: "")) {
						if let speaker = viewModel.speakers[message.id] {
							openSpeakerProfile(speaker)
						}
					}
					if (positionInGroup == .last || positionInGroup == .single) && message.user.isCurrentUser, let speaker = viewModel.speakers[message.id] {
						SpeakerImageView(speaker: speaker, parliamentNumber: hansard.parliamentNumber)
							.onTapGesture {
								openSpeakerProfile(speaker)
							}
							.accessibilityHidden(true)
					} else {
						Spacer(minLength: SpeechLayout.speakerPlaceholderWidth)
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
					.accessibilityHidden(true)
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
			.padding(.bottom, SpeechLayout.bottomBadgePadding)
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
				try await Task.sleep(nanoseconds: SpeechLayout.messageAdvanceDelayNanoseconds)
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
			ReviewRequestManager.shared.recordDebateThreadRead(
				hansardID: hansard.hansardID,
				subjectTitle: subject.title
			)
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
							try await Task.sleep(nanoseconds: SpeechLayout.messageAdvanceDelayNanoseconds)
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
			VStack(alignment: .leading, spacing: SpeechLayout.contextSpacing) {
				HStack {
					Label("Inflation context", systemImage: "chart.line.uptrend.xyaxis")
						.font(.caption.bold())
					Spacer()
					Text(ConsumerPriceIndexStatisticsDatabase.monthLabel(cpi.referenceMonth))
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
				statPillRow {
					statPill("All-items", yearOverYearLabel(cpi.allItemsYearOverYearPercent))
					statPill("Food", yearOverYearLabel(cpi.foodYearOverYearPercent))
					statPill("Canada", yearOverYearLabel(cpi.nationalAllItemsYearOverYearPercent))
				}
			}
			.padding(.horizontal, SpeechLayout.contextHorizontalPadding)
			.padding(.vertical, SpeechLayout.contextVerticalPadding)
			.background(Color(.secondarySystemGroupedBackground))
			.clipShape(RoundedRectangle(cornerRadius: SpeechLayout.contextCornerRadius))
			.padding(.horizontal)
		}
	}

	@ViewBuilder
	private var employmentInsuranceDebateContext: some View {
		if isEmploymentInsuranceRelevant,
		   let ei = EmploymentInsuranceStatisticsDatabase.statistic(for: userProvinceCode) {
			VStack(alignment: .leading, spacing: SpeechLayout.contextSpacing) {
				HStack {
					Label("EI context", systemImage: "briefcase.fill")
						.font(.caption.bold())
					Spacer()
					Text(EmploymentInsuranceStatisticsDatabase.monthLabel(ei.referenceMonth))
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
				statPillRow {
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
			.padding(.horizontal, SpeechLayout.contextHorizontalPadding)
			.padding(.vertical, SpeechLayout.contextVerticalPadding)
			.background(Color(.secondarySystemGroupedBackground))
			.clipShape(RoundedRectangle(cornerRadius: SpeechLayout.contextCornerRadius))
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
	private var studentFinanceDebateContext: some View {
		if isStudentFinanceRelevant,
		   let finance = StudentFinancialAssistanceStatisticsDatabase.statistic(for: userProvinceCode),
		   let tuition = finance.latestTuitionYear {
			VStack(alignment: .leading, spacing: SpeechLayout.contextSpacing) {
				HStack {
					Label("Student finance context", systemImage: "graduationcap.fill")
						.font(.caption.bold())
					Spacer()
					Text(StudentFinancialAssistanceStatisticsDatabase.academicYearLabel(tuition.academicYear))
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
				statPillRow {
					statPill(
						"Tuition",
						tuition.averageUndergraduateTuition.formatted(.currency(code: "CAD").precision(.fractionLength(0)))
					)
					if let tuitionChange = tuition.yearOverYearChangePercent {
						statPill("Tuition YoY", yearOverYearLabel(tuitionChange))
					}
					if let latestCSFA = finance.latestCSFAYear {
						statPill("CSL recipients", latestCSFA.loanRecipients.formatted())
					}
				}
			}
			.padding(.horizontal, SpeechLayout.contextHorizontalPadding)
			.padding(.vertical, SpeechLayout.contextVerticalPadding)
			.background(Color(.secondarySystemGroupedBackground))
			.clipShape(RoundedRectangle(cornerRadius: SpeechLayout.contextCornerRadius))
			.padding(.horizontal)
		}
	}

	private var isStudentFinanceRelevant: Bool {
		ParliamentaryTopic.matching(subject.title).contains { $0.id == "education" }
	}

	@ViewBuilder
	private var correctionsDebateContext: some View {
		if isCorrectionsRelevant,
		   let snapshot = CorrectionsStatisticsDatabase.snapshot(),
		   let latest = snapshot.latestAnnualStatistic {
			VStack(alignment: .leading, spacing: SpeechLayout.contextSpacing) {
				HStack {
					Label("Corrections context", systemImage: "building.columns.fill")
						.font(.caption.bold())
					Spacer()
					Text(CorrectionsStatisticsDatabase.fiscalYearLabel(snapshot.referenceFiscalYear))
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
				statPillRow {
					statPill("Indigenous custody", percentLabel(latest.indigenousInCustodyPercent))
					statPill("Canada share", percentLabel(snapshot.indigenousPopulationShare.percentOfCanada))
					statPill("Recidivism", percentLabel(latest.recidivismRatePercent))
				}
			}
			.padding(.horizontal, SpeechLayout.contextHorizontalPadding)
			.padding(.vertical, SpeechLayout.contextVerticalPadding)
			.background(Color(.secondarySystemGroupedBackground))
			.clipShape(RoundedRectangle(cornerRadius: SpeechLayout.contextCornerRadius))
			.padding(.horizontal)
		}
	}

	private var isCorrectionsRelevant: Bool {
		let topicIDs = ParliamentaryTopic.matching(subject.title).map(\.id)
		if topicIDs.contains("justice") || topicIDs.contains("indigenous") {
			return true
		}
		let title = subject.title.localizedLowercase
		return title.contains("correctional service")
			|| title.contains("incarceration")
			|| title.contains("prison")
			|| title.contains("parole")
			|| title.contains("recidivism")
	}

	@ViewBuilder
	private var cppOasDebateContext: some View {
		if isCPPOASRelevant,
		   let stat = CPPOASStatisticsDatabase.statistic(for: userProvinceCode) {
			VStack(alignment: .leading, spacing: SpeechLayout.contextSpacing) {
				Label("Pensions context", systemImage: "person.text.rectangle.fill")
					.font(.caption.bold())
				statPillRow {
					if let cpp = stat.cppRetirementRecipients {
						statPill("CPP recipients", cpp.formatted())
					}
					if let oas = stat.oasPensionRecipients {
						statPill("OAS recipients", oas.formatted())
					}
				}
			}
			.padding(.horizontal, SpeechLayout.contextHorizontalPadding)
			.padding(.vertical, SpeechLayout.contextVerticalPadding)
			.background(Color(.secondarySystemGroupedBackground))
			.clipShape(RoundedRectangle(cornerRadius: SpeechLayout.contextCornerRadius))
			.padding(.horizontal)
		}
	}

	private var isCPPOASRelevant: Bool {
		ParliamentaryTopic.matching(subject.title).contains { $0.id == "seniors" }
	}

	@ViewBuilder
	private var veteransAffairsDebateContext: some View {
		if isVeteransAffairsRelevant,
		   let summary = VeteransAffairsStatisticsDatabase.nationalSummary(),
		   let latestAnnual = VeteransAffairsStatisticsDatabase.latestAnnual(),
		   let latestWait = latestAnnual.firstApplicationAverageWeeks {
			VStack(alignment: .leading, spacing: SpeechLayout.contextSpacing) {
				HStack {
					Label("Veterans context", systemImage: "cross.case.fill")
						.font(.caption.bold())
					Spacer()
					Text("Backlog as of \(VeteransAffairsStatisticsDatabase.dateLabel(summary.referenceDate))")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
				statPillRow {
					statPill("Recipients", summary.disabilityBenefitRecipients.formatted())
					statPill(
						"Wait \(latestAnnual.fiscalYear)",
						"\(latestWait.formatted(.number.precision(.fractionLength(1))))w"
					)
					statPill("Backlog", summary.backlogApplications.formatted())
				}
			}
			.padding(.horizontal, SpeechLayout.contextHorizontalPadding)
			.padding(.vertical, SpeechLayout.contextVerticalPadding)
			.background(Color(.secondarySystemGroupedBackground))
			.clipShape(RoundedRectangle(cornerRadius: SpeechLayout.contextCornerRadius))
			.padding(.horizontal)
		}
	}

	private var isVeteransAffairsRelevant: Bool {
		if ParliamentaryTopic.matching(subject.title).contains(where: { $0.id == "defence" }) {
			return true
		}
		let title = subject.title.localizedLowercase
		return title.contains("veteran")
			|| title.contains("veterans affairs")
			|| title.contains("disability benefit")
			|| title.contains("ancien combattant")
	}

	@ViewBuilder
	private var transportationSafetyDebateContext: some View {
		if isTransportationSafetyRelevant,
		   let road = TransportSafetyStatisticsDatabase.roadStatistic(for: userProvinceCode),
		   let rail = TransportSafetyStatisticsDatabase.latestModeYear("rail") {
			VStack(alignment: .leading, spacing: SpeechLayout.contextSpacing) {
				HStack {
					Label("Transport safety context", systemImage: "car.2.fill")
						.font(.caption.bold())
					Spacer()
					Text("\(road.referenceYear) road · \(rail.year) TSB")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
				statPillRow {
					statPill("Road deaths", TransportSafetyStatisticsDatabase.rateLabel(road.fatalitiesPer100k, unit: "/100k"))
					statPill("Rail accidents", rail.accidents.formatted())
					if let air = TransportSafetyStatisticsDatabase.latestModeYear("air") {
						statPill("Air accidents", air.accidents.formatted())
					}
				}
			}
			.padding(.horizontal, SpeechLayout.contextHorizontalPadding)
			.padding(.vertical, SpeechLayout.contextVerticalPadding)
			.background(Color(.secondarySystemGroupedBackground))
			.clipShape(RoundedRectangle(cornerRadius: SpeechLayout.contextCornerRadius))
			.padding(.horizontal)
		}
	}

	private var isTransportationSafetyRelevant: Bool {
		let topicIDs = ParliamentaryTopic.matching(subject.title).map(\.id)
		if topicIDs.contains("transport") {
			return true
		}
		let title = subject.title.localizedLowercase
		return title.contains("safety")
			|| title.contains("rail")
			|| title.contains("aviation")
			|| title.contains("marine")
			|| title.contains("road")
			|| title.contains("infrastructure")
	}

	private func statPill(_ label: String, _ value: String) -> some View {
		VStack(alignment: .leading, spacing: SpeechLayout.statPillSpacing) {
			Text(label)
				.font(.caption2)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
			Text(value)
				.font(.caption.monospacedDigit().weight(.semibold))
				.fixedSize(horizontal: false, vertical: true)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	@ViewBuilder
	private func statPillRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
		ViewThatFits(in: .horizontal) {
			HStack(spacing: SpeechLayout.statPillRowSpacing) {
				content()
			}
			VStack(alignment: .leading, spacing: SpeechLayout.statPillColumnSpacing) {
				content()
			}
		}
	}

	private func messageAccessibilityLabel(_ message: Message) -> String {
		SpeechMessageAccessibility.label(for: message, speaker: viewModel.speakers[message.id])
	}

	private func messageAccessibilityValue(_ message: Message) -> String {
		SpeechMessageAccessibility.value(for: message, messages: viewModel.messages, totalCount: length)
	}

	private func openSpeakerProfile(_ speaker: ParliamentMember) {
		router.selectedMember = speaker
		router.selectedTab = .members
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

	private func percentLabel(_ value: Double) -> String {
		"\(value.formatted(.number.precision(.fractionLength(1))))%"
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
		VStack(alignment: .leading, spacing: SpeechLayout.shareRootSpacing) {
			VStack(alignment: .leading, spacing: SpeechLayout.shareHeaderSpacing) {
				Text(subjectTitle)
					.font(.system(.headline, design: .rounded))
					.foregroundStyle(.gray)
				Text(date.formatted(date: .long, time: .omitted))
					.font(.system(.subheadline, design: .rounded))
					.foregroundStyle(.gray.opacity(SpeechLayout.shareHeaderOpacity))
			}
			.padding(.bottom, SpeechLayout.shareHeaderBottomPadding)

			ForEach(groupedMessages) { group in
				HStack(alignment: .bottom) {
					if !group.isCurrentUser {
						SpeakerImageView(speaker: group.speaker, parliamentNumber: parliamentNumber)
					} else {
						Spacer()
					}

					VStack(alignment: group.isCurrentUser ? .trailing : .leading, spacing: SpeechLayout.shareGroupSpacing) {
						if !group.isCurrentUser {
							VStack(alignment: .leading, spacing: 0) {
								Text(group.speaker.name)
									.font(.system(.caption, design: .rounded, weight: .bold))
								Text("\(group.speaker.riding), \(group.speaker.province.rawValue)")
									.font(.system(.caption2, design: .rounded))
							}
							.foregroundStyle(.white.opacity(SpeechLayout.speakerMetadataOpacity))
						}

						VStack(alignment: .leading, spacing: SpeechLayout.shareGroupSpacing) {
							ForEach(group.texts, id: \.self) { text in
								Text(verbatim: text)
									.lineSpacing(SpeechLayout.messageLineSpacing)
							}
						}
						.padding(SpeechLayout.messageBubblePadding)
						.background(group.isCurrentUser ? Color(UIColor.darkGray) : Color(UIColor.gray))
						.cornerRadius(SpeechLayout.messageBubbleCornerRadius)
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
		.frame(width: SpeechLayout.shareWidth)
	}
}
