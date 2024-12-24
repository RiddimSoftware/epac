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
	@State private var wasForwarded = false

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
							SpeechView(subject: subject)
								.onDisappear {
									print("onDisappear")
								}
						})
						.onAppear {
							if !wasForwarded {
								wasForwarded = true
								selectedSubject = selectedHansard?.orders.first(where: { order in
									order.subjects.contains { subject in
										subject.hansardID == "13061553"
									}
								})?.subjects.first(where: { subject in
									subject.hansardID == "13061553"
								})
							}
						}
				}
				.onChange(of: selectedDate) { oldValue, newValue in
					if let newValue, let date = Calendar.current.date(from: newValue) {
						Task {
							selectedHansard = try await fetch.hansard(date)
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
			if !wasForwarded {
				self.selectedDate = DateComponents(year: 2024, month: 12, day: 11)
			}
		}
		.fontDesign(.serif)
	}
}

//#Preview {
//	ContentView()
//}
