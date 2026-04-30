//
//  epacWidgetBundle.swift
//  epac-widget
//

import SwiftUI
import WidgetKit

@main
struct epacWidgetBundle: WidgetBundle {
	var body: some Widget {
		NextSittingWidget()
		RecentDebatesWidget()
	}
}
