//
//  NavigationRouter.swift
//  epac
//
//  Created by Codex on 2026-01-29.
//

import SwiftUI
import Observation

public enum AppTab: String, CaseIterable, Identifiable {
	case sittingCalendar
	case members
	case expenditures

	public var id: String { rawValue }

	public var title: String {
		switch self {
		case .sittingCalendar:
			return "Sitting Calendar"
		case .members:
			return "Members"
		case .expenditures:
			return "Expenditures"
		}
	}

	public var systemImageName: String {
		switch self {
		case .sittingCalendar:
			return "calendar"
		case .members:
			return "person.3"
		case .expenditures:
			return "dollarsign.circle"
		}
	}
}

@Observable
class NavigationRouter {
	var selectedTab: AppTab = .sittingCalendar
	var selectedMember: ParliamentMember?
}
