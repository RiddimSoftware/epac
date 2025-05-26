//
//  ClipFetch.swift
//  epac
//
//  Created by Sunny on 2024-12-22.
//

import Foundation
import SwiftData
import Kanna
import SWXMLHash

@ModelActor
actor ClipFetch: ObservableObject {
	private let hosturl: URL = URL(string: "https://www.ourcommons.ca")!
	private let calendarPath: String = "en/sitting-calendar/%d"
	private let dailyPath: String = "en/parliamentary-business/"
	private let xmlPath: String = "Content/House/%@/Debates/%@/HAN%@-%@.XML"
	private let membersPath: String = "Members/en/search/XML"
	private let membersSearchPath: String = "Members/search/members"
	private let constituenciesPath: String = "Members/en/constituencies/XML"
	private var language: String = {
		if Locale.current.identifier.contains("fr") {
			return "F"
		} else {
			return "E"
		}
	}()
	
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
		let dates = try await downloadCalendar(year: year)
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

	func downloadXML(forDate date: Date) async throws -> String {
		let url = hosturl.appending(path: dailyPath).appending(path: DateUtils.getCSVStringFromDate(date))
		var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
		var (data, _) = try await URLSession.shared.data(for: request)
		guard let htmlstring = String(data: data, encoding: .utf8),
					let doc = try? HTML(html: htmlstring, url: nil, encoding: .utf8) else {
			throw NSError(domain: "", code: 1)
		}
		var href: String?
		for debatelink in doc.css("a.active-publication-link") {
			guard let text = debatelink.text?.lowercased() else {
				throw NSError(domain: "", code: 2)
			}
			if text.contains("hansard") {
				href = debatelink["href"]
			}
			else if text.contains("projected") {
				throw NSError(domain: "", code: 3)
			}
		}
		guard let href else {
			throw NSError(domain: "", code: 4)
		}
		request = URLRequest(url: hosturl.appending(path: href))
		(data, _) = try await URLSession.shared.data(for: request)
		guard let htmlstring = String(data: data, encoding: .utf8),
					let doc = try? HTML(html: htmlstring, url: nil, encoding: .utf8) else {
			throw NSError(domain: "", code: 1)
		}
		guard let xmllinkelement = doc.css("a.btn-export-xml").first else {
			throw NSError(domain: "", code: 5)
		}
		guard let href = xmllinkelement["href"] else {
			throw NSError(domain: "", code: 4)
		}
		let xmllink = hosturl.appending(path: href)
		request = URLRequest(url: xmllink, cachePolicy: .reloadIgnoringLocalCacheData)
		(data, _) = try await URLSession.shared.data(for: request)
		guard let utfstringvalue = String(data: data, encoding: .utf8) else {
			throw NSError(domain: "", code: 7)
		}
		return utfstringvalue
	}

	func downloadCalendar(year: Int) async throws -> [Date] {
		Log.debug("Downloading calendar \(year)")
		let path = String(format: calendarPath, year)
		let request = URLRequest(url: hosturl.appending(path: path), cachePolicy: .reloadIgnoringLocalCacheData)
		let (data, _) = try await URLSession.shared.data(for: request)
		Log.debug("Downloaded \(data.count) bytes")

		if let htmlstring = String(data: data, encoding: .utf8),
			 let doc = try? HTML(html: htmlstring, url: nil, encoding: String.Encoding.utf8) {
			var dates: [Date] = []
			for cssdate in doc.css("td.chamber-meeting") {
				guard let attrclass = cssdate["class"],
							attrclass.contains("chamber-meeting") else {
					continue
				}
				let classes = attrclass.components(separatedBy: " ")
				guard let datestring = classes.first else {
					continue
				}
				let date = DateUtils.getDate(forCSVDateString: datestring)
				dates.append(date)
			}
			dates.sort(by: >)
			UserDefaults.standard.set(dates, forKey: "calendardates_v2")
			return dates
		} else {
			return []
		}

	}

	func downloadMembers() async throws -> [ParliamentMember] {
		let url = hosturl.appending(path: membersPath)
		let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
		let (data, _) = try await URLSession.shared.data(for: request)
		guard let utfstringvalue = String(data: data, encoding: .utf8) else {
			throw NSError(domain: "", code: 7)
		}
		let members = XMLBro.parseMembers(utfstringvalue)
		return members
	}

	func downloadMember(_ firstName: String, _ lastName: String) async throws -> ParliamentMember {
		let url = hosturl.appending(path: membersSearchPath)
		var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
		request.httpMethod = "POST"
		request.httpBody = try! JSONSerialization.data(withJSONObject: ["searchText": "\(firstName) \(lastName)"])
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		let (data, _) = try await URLSession.shared.data(for: request)
		guard let responseBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw NSError(domain: "", code: 7)
		}
		let pastMembers = responseBody["pastMembers"] as! [[String: Any]]
		if let member = pastMembers.first {
			return ParliamentMember(
				name: "\(firstName) \(lastName)",
				lastName: lastName,
				firstName: firstName,
				photoURL: hosturl.appending(path: member["officialPhotoUrl"] as! String),
				riding: member["constituencyNameEn"] as! String,
				province: Province(rawValue: member["provinceNameEn"] as! String)!,
				party: Party.partyWithAbbreviation(member["caucusAbbreviationEn"] as! String)
			)
		} else {
			throw NSError(domain: "", code: 8)
		}
	}


	func downloadConsituencies() async throws -> [Constituency] {
		let url = hosturl.appending(path: constituenciesPath)
		let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
		let (data, _) = try await URLSession.shared.data(for: request)
		guard let utfstringvalue = String(data: data, encoding: .utf8) else {
			throw NSError(domain: "", code: 7)
		}
		let constituencies = XMLBro.parseConstituencies(utfstringvalue)
		return constituencies
	}
}
