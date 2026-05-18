//
//  CalendarExportService.swift
//  epac
//

import EventKit
import Foundation

enum CalendarExportError: LocalizedError {
	case accessDenied
	case noDefaultCalendar

	var errorDescription: String? {
		switch self {
		case .accessDenied:
			return NSLocalizedString("sitting.calendar.export.error.accessDenied", comment: "")
		case .noDefaultCalendar:
			return NSLocalizedString("sitting.calendar.export.error.noDefaultCalendar", comment: "")
		}
	}
}

@MainActor
final class CalendarExportService {
	nonisolated(unsafe) private let eventStore: EKEventStore

	init(eventStore: EKEventStore = EKEventStore()) {
		self.eventStore = eventStore
	}

	func addSittingDays(_ dates: [Date], calendar: Calendar = .current) async throws -> Int {
		guard !dates.isEmpty else { return 0 }
		guard try await requestCalendarAccess() else {
			throw CalendarExportError.accessDenied
		}
		guard let targetCalendar = eventStore.defaultCalendarForNewEvents else {
			throw CalendarExportError.noDefaultCalendar
		}

		var addedCount = 0
		for date in dates {
			let start = calendar.startOfDay(for: date)
			guard !hasExistingSittingEvent(on: start, calendar: calendar) else { continue }
			let event = EKEvent(eventStore: eventStore)
			event.calendar = targetCalendar
			event.title = NSLocalizedString("sitting.calendar.export.eventTitle", comment: "")
			event.startDate = start
			event.endDate = calendar.date(byAdding: .day, value: 1, to: start)
			event.isAllDay = true
			event.url = CalendarExportService.deepLinkURL(for: start)
			try eventStore.save(event, span: .thisEvent, commit: false)
			addedCount += 1
		}
		if addedCount > 0 {
			try eventStore.commit()
		}
		return addedCount
	}

	static func subscriptionURL(baseURL: URL = ArtifactConfig.shared.baseURL) -> URL {
		ArtifactKey.calendarHouse.url(relativeTo: baseURL)
	}

	static func deepLinkURL(for date: Date, calendar: Calendar = .current) -> URL? {
		let components = calendar.dateComponents([.year, .month, .day], from: date)
		guard let year = components.year,
		      let month = components.month,
		      let day = components.day else {
			return nil
		}
		return URL(string: String(format: "cabinetdoor://sitting/%04d-%02d-%02d", year, month, day))
	}

	private func requestCalendarAccess() async throws -> Bool {
		if #available(iOS 17.0, *) {
			switch EKEventStore.authorizationStatus(for: .event) {
			case .fullAccess:
				return true
			case .denied, .restricted, .writeOnly:
				return false
			case .notDetermined:
				return try await eventStore.requestFullAccessToEvents()
			@unknown default:
				return false
			}
		} else {
			switch EKEventStore.authorizationStatus(for: .event) {
			case .fullAccess:
				return true
			case .authorized:
				return true
			case .writeOnly:
				return false
			case .denied, .restricted:
				return false
			case .notDetermined:
				return try await withCheckedThrowingContinuation { continuation in
					eventStore.requestAccess(to: .event) { granted, error in
						if let error {
							continuation.resume(throwing: error)
						} else {
							continuation.resume(returning: granted)
						}
					}
				}
			@unknown default:
				return false
			}
		}
	}

	private func hasExistingSittingEvent(on date: Date, calendar: Calendar) -> Bool {
		guard let end = calendar.date(byAdding: .day, value: 1, to: date) else { return false }
		let predicate = eventStore.predicateForEvents(withStart: date, end: end, calendars: nil)
		let title = NSLocalizedString("sitting.calendar.export.eventTitle", comment: "")
		return eventStore.events(matching: predicate).contains { event in
			event.isAllDay && event.title == title && calendar.isDate(event.startDate, inSameDayAs: date)
		}
	}
}
