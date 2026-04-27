//
//  ContentViewModel.swift
//  epac
//

import Observation
import SwiftUI
import SwiftData

@MainActor
@Observable
class ContentViewModel {
	var selectedDate: DateComponents?
	var selectedHansard: Hansard?
	var nonSittingDate: Date?
	var selectedSubject: SubjectOfBusiness?
	var selectedHansardID: PersistentIdentifier?

	func onSelectedDateChanged(to newValue: DateComponents?, modelContext: ModelContext, fetch: Fetch) {
		guard let newValue, let date = Calendar.current.date(from: newValue) else { return }

		if let fetched = try? modelContext.fetch(FetchDescriptor<Hansard>(predicate: #Predicate { $0.date == date })).first {
			selectedHansard = fetched
		} else {
			Task { @MainActor in
				do {
					try await fetch.downloadHansard(date)
					selectedHansard = try? modelContext.fetch(FetchDescriptor<Hansard>(predicate: #Predicate { $0.date == date })).first
					if let h = selectedHansard {
						let subjects = h.orders.flatMap { $0.subjects }.map { (title: $0.title, date: h.date) }
						await TopicNotificationScheduler.checkAndNotify(subjectTitles: subjects)
						let titles = h.orders.flatMap { $0.subjects }.map { $0.title }
						WidgetDataWriter.writeRecentSubjects(titles)
						WidgetDataWriter.reloadWidgets()
					}
				} catch {
					Log.debug("Failed to fetch hansard \(date)")
					nonSittingDate = date
				}
			}
		}
	}

	func onOpenURL(_ url: URL, modelContext: ModelContext, fetch: Fetch) {
		Log.debug("\(url.absoluteString)")
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
			  let items = components.queryItems else { return }

		let dateString = items.first(where: { $0.name == "date" })?.value
		let subjectID = items.first(where: { $0.name == "subjectID" })?.value
		let speechID = items.first(where: { $0.name == "speechID" })?.value
		let messageID = items.first(where: { $0.name == "messageID" })?.value

		guard let dateString, let date = ISO8601DateFormatter().date(from: dateString) else { return }

		func applyNavigation(hansard: Hansard) {
			selectedHansard = hansard
			if let subjectID {
				let subject = try? modelContext.fetch(FetchDescriptor<SubjectOfBusiness>(predicate: #Predicate { $0.hansardID == subjectID })).first
				if let speechID {
					subject?.currentSpeech = subject?.speeches.first(where: { $0.hansardID == speechID })
					if let messageID {
						subject?.currentSpeech?.currentMessage = subject?.currentSpeech?.messages.first(where: { $0.hansardID == messageID })
					}
				}
				selectedSubject = subject
			}
		}

		if let fetched = try? modelContext.fetch(FetchDescriptor<Hansard>(predicate: #Predicate { $0.date == date })).first {
			applyNavigation(hansard: fetched)
		} else {
			Task { @MainActor in
				do {
					try await fetch.downloadHansard(date)
					if let fetched = try? modelContext.fetch(FetchDescriptor<Hansard>(predicate: #Predicate { $0.date == date })).first {
						applyNavigation(hansard: fetched)
					}
				} catch {
					Log.debug("Failed to fetch hansard \(error.localizedDescription)")
				}
			}
		}
	}

	func downloadInitialData(members: [ParliamentMember], constituencies: [Constituency], modelContext: ModelContext, fetch: Fetch) async {
		// Snapshot Sendable Bools before async let to avoid Swift 6 data-race warnings
		// from capturing @MainActor-bound @Model arrays across task boundaries.
		let needsMembers = members.isEmpty
		let needsConstituencies = constituencies.isEmpty

		// All three downloads are independent — run concurrently to minimize cold-launch sync time.
		// downloadVotingRecords guards itself internally (fetchCount == 0), so no outer check needed.
		async let membersDownload: Void = needsMembers ? fetch.downloadMembers() : ()
		async let constituenciesDownload: Void = needsConstituencies ? fetch.downloadConstituencies() : ()
		async let votesDownload: Void = fetch.downloadVotingRecords()

		do { try await membersDownload } catch { Log.debug("Failed to download members: \(error.localizedDescription)") }
		do { try await constituenciesDownload } catch { Log.debug("Failed to download constituencies: \(error.localizedDescription)") }
		do { try await votesDownload } catch { Log.debug("Failed to download voting records: \(error.localizedDescription)") }
	}
}
