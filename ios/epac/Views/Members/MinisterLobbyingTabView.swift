import SwiftUI

private enum MinisterLobbyingLayout {
	static let cardCornerRadius = EpacCornerRadius.m
	static let cardSpacing = EpacSpacing.m
	static let sectionSpacing = EpacSpacing.s
	static let rowSpacing = EpacSpacing.xs
	static let rowPadding = EpacSpacing.s
	static let badgeSpacing = EpacSpacing.xxs
	static let matchStripeWidth: CGFloat = 4
	static let matchStripeCornerRadius: CGFloat = 2
	static let countColumnWidth: CGFloat = 44
	static let loadingMinHeight: CGFloat = 120
	static let unavailableMinHeight: CGFloat = 180
	static let mandateMatchRowOpacity = 0.12
	static let mandateMatchBadgeOpacity = 0.18
	static let mandateMatchBadgeHorizontalPadding: CGFloat = 6
	static let mandateMatchBadgeVerticalPadding: CGFloat = 3
}

struct MinisterLobbyingTabView: View {
	let memberID: Int

	private let load: LoadMinisterLobbyingByPortfolio
	private let autoload: Bool

	@State private var periods: [MinisterPortfolioLobbyingPeriod]
	@State private var isLoading = false
	@State private var loadFailed = false
	@State private var loaded: Bool

	init(
		memberID: Int,
		load: LoadMinisterLobbyingByPortfolio = LoadMinisterLobbyingByPortfolio(
			repository: BackendCabinetLobbyingRepository()
		),
		initialPeriods: [MinisterPortfolioLobbyingPeriod] = [],
		initialLoadCompleted: Bool = false,
		autoload: Bool = true
	) {
		self.memberID = memberID
		self.load = load
		self.autoload = autoload
		self._periods = State(initialValue: initialPeriods)
		self._loaded = State(initialValue: initialLoadCompleted || !initialPeriods.isEmpty)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: MinisterLobbyingLayout.cardSpacing) {
			header

			if isLoading && periods.isEmpty {
				ProgressView(NSLocalizedString("lobbying.loading", comment: ""))
					.frame(maxWidth: .infinity, minHeight: MinisterLobbyingLayout.loadingMinHeight)
			} else if loadFailed && periods.isEmpty {
				ContentUnavailableView(
					NSLocalizedString("lobbying.error.title", comment: ""),
					systemImage: "exclamationmark.triangle",
					description: Text(NSLocalizedString("lobbying.error.description", comment: ""))
				)
				.frame(minHeight: MinisterLobbyingLayout.unavailableMinHeight)
			} else if loaded && periods.isEmpty {
				ContentUnavailableView(
					"No registered ministerial lobbying",
					systemImage: "building.columns",
					description: Text("No communications found for this minister's cabinet portfolio periods.")
				)
				.frame(minHeight: MinisterLobbyingLayout.unavailableMinHeight)
			} else {
				ForEach(periods) { period in
					MinisterPortfolioPeriodSection(period: period)
				}
			}
		}
		.padding()
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color.appSurface)
		.cornerRadius(MinisterLobbyingLayout.cardCornerRadius)
		.accessibilityIdentifier("minister-lobbying-tab")
		.task(id: memberID) {
			guard autoload, !loaded, !isLoading else { return }
			await reload()
		}
	}

	private var header: some View {
		HStack(alignment: .firstTextBaseline) {
			Label("Ministerial Lobbying", systemImage: "person.2.wave.2.fill")
				.font(.headline)
			Spacer()
			if !periods.isEmpty {
				Text("\(periods.reduce(0) { $0 + $1.communicationCount })")
					.font(.headline.monospacedDigit())
					.foregroundStyle(.secondary)
					.accessibilityLabel("\(periods.reduce(0) { $0 + $1.communicationCount }) communications")
			}
		}
	}

	@MainActor
	private func reload() async {
		isLoading = true
		loadFailed = false
		defer {
			isLoading = false
			loaded = true
		}

		do {
			periods = try await load.execute(memberID: memberID)
		} catch {
			loadFailed = true
		}
	}
}

private struct MinisterPortfolioPeriodSection: View {
	let period: MinisterPortfolioLobbyingPeriod

	var body: some View {
		VStack(alignment: .leading, spacing: MinisterLobbyingLayout.sectionSpacing) {
			HStack(alignment: .top) {
				VStack(alignment: .leading, spacing: MinisterLobbyingLayout.badgeSpacing) {
					Text(period.title)
						.font(.subheadline.weight(.semibold))
						.fixedSize(horizontal: false, vertical: true)
					Text(period.dateRangeLabel)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer(minLength: EpacSpacing.s)
				Text("\(period.communicationCount)")
					.font(.subheadline.monospacedDigit().weight(.semibold))
					.frame(width: MinisterLobbyingLayout.countColumnWidth, alignment: .trailing)
					.accessibilityLabel("\(period.communicationCount) communications")
			}

			if period.communications.isEmpty {
				Text("No communications recorded for this portfolio period.")
					.font(.caption)
					.foregroundStyle(.secondary)
			} else {
				ForEach(period.communications) { communication in
					MinisterLobbyingRow(communication: communication)
				}
			}
		}
		.padding(.vertical, EpacSpacing.xs)
	}
}

private struct MinisterLobbyingRow: View {
	let communication: MinisterLobbyingCommunication

	var body: some View {
		VStack(alignment: .leading, spacing: MinisterLobbyingLayout.rowSpacing) {
			HStack(alignment: .firstTextBaseline, spacing: EpacSpacing.xs) {
				Text(communication.organizationName)
					.font(.subheadline.weight(.semibold))
					.fixedSize(horizontal: false, vertical: true)
				if communication.mandateMatch {
					MandateMatchBadge()
				}
			}

			if !communication.subjectMatter.isEmpty {
				Text(communication.subjectMatter)
					.font(.caption)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}

			HStack(spacing: EpacSpacing.xs) {
				if let date = communication.communicationDate {
					Text(Self.dateFormatter.string(from: date))
				}
				if let communicationType = communication.communicationType, !communicationType.isEmpty {
					Text(communicationType)
				}
				if !communication.registrantType.isEmpty {
					Text(communication.registrantType)
				}
			}
			.font(.caption2)
			.foregroundStyle(.secondary)

			LobbyingSourceCitationView(url: communication.registryURL)
		}
		.padding(MinisterLobbyingLayout.rowPadding)
		.padding(.leading, communication.mandateMatch ? EpacSpacing.s : 0)
		.overlay(alignment: .leading) {
			if communication.mandateMatch {
				RoundedRectangle(cornerRadius: MinisterLobbyingLayout.matchStripeCornerRadius)
					.fill(Color.appWarning)
					.frame(width: MinisterLobbyingLayout.matchStripeWidth)
					.padding(.vertical, MinisterLobbyingLayout.rowPadding)
					.padding(.leading, MinisterLobbyingLayout.rowPadding)
					.accessibilityHidden(true)
			}
		}
		.background(
			communication.mandateMatch
				? Color.appWarning.opacity(MinisterLobbyingLayout.mandateMatchRowOpacity)
				: Color(.secondarySystemBackground)
		)
		.cornerRadius(EpacCornerRadius.s)
		.accessibilityElement(children: .combine)
	}

	private static let dateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.calendar = Calendar(identifier: .gregorian)
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateStyle = .medium
		formatter.timeStyle = .none
		return formatter
	}()
}

private struct MandateMatchBadge: View {
	var body: some View {
		Label("Mandate match", systemImage: "doc.text.magnifyingglass")
			.labelStyle(.titleAndIcon)
			.font(.caption2.weight(.semibold))
			.padding(.horizontal, MinisterLobbyingLayout.mandateMatchBadgeHorizontalPadding)
			.padding(.vertical, MinisterLobbyingLayout.mandateMatchBadgeVerticalPadding)
			.background(Color.appWarning.opacity(MinisterLobbyingLayout.mandateMatchBadgeOpacity))
			.foregroundStyle(Color.appWarning)
			.clipShape(Capsule())
			.fixedSize()
	}
}

struct LobbyingSourceCitationView: View {
	let url: URL

	var body: some View {
		Link(CabinetLobbyingSource.citation, destination: url)
			.font(.caption2)
			.foregroundStyle(.secondary)
			.accessibilityIdentifier("lobbying-source-citation")
	}
}

private extension MinisterPortfolioLobbyingPeriod {
	var title: String {
		"While \(portfolioName)"
	}

	var dateRangeLabel: String {
		switch (startDate, endDate) {
		case let (start?, end?):
			"\(Self.monthFormatter.string(from: start)) to \(Self.monthFormatter.string(from: end))"
		case let (start?, nil):
			"\(Self.monthFormatter.string(from: start)) to present"
		case let (nil, end?):
			"Until \(Self.monthFormatter.string(from: end))"
		case (nil, nil):
			"Portfolio period"
		}
	}

	private static let monthFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.calendar = Calendar(identifier: .gregorian)
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateFormat = "yyyy-MM"
		return formatter
	}()
}
