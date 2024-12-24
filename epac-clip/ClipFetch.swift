//
//  ClipFetch.swift
//  epac
//
//  Created by Sunny on 2024-12-22.
//

import Foundation
import SwiftData

@ModelActor
actor ClipFetch: ObservableObject {
	func sittingCalendar(_ year: Int) async throws -> SittingCalendar {
		let calendar = try modelContext.fetch(FetchDescriptor<SittingCalendar>(predicate: #Predicate { $0.year == year }))
		if let first = calendar.first {
			return first
		} else {
			try await downloadSittingCalendar(year)
			return try await sittingCalendar(year)
		}
	}
	private func downloadSittingCalendar(_ year: Int) async throws {
		let dates = try await Downloader.downloadCalendar(year: year)
		let calendar = SittingCalendar(year: year, sittings: dates)
		modelContext.insert(calendar)
		try modelContext.save()
	}

	func hansard(_ date: Date) async throws -> Hansard {
		let fetched = try modelContext.fetch(FetchDescriptor<Hansard>(predicate: #Predicate { $0.date == date }))
		if let first = fetched.first {
			return first
		} else {
			try await downloadHansard(date)
			return try await hansard(date)
		}
	}

	func downloadHansard(_ date: Date) async throws {
		let path = Bundle(for: ClipFetch.self).path(forResource: "2024-12-11", ofType: "xml")
		if let path, let url = URL(string: path) {
			let xml = try String(contentsOf: url, encoding: .utf8)
			let hansard = Hansard(xml: xml)
			modelContext.insert(hansard)
			try modelContext.save()
		} else {
			throw NSError(domain: "downloadHansard", code: 1)
		}
	}
}
