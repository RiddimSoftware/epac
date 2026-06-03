import Observation
import SwiftUI

private enum LobbyistOrganizationLayout {
	static let sectionSpacing = EpacSpacing.s
	static let rowSpacing = EpacSpacing.xs
	static let compactSpacing = EpacSpacing.xxs
	static let pillHorizontalPadding: CGFloat = 8
	static let pillVerticalPadding: CGFloat = 4
	static let countColumnWidth: CGFloat = 42
	static let loadingMinHeight: CGFloat = 220
	static let recentCommunicationLimit = 10
	static let statusPillOpacity = 0.14
	static let typePillOpacity = 0.12
}

struct LobbyistOrganizationView: View {
	@State private var viewModel: LobbyistOrganizationViewModel

	init(
		organizationID: String,
		load: LoadLobbyistOrganizationProfile = LoadLobbyistOrganizationProfile(
			repository: BackendLobbyistOrganizationRepository()
		),
		initialProfile: LobbyistOrganization? = nil,
		autoload: Bool = true
	) {
		_viewModel = State(
			initialValue: LobbyistOrganizationViewModel(
				target: .id(organizationID),
				load: load,
				initialProfile: initialProfile,
				autoload: autoload
			)
		)
	}

	init(
		organizationName: String,
		load: LoadLobbyistOrganizationProfile = LoadLobbyistOrganizationProfile(
			repository: BackendLobbyistOrganizationRepository()
		),
		initialProfile: LobbyistOrganization? = nil,
		autoload: Bool = true
	) {
		_viewModel = State(
			initialValue: LobbyistOrganizationViewModel(
				target: .name(organizationName),
				load: load,
				initialProfile: initialProfile,
				autoload: autoload
			)
		)
	}

	init(profile: LobbyistOrganization) {
		_viewModel = State(
			initialValue: LobbyistOrganizationViewModel(
				target: .id(profile.id),
				load: LoadLobbyistOrganizationProfile(repository: BackendLobbyistOrganizationRepository()),
				initialProfile: profile,
				autoload: false
			)
		)
	}

	var body: some View {
		Group {
			if viewModel.isLoading && viewModel.profile == nil {
				ProgressView(NSLocalizedString("lobbying.loading", comment: ""))
					.frame(maxWidth: .infinity, minHeight: LobbyistOrganizationLayout.loadingMinHeight)
			} else if viewModel.loadFailed && viewModel.profile == nil {
				ContentUnavailableView(
					NSLocalizedString("lobbying.error.title", comment: ""),
					systemImage: "exclamationmark.triangle",
					description: Text(NSLocalizedString("lobbying.error.description", comment: ""))
				)
				.frame(maxWidth: .infinity, minHeight: LobbyistOrganizationLayout.loadingMinHeight)
			} else if let profile = viewModel.profile {
				List {
					header(profile)
					activeRegistrations(profile)
					communications(profile)
					subjectMatters(profile)
					Section {
						LobbyingSourceCitationView(url: profile.sourceURL)
					}
				}
				.listStyle(.insetGrouped)
				.accessibilityIdentifier("lobbyist-organization-profile")
			}
		}
		.navigationTitle(viewModel.profile?.name ?? "Organization")
		.navigationBarTitleDisplayMode(.inline)
		.task {
			guard viewModel.autoload, viewModel.profile == nil, !viewModel.isLoading else { return }
			await viewModel.loadProfile()
		}
	}

	private func header(_ profile: LobbyistOrganization) -> some View {
		Section {
			VStack(alignment: .leading, spacing: LobbyistOrganizationLayout.sectionSpacing) {
				Text(profile.name)
					.font(.title3.weight(.semibold))
					.fixedSize(horizontal: false, vertical: true)

				ViewThatFits(in: .horizontal) {
					HStack(spacing: LobbyistOrganizationLayout.compactSpacing) {
						statusPill(profile.registrationStatus)
						typePill(registrationKindLabel(profile))
						if let sector = profile.sector, !sector.isEmpty {
							typePill(sector)
						}
					}
					VStack(alignment: .leading, spacing: LobbyistOrganizationLayout.compactSpacing) {
						statusPill(profile.registrationStatus)
						typePill(registrationKindLabel(profile))
						if let sector = profile.sector, !sector.isEmpty {
							typePill(sector)
						}
					}
				}

				HStack {
					Link(destination: profile.sourceURL) {
						Label("Open OCL record", systemImage: "arrow.up.right.square")
					}
					Spacer()
					Button {
						viewModel.follow()
					} label: {
						Label("Follow", systemImage: "bell.badge")
					}
					.buttonStyle(.bordered)
					.accessibilityHint("Notification behavior is not yet enabled.")
				}
				.font(.caption)
			}
			.padding(.vertical, EpacSpacing.xs)
		}
	}

	@ViewBuilder
	private func activeRegistrations(_ profile: LobbyistOrganization) -> some View {
		Section("Active registrations") {
			if profile.activeRegistrations.isEmpty {
				Text(profile.registrationStatus == .expired ? "No active registration in the OCL aggregate." : "No active registration details available.")
					.font(.caption)
					.foregroundStyle(.secondary)
			} else {
				ForEach(profile.activeRegistrations) { registration in
					LobbyistRegistrationRow(registration: registration)
				}
			}
		}

		if !profile.expiredRegistrations.isEmpty {
			Section("Registration history") {
				ForEach(profile.expiredRegistrations) { registration in
					LobbyistRegistrationRow(registration: registration)
				}
			}
		}
	}

	private func communications(_ profile: LobbyistOrganization) -> some View {
		Section("Communications") {
			if profile.recentCommunications.isEmpty {
				Text("No communications found for this organization.")
					.font(.caption)
					.foregroundStyle(.secondary)
			} else {
				ForEach(profile.recentCommunications.prefix(LobbyistOrganizationLayout.recentCommunicationLimit)) { communication in
					if let memberID = communication.dpohMemberID.flatMap(Int.init) {
						NavigationLink {
							ScrollView {
								LobbyingView(memberID: memberID)
									.padding()
							}
							.navigationTitle(communication.dpohName)
							.navigationBarTitleDisplayMode(.inline)
						} label: {
							LobbyistOrganizationCommunicationRow(communication: communication)
						}
					} else {
						LobbyistOrganizationCommunicationRow(communication: communication)
					}
				}
			}
		}
	}

	private func subjectMatters(_ profile: LobbyistOrganization) -> some View {
		Section("Subject matters") {
			if profile.subjectMatters.isEmpty {
				Text("No subject-matter counts found for this organization.")
					.font(.caption)
					.foregroundStyle(.secondary)
			} else {
				ForEach(profile.subjectMatters) { subject in
					if let slug = subject.topicSlug, !slug.isEmpty {
						NavigationLink(destination: TopicsView(initialSearchText: topicSearchText(for: slug))) {
							LobbyistOrganizationSubjectRow(subject: subject)
						}
					} else {
						LobbyistOrganizationSubjectRow(subject: subject)
					}
				}
			}
		}
	}

	private func statusPill(_ status: LobbyistRegistrationStatus) -> some View {
		Text(status == .active ? "Active" : "Expired")
			.font(.caption2.weight(.semibold))
			.padding(.horizontal, LobbyistOrganizationLayout.pillHorizontalPadding)
			.padding(.vertical, LobbyistOrganizationLayout.pillVerticalPadding)
			.background(
				(status == .active ? Color.appPositive : Color.appWarning)
					.opacity(LobbyistOrganizationLayout.statusPillOpacity)
			)
			.foregroundStyle(status == .active ? Color.appPositive : Color.appWarning)
			.clipShape(Capsule())
	}

	private func typePill(_ label: String) -> some View {
		Text(label)
			.font(.caption2.weight(.semibold))
			.padding(.horizontal, LobbyistOrganizationLayout.pillHorizontalPadding)
			.padding(.vertical, LobbyistOrganizationLayout.pillVerticalPadding)
			.background(Color.accentColor.opacity(LobbyistOrganizationLayout.typePillOpacity))
			.foregroundStyle(Color.accentColor)
			.clipShape(Capsule())
	}

	private func registrationKindLabel(_ profile: LobbyistOrganization) -> String {
		let registrations = profile.activeRegistrations.isEmpty ? profile.registrations : profile.activeRegistrations
		let lobbyists = profile.registeredLobbyists
		let kinds = Set((registrations.isEmpty ? lobbyists.map(\.kind) : registrations.map(\.kind)))
		if kinds.contains(.consultant), kinds.contains(.inHouse) {
			return "Consultant + in-house"
		}
		if kinds.contains(.consultant) {
			return "Consultant"
		}
		return "In-house"
	}

	private func topicSearchText(for slug: String) -> String {
		ParliamentaryTopic.all.first { $0.id == slug }?.localizedName ?? slug
	}
}

private struct LobbyistRegistrationRow: View {
	let registration: LobbyistRegistration

	var body: some View {
		VStack(alignment: .leading, spacing: LobbyistOrganizationLayout.rowSpacing) {
			HStack {
				Text(registration.kind == .consultant ? "Consultant registration" : "In-house registration")
					.font(.subheadline.weight(.semibold))
				Spacer()
				Text(registration.status == .active ? "Active" : "Expired")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(registration.status == .active ? Color.appPositive : Color.appWarning)
				Link("OCL", destination: registration.sourceURL)
					.font(.caption2)
			}
			if !registration.subjectMatters.isEmpty {
				Text(registration.subjectMatters.joined(separator: ", "))
					.font(.caption)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			if !registration.targetedInstitutions.isEmpty {
				Text("Targets: \(registration.targetedInstitutions.joined(separator: ", "))")
					.font(.caption2)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.accessibilityElement(children: .combine)
	}
}

private struct LobbyistOrganizationCommunicationRow: View {
	let communication: LobbyistOrganizationCommunication

	var body: some View {
		VStack(alignment: .leading, spacing: LobbyistOrganizationLayout.rowSpacing) {
			HStack(alignment: .firstTextBaseline) {
				Text(communication.dpohName)
					.font(.subheadline.weight(.semibold))
					.fixedSize(horizontal: false, vertical: true)
				Spacer()
				if let date = communication.date {
					Text(date, style: .date)
						.font(.caption2.monospacedDigit())
						.foregroundStyle(.secondary)
				}
			}
			Text(communication.institution)
				.font(.caption)
				.foregroundStyle(.secondary)
			if !communication.subjectMatters.isEmpty {
				Text(communication.subjectMatters.joined(separator: ", "))
					.font(.caption2)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			LobbyingSourceCitationView(url: communication.sourceURL)
		}
		.accessibilityElement(children: .combine)
	}
}

private struct LobbyistOrganizationSubjectRow: View {
	let subject: LobbyistOrganizationSubjectMatter

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: LobbyistOrganizationLayout.rowSpacing) {
			Text(subject.subjectMatter)
				.font(.subheadline)
				.fixedSize(horizontal: false, vertical: true)
			Spacer(minLength: EpacSpacing.s)
			Text("\(subject.communicationCount)")
				.font(.subheadline.monospacedDigit().weight(.semibold))
				.frame(width: LobbyistOrganizationLayout.countColumnWidth, alignment: .trailing)
		}
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(subject.subjectMatter), \(subject.communicationCount) communications")
	}
}

private enum LobbyistOrganizationTarget: Equatable {
	case id(String)
	case name(String)
}

@MainActor
@Observable
private final class LobbyistOrganizationViewModel {
	let target: LobbyistOrganizationTarget
	let autoload: Bool
	private let load: LoadLobbyistOrganizationProfile

	var profile: LobbyistOrganization?
	var isLoading = false
	var loadFailed = false

	init(
		target: LobbyistOrganizationTarget,
		load: LoadLobbyistOrganizationProfile,
		initialProfile: LobbyistOrganization?,
		autoload: Bool
	) {
		self.target = target
		self.load = load
		self.profile = initialProfile
		self.autoload = autoload
	}

	func loadProfile() async {
		isLoading = true
		loadFailed = false
		defer { isLoading = false }

		do {
			switch target {
			case let .id(id):
				profile = try await load.execute(id: id)
			case let .name(name):
				profile = try await load.execute(organizationName: name)
			}
		} catch {
			loadFailed = true
		}
	}

	func follow() {}
}
