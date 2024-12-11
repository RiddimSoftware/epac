//
//  ContentView.swift
//  epac
//
//  Created by Sunny on 2024-12-11.
//

import SwiftUI

struct ContentView: View {
	var body: some View {
		NavigationSplitView {
			ParliamentDateView()
				.navigationTitle("Parliament")
		} detail: {
			Text("Select a Date")
		}
	}
}

#Preview {
	ContentView()
}
