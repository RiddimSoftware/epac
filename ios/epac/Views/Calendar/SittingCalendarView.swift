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

struct SittingCalendarView: View {
	@EnvironmentObject var fetch: Fetch
	@Binding var selectedDate: DateComponents?

	@Environment(\.modelContext) private var modelContext
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

	private let visibleDates = ISO8601DateFormatter().date(from: "2001-01-01T23:59:59Z")!...ISO8601DateFormatter().date(from: "2026-12-31T23:59:59Z")!
	private let todayComponents = Calendar.current.dateComponents([.year, .month, .day], from: .now)
	private let yearFormatter: NumberFormatter = {
		let f = NumberFormatter()
		f.usesGroupingSeparator = false
		return f
	}()
	private var firstSittingDayComponents: DateComponents? {
		let calendar = Calendar.current
		return viewModel.dates.union(viewModel.futureDates)
			.compactMap { calendar.date(from: $0) }
			.sorted()
			.first
			.map { calendar.dateComponents([.year, .month, .day], from: $0) }
	}

	var body: some View {
		let firstSittingDay = firstSittingDayComponents
		VStack {
			CalendarViewRepresentable(visibleDateRange: visibleDates, monthsLayout: .vertical, dataDependency: viewModel.dates, proxy: calendarViewProxy)
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
								RoundedRectangle(cornerRadius: 12)
									.fill(Color.appPositive)
							} else if isFutureSitting {
								RoundedRectangle(cornerRadius: 12)
									.stroke(Color.appPositive, lineWidth: 2)
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
						.accessibilityIdentifier(firstSittingDay?.sameYMD(as: day.components) == true
							? "parliament-sitting-row-0"
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
				.interMonthSpacing(15)
				.verticalDayMargin(8)
				.horizontalDayMargin(8)
				.padding([.leading, .trailing, .bottom])
				.background(CalendarScrollsToTopDisabler())
			VStack(alignment: .leading, spacing: 12) {
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

				HStack(spacing: 12) {
					RoundedRectangle(cornerRadius: 6)
						.fill(Color.appPositive)
						.frame(width: 24, height: 24)
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

				HStack(spacing: 20) {
					HStack(spacing: 8) {
						Circle()
							.fill(Color.appDestructive)
							.frame(width: 16, height: 16)
							.accessibilityHidden(true)
						Text("Today")
					}
					.accessibilityLabel("Today")

					HStack(spacing: 8) {
						RoundedRectangle(cornerRadius: 4)
							.stroke(Color.appPositive, lineWidth: 2)
							.frame(width: 16, height: 16)
							.accessibilityHidden(true)
						Text("Upcoming")
					}
					.accessibilityLabel("Upcoming scheduled sittings")
				}
				.font(.caption)
				.foregroundColor(.secondary)
			}
			.padding(.horizontal)
			.padding(.bottom, 8)
		}
		.frame(maxWidth: 500)
		.frame(maxWidth: .infinity)
		.task(id: viewModel.currentYear) {
			// id-based task cancels any in-flight fetch when year changes via the chevron picker.
			if viewModel.dates.isEmpty {
				await viewModel.fetchSittingCalendar(viewModel.currentYear, modelContext: modelContext, fetch: fetch)
				scrollToToday(animated: false)
			}
			selectedDate = nil
		}
		.safeAreaInset(edge: .bottom) {
			if viewModel.loadFailed {
				HStack(spacing: 12) {
					Image(systemName: "wifi.exclamationmark")
						.foregroundStyle(.red)
					Text("Couldn't load sitting dates.")
						.font(.footnote)
					Spacer()
					Button("Retry") {
						guard !isRetryDisabled else { return }
						isRetryDisabled = true
						Task { try? await Task.sleep(for: .seconds(2)); isRetryDisabled = false }
						Task { await viewModel.fetchSittingCalendar(viewModel.currentYear, modelContext: modelContext, fetch: fetch) }
					}
					.font(.footnote.bold())
					.disabled(isRetryDisabled)
				}
				.padding(.horizontal)
				.padding(.vertical, 10)
				.background(.ultraThinMaterial)
			}
		}
		.alert(NSLocalizedString("sitting.calendar.export.alertTitle", comment: ""), isPresented: $isShowingExportStatus) {
			Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {}
		} message: {
			Text(exportStatusMessage)
		}
		.toolbar {
			ToolbarItem(placement: .principal) {
				// Year picker: tap ‹ or › to jump by one year; the calendar scrolls to that year's January.
				HStack(spacing: 4) {
					Button {
						let prev = viewModel.currentYear - 1
						if prev >= 2016 {
							Task { await viewModel.fetchSittingCalendar(prev, modelContext: modelContext, fetch: fetch) }
							if let jan = Calendar.current.date(from: DateComponents(year: prev, month: 1, day: 1)) {
								calendarViewProxy.scrollToMonth(containing: jan, scrollPosition: .firstFullyVisiblePosition, animated: true)
							}
						}
					} label: {
						Image(systemName: "chevron.left")
							.font(.caption.weight(.semibold))
					}
					.disabled(viewModel.currentYear <= 2016)
					.accessibilityLabel("Previous year")
					.accessibilityHint(viewModel.currentYear > 2016 ? "Shows \(viewModel.currentYear - 1)" : "Not available before 2016")

					Text(verbatim: "\(viewModel.currentYear)")
						.font(.headline)
						.monospacedDigit()

					Button {
						let next = viewModel.currentYear + 1
						if next <= Calendar.current.dateComponents([.year], from: .now).year! {
							Task { await viewModel.fetchSittingCalendar(next, modelContext: modelContext, fetch: fetch) }
							if let jan = Calendar.current.date(from: DateComponents(year: next, month: 1, day: 1)) {
								calendarViewProxy.scrollToMonth(containing: jan, scrollPosition: .firstFullyVisiblePosition, animated: true)
							}
						}
					} label: {
						Image(systemName: "chevron.right")
							.font(.caption.weight(.semibold))
					}
					.disabled(viewModel.currentYear >= Calendar.current.dateComponents([.year], from: .now).year!)
					.accessibilityLabel("Next year")
					.accessibilityHint("Shows \(viewModel.currentYear + 1)")
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
		calendarViewProxy.scrollToDay(containing: .now, scrollPosition: .centered, animated: animated)
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
        VStack(spacing: 24) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
                .padding(.top, 40)
                .accessibilityHidden(true)
            
            VStack(spacing: 8) {
                Text(date.formatted(date: .long, time: .omitted))
                    .font(.title3)
                    .fontWeight(.bold)
                
                Text("The House is not sitting today.")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .padding(.horizontal, 40)
            
            VStack(alignment: .leading, spacing: 16) {
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
            .padding(.horizontal, 30)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: 500)
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
