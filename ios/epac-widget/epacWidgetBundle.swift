//
//  epacWidgetBundle.swift
//  epac-widget
//

import WidgetKit
import SwiftUI

@main
struct epacWidgetBundle: WidgetBundle {
	var body: some Widget {
		NextSittingWidget()
		RecentDebatesWidget()
	}
}
