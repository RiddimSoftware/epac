//
//  ContentView.swift
//  epac
//
//  Created by Sunny on 2024-12-11.
//

import SwiftUI
import SwiftData
import Foundation

struct ContentView: View {
	@Environment(\.modelContext) var modelContext
	var modelContainer: ModelContainer
	var fetch: Fetch
	@State private var selectedDate: DateComponents?
	@State private var selectedHansard: Hansard?
	@State private var selectedSubject: SubjectOfBusiness?
	@State private var selectedHansardID: PersistentIdentifier?
	@Query private var members: [ParliamentMember]
	@Query private var constituencies: [Constituency]

	init(modelContainer: ModelContainer) {
		self.modelContainer = modelContainer
		self.fetch = Fetch(modelContainer: modelContainer)
	}

	var body: some View {
		NavigationStack {
			SittingCalendarView(selectedDate: $selectedDate)
				.environmentObject(fetch)
				.navigationDestination(item: $selectedHansard) { hansard in
					SittingView(hansard: hansard, selectedSubject: $selectedSubject)
						.navigationTitle(hansard.date.formatted(date: .abbreviated, time: .omitted))
						.navigationDestination(item: $selectedSubject, destination: { subject in
							SpeechView(hansard: hansard, subject: subject)
								.onDisappear {
									Log.debug("onDisappear")
								}
						})
				}
				.onChange(of: selectedDate) { oldValue, newValue in
					if let newValue, let date = Calendar.current.date(from: newValue) {
						if let fetched = try? modelContext.fetch(FetchDescriptor<Hansard>(predicate: #Predicate { $0.date == date })).first {
							selectedHansard = fetched
						} else {
							Task {
								do {
									try await fetch.downloadHansard(date)
									selectedHansard = try? modelContext.fetch(FetchDescriptor<Hansard>(predicate: #Predicate { $0.date == date })).first
								} catch {
									Log.debug("Failed to fetch hansard \(date)")
								}
							}
						}
					}
				}
		}
		.environmentObject(fetch)
		.onOpenURL { url in
			Log.debug("\(url.absoluteString)")
			let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
			if let items = components.queryItems {
				let date = items.first(where: { $0.name == "date" })?.value
				let subjectID = items.first(where: { $0.name == "subjectID" })?.value
				let speechID = items.first(where: { $0.name == "speechID" })?.value
				let messageID = items.first(where: { $0.name == "messageID" })?.value
				if let dateString = date, let d = ISO8601DateFormatter().date(from: dateString) {
					if let fetched = try? modelContext.fetch(FetchDescriptor<Hansard>(predicate: #Predicate { $0.date == d })).first {
						selectedHansard = fetched
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
					} else {
						Task {
							do {
								try await fetch.downloadHansard(d)
								selectedHansard = try? modelContext.fetch(FetchDescriptor<Hansard>(predicate: #Predicate { $0.date == d })).first
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
							} catch {
								Log.debug("Failed to fetch hansard \(error.localizedDescription)")
							}
						}
					}
				}
			}
		}
		.task {
			if members.count == 0 {
				do {
					try await fetch.downloadMembers()
				} catch {
					Log.debug("Failed to download members \(error.localizedDescription)")
				}
			}
			if constituencies.count == 0 {
				do {
					try await fetch.downloadConstituencies()
				} catch {
					Log.debug("Failed to download members \(error.localizedDescription)")
				}
			}
		}
		//		.fontDesign(.serif)
	}
}

//#Preview {
//	ContentView()
//}
