//
//  Calendar.swift
//  epac
//
//  Created by Sunny on 2024-12-11.
//

import SwiftData
import Foundation

@Model
final class SittingCalendar {
	var year: Int
	var sittings: [Date]
	init(year: Int, sittings: [Date]) {
		self.year = year
		self.sittings = sittings
	}
}

