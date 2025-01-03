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
	@Query private var members: [ParliamentMember]

	init(modelContainer: ModelContainer) {
		self.modelContainer = modelContainer
		self.fetch = Fetch(modelContainer: modelContainer)
	}

	var body: some View {
		NavigationStack {
			SittingCalendarView(selectedDate: $selectedDate)
				.navigationTitle("Parliament")
				.environmentObject(fetch)
				.navigationDestination(item: $selectedHansard) { hansard in
					SittingView(hansard: hansard, selectedSubject: $selectedSubject)
						.navigationTitle(hansard.date.formatted(date: .abbreviated, time: .omitted))
						.navigationDestination(item: $selectedSubject, destination: { subject in
							SpeechView(hansard: hansard, subject: subject)
								.onDisappear {
									print("onDisappear")
								}
						})
				}
				.onChange(of: selectedDate) { oldValue, newValue in
					if let newValue, let date = Calendar.current.date(from: newValue) {
						Task {
							selectedHansard = try await fetch.hansard(date)
						}
					}
				}
		}
		.onOpenURL { url in
				print(url)
				let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
				if let items = components.queryItems {
					let date = items.first(where: { $0.name == "date" })?.value
					let subjectID = items.first(where: { $0.name == "subjectID" })?.value
					let speechID = items.first(where: { $0.name == "speechID" })?.value
					let messageID = items.first(where: { $0.name == "messageID" })?.value
					if let dateString = date, let d = ISO8601DateFormatter().date(from: dateString) {
						Task {
							do {
								selectedHansard = try await fetch.hansard(d)
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
								print(error.localizedDescription)
							}
						}
					}
				}
			}
		.task {
			if members.count == 0 {
				do {
					let downloadedMembers = try await Downloader.downloadMembers()
					print("Downloaded \(downloadedMembers.count) members")
					downloadedMembers.forEach { modelContext.insert($0) }
				} catch {
					print("Failed to download members \(error.localizedDescription)")
				}
			}
		}
		.fontDesign(.serif)
	}
}

//#Preview {
//	ContentView()
//}
