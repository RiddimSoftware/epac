//
//  ContentView.swift
//  epac
//
//  Created by Sunny on 2024-12-11.
//

import SwiftUI
import SwiftData

struct ContentView: View {
	@Environment(\.modelContext) var modelContext
	var modelContainer: ModelContainer
	var fetch: Fetch

	init(modelContainer: ModelContainer) {
		self.modelContainer = modelContainer
		self.fetch = Fetch(modelContainer: modelContainer)
	}

	var body: some View {
		NavigationSplitView {
			SittingCalendarView()
				.navigationTitle("Parliament")
				.environmentObject(fetch)
		} detail: {
			Text("Select a Date")
		}
	}
}

//#Preview {
//	ContentView()
//}
