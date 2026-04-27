//
//  NavigationRouter.swift
//  epac
//
//  Created by Codex on 2026-01-29.
//

import SwiftUI
import Observation

public enum AppTab: String, CaseIterable, Identifiable, Hashable {
	case home
	case parliament
	case members
	case accountability
	case search

	public var id: String { rawValue }

	// LocalizedStringKey so SwiftUI auto-resolves from Localizable.strings
	public var title: LocalizedStringKey {
		switch self {
		case .home:           return "Home"
		case .parliament:     return "Parliament"
		case .members:        return "Members"
		case .accountability: return "Accountability"
		case .search:         return "Search"
		}
	}

	public var systemImageName: String {
		switch self {
		case .home:           return "person.house.fill"
		case .parliament:     return "building.columns.fill"
		case .members:        return "person.3.sequence.fill"
		case .accountability: return "scalemass.fill"
		case .search:         return "magnifyingglass"
		}
	}
}

@Observable
class NavigationRouter {
	var selectedTab: AppTab = .parliament
	var selectedMember: ParliamentMember?
	// Pre-fills the Search tab search bar when set; cleared after SearchView reads it.
	var pendingSearchQuery: String?
	// Triggers postal code setup sheet when true; caller resets to false after handling.
	var pendingShowPostalCodeSetup = false
}
