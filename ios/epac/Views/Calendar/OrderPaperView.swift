//
//  OrderPaperView.swift
//  epac
//

import SwiftData
import SwiftUI

private enum OrderPaperLayout {
	static let upcomingLimit = 15
	static let minimumUpcomingCount = 1
	static let rowIconWidth: CGFloat = 28
	static let compactTextSpacing = EpacSpacing.xxs
	static let cardSpacing = EpacSpacing.s
	static let buttonVerticalPadding = EpacSpacing.s
	static let buttonCornerRadius: CGFloat = 10
	static let cardVerticalPadding = EpacSpacing.xs
}

// Shows upcoming scheduled sitting days from the local SittingCalendar cache
// and links to the official ourcommons.ca Order Paper for the full agenda.
//
// The Order Paper (Feuilleton) lists every item of business Parliament will
// consider on a sitting day. Parliament publishes it as a PDF the day before;
// this view surfaces the sitting schedule we already have and deep-links to
// the official document so users can read the actual agenda.
struct OrderPaperView: View {
	@Environment(\.openURL) private var openURL

	@Query(sort: [SortDescriptor(\SittingCalendar.year, order: .reverse)])
	private var calendars: [SittingCalendar]

	private var upcomingSittings: [Date] {
		let today = Calendar.current.startOfDay(for: .now)
		return Array(calendars
			.flatMap { $0.sittings }
			.filter { $0 >= today }
			.sorted()
			.prefix(OrderPaperLayout.upcomingLimit))
	}

	private var nextSitting: Date? { upcomingSittings.first }

	var body: some View {
		List {
			if let next = nextSitting {
				Section {
					nextSittingCard(date: next)
				}
			}

			if upcomingSittings.count > OrderPaperLayout.minimumUpcomingCount {
				Section("Upcoming Sittings") {
					ForEach(upcomingSittings.dropFirst(), id: \.self) { date in
						HStack {
							Image(systemName: "calendar")
								.foregroundStyle(.secondary)
								.frame(width: OrderPaperLayout.rowIconWidth)
							VStack(alignment: .leading, spacing: OrderPaperLayout.compactTextSpacing) {
								Text(date.formatted(.dateTime.weekday(.wide)))
									.font(.subheadline.bold())
								Text(date.formatted(date: .long, time: .omitted))
									.font(.caption)
									.foregroundStyle(.secondary)
							}
						}
					}
				}
			}

			Section("Official Source") {
				officialSourceRow
			}

			if upcomingSittings.isEmpty {
				ContentUnavailableView {
					Label("No upcoming sittings loaded", systemImage: "calendar.badge.exclamationmark")
				} description: {
					Text("Open the Parliament tab calendar to choose a sitting.")
				}
			}
		}
		.listStyle(.insetGrouped)
		.navigationTitle("Order Paper")
		.navigationBarTitleDisplayMode(.inline)
	}

	// MARK: - Sub-views

	private func nextSittingCard(date: Date) -> some View {
		let daysUntil = Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
		return VStack(alignment: .leading, spacing: OrderPaperLayout.cardSpacing) {
			HStack {
				VStack(alignment: .leading, spacing: OrderPaperLayout.compactTextSpacing) {
					Text("Next Sitting")
						.font(.caption)
						.foregroundStyle(.secondary)
					Text(date.formatted(.dateTime.weekday(.wide).month().day()))
						.font(.title3.bold())
				}
				Spacer()
				VStack(alignment: .trailing, spacing: OrderPaperLayout.compactTextSpacing) {
					Text(daysUntil == 0 ? "Today" : daysUntil == 1 ? "Tomorrow" : "In \(daysUntil) days")
						.font(.headline)
						.foregroundStyle(daysUntil <= 1 ? .green : .primary)
					Text("House of Commons")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
			}
			Button {
				openOrderPaper(for: date)
			} label: {
				Label("View Order Paper", systemImage: "doc.text")
					.frame(maxWidth: .infinity)
					.padding(.vertical, OrderPaperLayout.buttonVerticalPadding)
					.background(Color.accentColor)
					.foregroundStyle(.white)
					.cornerRadius(OrderPaperLayout.buttonCornerRadius)
			}
		}
		.padding(.vertical, OrderPaperLayout.cardVerticalPadding)
	}

	private var officialSourceRow: some View {
		Button {
			openURL(URL(string: "https://www.ourcommons.ca/en/parliamentary-business/order-papers")!)
		} label: {
			HStack {
				VStack(alignment: .leading, spacing: OrderPaperLayout.compactTextSpacing) {
					Text("ourcommons.ca Order Papers")
						.font(.subheadline)
						.foregroundStyle(.primary)
					Text("Official daily agenda published by Parliament")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Image(systemName: "arrow.up.right.square")
					.foregroundStyle(.secondary)
			}
		}
	}

	// MARK: - Helpers

	private static let orderPaperDateFormatter: DateFormatter = {
		let f = DateFormatter()
		f.dateFormat = "yyyyMMdd"
		return f
	}()

	private func openOrderPaper(for date: Date) {
		// The official Order Paper is published at a date-specific URL.
		// Format: /DocumentViewer/en/44-1/house/order-paper/[YYYYMMDD]
		// We use the index page since we don't know the exact parliament/session
		// without joining calendar data to parliament metadata.
		let fallback = URL(string: "https://www.ourcommons.ca/en/parliamentary-business/order-papers")!
		let dateStr = Self.orderPaperDateFormatter.string(from: date)
		let url = URL(string: "https://www.ourcommons.ca/en/parliamentary-business/order-paper/\(dateStr)") ?? fallback
		openURL(url)
	}
}
