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

	init(modelContainer: ModelContainer) {
		self.modelContainer = modelContainer
		self.fetch = Fetch(modelContainer: modelContainer)
	}

	var body: some View {
		NavigationSplitView {
			SittingCalendarView(selectedDate: $selectedDate)
				.navigationTitle("Parliament")
				.environmentObject(fetch)
				.navigationDestination(item: $selectedHansard) { hansard in
					SittingView(hansard: hansard)
						.navigationTitle(hansard.date.formatted(date: .abbreviated, time: .omitted))
				}
				.onChange(of: selectedDate) { oldValue, newValue in
					if let newValue, let date = Calendar.current.date(from: newValue) {
						Task {
							selectedHansard = try await fetch.hansard(date)
						}
					}
				}
		} detail: {
			Text("Select a Date")
		}
		.fontDesign(.serif)
	}
}

//#Preview {
//	ContentView()
//}
