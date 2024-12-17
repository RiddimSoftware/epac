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
						SpeechView2(subject: subject)
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
