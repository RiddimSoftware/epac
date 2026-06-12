//
//  ContentView.swift
//  epac
//
//  Created by Sunny on 2024-12-08.
//

import HorizonCalendar
import SwiftData
import SwiftUI
import UIKit

private enum SittingCalendarLayout {
	static let sittingDayCornerRadius = EpacCornerRadius.m
	static let futureSittingStrokeWidth: CGFloat = 2
	static let interMonthSpacing: CGFloat = 15
	static let dayMargin = EpacSpacing.s
	static let controlsSpacing: CGFloat = 12
	static let legendSwatchCornerRadius: CGFloat = 6
	static let legendSwatchSize = EpacIconSize.m
	static let legendGroupSpacing: CGFloat = 20
	static let legendItemSpacing = EpacSpacing.s
	static let legendIndicatorSize = EpacIconSize.xs
	static let calendarBottomPadding = EpacSpacing.s
	static let contentMaxWidth: CGFloat = 500
	static let retryDelaySeconds: Int64 = 2
	static let retryVerticalPadding: CGFloat = 10
	static let yearPickerSpacing = EpacSpacing.xs
	static let firstAvailableYear = 2016
	static let yearStep = 1
	static let januaryMonth = 1
	static let firstDayOfMonth = 1
	static let recessRootSpacing = EpacSpacing.l
	static let recessIconSize: CGFloat = 80
	static let recessIconTopPadding: CGFloat = 40
	static let recessDateSpacing = EpacSpacing.s
	static let recessDividerHorizontalPadding: CGFloat = 40
	static let recessInfoSpacing = EpacSpacing.m
	static let recessInfoHorizontalPadding: CGFloat = 30
}

struct SittingCalendarView: View {
	@EnvironmentObject var fetch: Fetch
	@Binding var selectedDate: DateComponents?
	@Binding var pendingInterventionID: String?

	@Environment(\.modelContext) private var modelContext
	@Environment(\.hansardRepository) private var hansardRepository
	@Environment(\.isPresented) private var isPresented
	@Environment(\.font) private var font
	@StateObject private var calendarViewProxy = CalendarViewProxy()

	@State private var viewModel = SittingCalendarViewModel()
	@State private var calendarExportService = CalendarExportService()
	@State private var isRefreshing = false
	@State private var isRetryDisabled = false
	@State private var isExportingCalendar = false
	@State private var exportStatusMessage = ""
	@State private var isShowingExportStatus = false
	@State private var isTodayVisible = true
	@State private var isShowingHansardSearch = false
	@State private var scrollCoordinator = SittingCalendarScrollCoordinator()
	@State private var hasRequestedInitialTodayScroll = false

	private let visibleDates = ISO8601DateFormatter().date(from: "2001-01-01T23:59:59Z")!...ISO8601DateFormatter().date(from: "2026-12-31T23:59:59Z")!
	private let todayComponents = Calendar.current.dateComponents([.year, .month, .day], from: .now)
	private let yearFormatter: NumberFormatter = {
		let f = NumberFormatter()
		f.usesGroupingSeparator = false
		return f
	}()
	var body: some View {
		VStack {
			CalendarViewRepresentable(visibleDateRange: visibleDates, monthsLayout: .vertical, dataDependency: viewModel.sittingDateComponents, proxy: calendarViewProxy)
				.days({ day in
					let isToday = todayComponents.sameYMD(as: day.components)
					let isPastSitting = viewModel.dates.contains(where: { $0.sameYMD(as: day.components) })
					let isFutureSitting = viewModel.futureDates.contains(where: { $0.sameYMD(as: day.components) })

					Text(verbatim: "\(day.day)")
						.foregroundStyle(isToday ? Color(UIColor.white) : Color(UIColor.label))
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.background {
							if isToday {
								Circle()
									.fill(Color.appDestructive)
							} else if isPastSitting {
								RoundedRectangle(cornerRadius: SittingCalendarLayout.sittingDayCornerRadius)
									.fill(Color.appPositive)
							} else if isFutureSitting {
								RoundedRectangle(cornerRadius: SittingCalendarLayout.sittingDayCornerRadius)
									.stroke(Color.appPositive, lineWidth: SittingCalendarLayout.futureSittingStrokeWidth)
							} else {
								Color.clear
							}
						}
						.accessibilityLabel({
							if let date = Calendar.current.date(from: day.components) {
								let formatted = date.formatted(date: .long, time: .omitted)
								if isToday && isPastSitting { return "\(formatted), today, sitting" }
								if isToday { return "\(formatted), today" }
								if isPastSitting { return "\(formatted), sitting day" }
								if isFutureSitting { return "\(formatted), scheduled sitting" }
								return formatted
							}
							return "\(day.day)"
						}())
						.accessibilityIdentifier(isPastSitting || isFutureSitting
							? "sitting-day-cell"
							: "parliament-calendar-day-\(day.components.year ?? 0)-\(day.components.month ?? 0)-\(day.day)")
				})
				.onDragEnd({ visibleDayRange, willDecelerate in
					guard !willDecelerate else { return }
					viewModel.onVisibleDayRangeChanged(visibleDayRange, modelContext: modelContext, fetch: fetch)
				})
				.onDeceleratingEnd({ visibleDayRange in
					viewModel.onVisibleDayRangeChanged(visibleDayRange, modelContext: modelContext, fetch: fetch)
				})
				.onDaySelection({ day in
					selectedDate = day.components
				})
				.onScroll({ visibleDayRange, _ in
					updateTodayVisibility(for: visibleDayRange)
				})
				.interMonthSpacing(SittingCalendarLayout.interMonthSpacing)
				.verticalDayMargin(SittingCalendarLayout.dayMargin)
				.horizontalDayMargin(SittingCalendarLayout.dayMargin)
				.padding([.leading, .trailing, .bottom])
				.background(CalendarScrollsToTopDisabler())
				.onAppear {
					if scrollCoordinator.calendarDidMount() {
						scrollToToday(animated: false, deferIfUnmounted: false)
					}
				}
				.onDisappear {
					scrollCoordinator.calendarDidUnmount()
				}
			VStack(alignment: .leading, spacing: SittingCalendarLayout.controlsSpacing) {
				Button {
					scrollToToday(animated: true)
				} label: {
					Label("Today", systemImage: "calendar.circle")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.borderedProminent)
				.disabled(isTodayVisible)
				.accessibilityHint(isTodayVisible ? "Today is already visible" : "Scrolls to today's date")
				.accessibilityIdentifier("parliament-calendar-today-button")

				HStack(spacing: SittingCalendarLayout.controlsSpacing) {
					RoundedRectangle(cornerRadius: SittingCalendarLayout.legendSwatchCornerRadius)
						.fill(Color.appPositive)
						.frame(width: SittingCalendarLayout.legendSwatchSize, height: SittingCalendarLayout.legendSwatchSize)
						.accessibilityHidden(true)
					Text("Sitting days")
						.font(.subheadline)
						.fontWeight(.medium)
					if viewModel.sittingDayCount > 0 {
						Text("(\(viewModel.sittingDayCount) in \(yearFormatter.string(from: NSNumber(value: viewModel.currentYear))!))")
							.font(.caption)
							.foregroundColor(.secondary)
					}
				}
				.accessibilityElement(children: .combine)
				.accessibilityLabel(viewModel.sittingDayCount > 0
					? "Sitting days: \(viewModel.sittingDayCount) in \(viewModel.currentYear)"
					: "Sitting days legend")

				HStack(spacing: SittingCalendarLayout.legendGroupSpacing) {
					HStack(spacing: SittingCalendarLayout.legendItemSpacing) {
						Circle()
							.fill(Color.appDestructive)
							.frame(width: SittingCalendarLayout.legendIndicatorSize, height: SittingCalendarLayout.legendIndicatorSize)
							.accessibilityHidden(true)
						Text("Today")
					}
					.accessibilityLabel("Today")

					HStack(spacing: SittingCalendarLayout.legendItemSpacing) {
						RoundedRectangle(cornerRadius: EpacCornerRadius.xs)
							.stroke(Color.appPositive, lineWidth: SittingCalendarLayout.futureSittingStrokeWidth)
							.frame(width: SittingCalendarLayout.legendIndicatorSize, height: SittingCalendarLayout.legendIndicatorSize)
							.accessibilityHidden(true)
						Text("Upcoming")
					}
					.accessibilityLabel("Upcoming scheduled sittings")
				}
				.font(.caption)
				.foregroundColor(.secondary)
			}
			.padding(.horizontal)
			.padding(.bottom, SittingCalendarLayout.calendarBottomPadding)
		}
		.frame(maxWidth: SittingCalendarLayout.contentMaxWidth)
		.frame(maxWidth: .infinity)
		.task(id: viewModel.currentYear) {
			// id-based task cancels any in-flight load when year changes via the chevron picker.
			viewModel.configure(
				browseHansardSitting: BrowseHansardSitting(
					repository: HansardSittingRepositoryAdapter(hansardRepository: hansardRepository)
				)
			)
			viewModel.loadSittingCalendarCacheFirst(
				viewModel.currentYear,
				modelContext: modelContext,
				fetch: fetch,
				forceRemoteRefresh: true
			)
			requestInitialScrollToToday()
			selectedDate = nil
		}
		.safeAreaInset(edge: .bottom) {
			if viewModel.loadFailed {
				HStack(spacing: SittingCalendarLayout.controlsSpacing) {
					Image(systemName: "wifi.exclamationmark")
						.foregroundStyle(.red)
					Text("Couldn't load sitting dates.")
						.font(.footnote)
					Spacer()
					Button("Retry") {
						guard !isRetryDisabled else { return }
						isRetryDisabled = true
						Task { try? await Task.sleep(for: .seconds(SittingCalendarLayout.retryDelaySeconds)); isRetryDisabled = false }
						Task { await viewModel.fetchSittingCalendar(viewModel.currentYear, modelContext: modelContext, fetch: fetch) }
					}
					.font(.footnote.bold())
					.disabled(isRetryDisabled)
				}
				.padding(.horizontal)
				.padding(.vertical, SittingCalendarLayout.retryVerticalPadding)
				.background(.ultraThinMaterial)
			}
		}
		.alert(NSLocalizedString("sitting.calendar.export.alertTitle", comment: ""), isPresented: $isShowingExportStatus) {
			Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {}
		} message: {
			Text(exportStatusMessage)
		}
		.navigationDestination(isPresented: $isShowingHansardSearch) {
			HansardSearchView { result in
				isShowingHansardSearch = false
				pendingInterventionID = result.interventionID
				selectedDate = Calendar.current.dateComponents([.year, .month, .day], from: result.sittingDate)
			}
		}
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					isShowingHansardSearch = true
				} label: {
					Image(systemName: "magnifyingglass")
				}
				.accessibilityLabel("Search Hansard debates")
			}
			ToolbarItem(placement: .principal) {
				// Year picker: tap ‹ or › to jump by one year; the calendar scrolls to that year's January.
				HStack(spacing: SittingCalendarLayout.yearPickerSpacing) {
					Button {
						let prev = viewModel.currentYear - SittingCalendarLayout.yearStep
						if prev >= SittingCalendarLayout.firstAvailableYear {
							Task { await viewModel.fetchSittingCalendar(prev, modelContext: modelContext, fetch: fetch) }
							if let jan = Calendar.current.date(from: DateComponents(year: prev, month: SittingCalendarLayout.januaryMonth, day: SittingCalendarLayout.firstDayOfMonth)) {
								calendarViewProxy.scrollToMonth(containing: jan, scrollPosition: .firstFullyVisiblePosition, animated: true)
							}
						}
					} label: {
						Image(systemName: "chevron.left")
							.font(.caption.weight(.semibold))
					}
					.disabled(viewModel.currentYear <= SittingCalendarLayout.firstAvailableYear)
					.accessibilityLabel("Previous year")
					.accessibilityHint(
						viewModel.currentYear > SittingCalendarLayout.firstAvailableYear
							? "Shows \(viewModel.currentYear - SittingCalendarLayout.yearStep)"
							: "Not available before \(SittingCalendarLayout.firstAvailableYear)"
					)

					Text(verbatim: "\(viewModel.currentYear)")
						.font(.headline)
						.monospacedDigit()

					Button {
						let next = viewModel.currentYear + SittingCalendarLayout.yearStep
						if next <= Calendar.current.dateComponents([.year], from: .now).year! {
							Task { await viewModel.fetchSittingCalendar(next, modelContext: modelContext, fetch: fetch) }
							if let jan = Calendar.current.date(from: DateComponents(year: next, month: SittingCalendarLayout.januaryMonth, day: SittingCalendarLayout.firstDayOfMonth)) {
								calendarViewProxy.scrollToMonth(containing: jan, scrollPosition: .firstFullyVisiblePosition, animated: true)
							}
						}
					} label: {
						Image(systemName: "chevron.right")
							.font(.caption.weight(.semibold))
					}
					.disabled(viewModel.currentYear >= Calendar.current.dateComponents([.year], from: .now).year!)
					.accessibilityLabel("Next year")
					.accessibilityHint("Shows \(viewModel.currentYear + SittingCalendarLayout.yearStep)")
				}
				.accessibilityElement(children: .contain)
			}
			ToolbarItem(placement: .topBarTrailing) {
				if isRefreshing {
					ProgressView()
						.accessibilityLabel("Refreshing parliamentary calendar")
				} else {
					Button {
						Task {
							isRefreshing = true
							await viewModel.refresh(modelContext: modelContext, fetch: fetch)
							isRefreshing = false
						}
					} label: {
						Image(systemName: "arrow.clockwise")
					}
					.accessibilityLabel("Refresh parliamentary calendar")
				}
			}
			ToolbarItem(placement: .topBarTrailing) {
				if isExportingCalendar {
					ProgressView()
						.accessibilityLabel(NSLocalizedString("sitting.calendar.export.inProgress", comment: ""))
				} else {
					Button {
						Task { await addNextSittingsToCalendar() }
					} label: {
						Image(systemName: "calendar.badge.plus")
					}
					.accessibilityLabel(NSLocalizedString("sitting.calendar.export.addNext30", comment: ""))
				}
			}
			ToolbarItem(placement: .topBarTrailing) {
				Menu {
					NavigationLink(destination: OrderPaperView()) {
						Label("Order Paper", systemImage: "doc.text.below.ecg")
					}
					NavigationLink(destination: CommitteesView()) {
						Label(
							NSLocalizedString("committees.navTitle", comment: ""),
							systemImage: "person.3"
						)
					}
					NavigationLink(destination: OntarioDebatesView()) {
						Label(
							NSLocalizedString("ontario.debates.toolbarLabel", comment: ""),
							systemImage: "building.2"
						)
					}
				} label: {
					Image(systemName: "line.3.horizontal")
				}
				.accessibilityLabel("More parliamentary links")
			}
		}
	}

	private func updateTodayVisibility(for visibleDayRange: DayComponentsRange) {
		let calendar = Calendar.current
		guard let visibleStart = calendar.date(from: visibleDayRange.lowerBound.components),
		      let visibleEnd = calendar.date(from: visibleDayRange.upperBound.components),
		      let today = calendar.date(from: todayComponents) else {
			isTodayVisible = false
			return
		}
		isTodayVisible = visibleStart <= today && today <= visibleEnd
	}

	private func scrollToToday(animated: Bool) {
		scrollToToday(animated: animated, deferIfUnmounted: true)
	}

	private func requestInitialScrollToToday() {
		guard !hasRequestedInitialTodayScroll else { return }
		hasRequestedInitialTodayScroll = true
		scrollToToday(animated: false)
	}

	private func scrollToToday(animated: Bool, deferIfUnmounted: Bool) {
		switch scrollCoordinator.requestScrollToToday(deferIfUnmounted: deferIfUnmounted) {
		case .scrollNow:
			calendarViewProxy.scrollToDay(containing: .now, scrollPosition: .centered, animated: animated)
		case .deferredUntilMounted:
			Log.warning("Deferred SittingCalendarView scrollToToday until CalendarViewRepresentable appears")
		case .skippedUnmounted:
			Log.warning("Skipped SittingCalendarView scrollToToday because CalendarViewRepresentable is not mounted")
			return
		}
		isTodayVisible = true
	}

	private func addNextSittingsToCalendar() async {
		let sittingDates = viewModel.upcomingSittingDates()
		if sittingDates.isEmpty {
			exportStatusMessage = NSLocalizedString("sitting.calendar.export.noUpcoming", comment: "")
			isShowingExportStatus = true
			return
		}

		isExportingCalendar = true
		defer { isExportingCalendar = false }
		do {
			let count = try await calendarExportService.addSittingDays(sittingDates)
			if count == 0 {
				exportStatusMessage = NSLocalizedString("sitting.calendar.export.alreadyAdded", comment: "")
			} else {
				exportStatusMessage = String(
					format: NSLocalizedString("sitting.calendar.export.addedCount", comment: ""),
					count
				)
			}
		} catch {
			exportStatusMessage = error.localizedDescription
		}
		isShowingExportStatus = true
	}

}

extension Date: @retroactive Identifiable {
	public var id: Date {
		return self
	}
}

extension DateComponents {
	func sameYMD(as components: DateComponents) -> Bool {
		return self.year == components.year && self.month == components.month && self.day == components.day
	}
}

struct NonSittingDayView: View {
    let date: Date

    var body: some View {
        VStack(spacing: SittingCalendarLayout.recessRootSpacing) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: SittingCalendarLayout.recessIconSize))
                .foregroundColor(.accentColor)
                .padding(.top, SittingCalendarLayout.recessIconTopPadding)
                .accessibilityHidden(true)

            VStack(spacing: SittingCalendarLayout.recessDateSpacing) {
                Text(date.formatted(date: .long, time: .omitted))
                    .font(.title3)
                    .fontWeight(.bold)

                Text("The House is not sitting today.")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }

            Divider()
                .padding(.horizontal, SittingCalendarLayout.recessDividerHorizontalPadding)

            VStack(alignment: .leading, spacing: SittingCalendarLayout.recessInfoSpacing) {
                Label("Committee Meetings", systemImage: "person.3.fill")
                    .font(.headline)
                Text("Committees often meet even when the House is not in session to study legislation and specific issues in depth.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Label("Historical Throwback", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Text("Did you know? The first session of Canada's 1st Parliament opened on November 6, 1867.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, SittingCalendarLayout.recessInfoHorizontalPadding)

            Spacer()
        }
        .padding()
        .frame(maxWidth: SittingCalendarLayout.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .navigationTitle("Recess")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        NonSittingDayView(date: .now)
    }
}
