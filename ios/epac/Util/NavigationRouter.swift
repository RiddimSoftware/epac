//
//  NavigationRouter.swift
//  epac
//
//  Created by Codex on 2026-01-29.
//

import SwiftUI
import Observation

public enum AppTab: String, CaseIterable, Identifiable, Hashable {
	case sittingCalendar
	case search
	case members
	case expenditures

	public var id: String { rawValue }

	// LocalizedStringKey so SwiftUI auto-resolves from Localizable.strings
	public var title: LocalizedStringKey {
		switch self {
		case .sittingCalendar: return "Sitting Calendar"
		case .search:          return "Search"
		case .members:         return "Members"
		case .expenditures:    return "Expenditures"
		}
	}

	public var systemImageName: String {
		switch self {
		case .sittingCalendar: return "calendar"
		case .search:          return "magnifyingglass"
		case .members:         return "person.3"
		case .expenditures:    return "dollarsign.circle"
		}
	}
}

@Observable
class NavigationRouter {
	var selectedTab: AppTab = .sittingCalendar
	var selectedMember: ParliamentMember?
}
