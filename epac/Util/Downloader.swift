//
//  Downloader.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-05-13.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation
import Kanna
import SWXMLHash

class Downloader: ObservableObject {
	private static let hosturl: URL = URL(string: "https://www.ourcommons.ca")!
	private static let calendarPath: String = "/en/sitting-calendar/%d"
	private static let dailyPath: String = "/en/parliamentary-business/"
	private static let xmlPath: String = "/Content/House/%@/Debates/%@/HAN%@-%@.XML"
	private static var language: String = {
		if Locale.current.identifier.contains("fr") {
			return "F"
		} else {
			return "E"
		}
	}()


	static func downloadXML(forDate date: Date) async throws -> String {
		print("xml from network")
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
		guard href != nil else {
			throw NSError(domain: "", code: 4)
		}
		let pathcomponents = href!.components(separatedBy: "/")
		guard pathcomponents.count == 7 else {
			throw NSError(domain: "", code: 5)
		}
		let parlsession: String = pathcomponents[3].replacingOccurrences(of: "-", with: "")
		let sittingcomponents = pathcomponents[5].components(separatedBy: "-")
		guard sittingcomponents.count == 2 else {
			throw NSError(domain: "", code: 6)
		}
		let sittingnumber = sittingcomponents[1]
		let xmllinkpath = String(
			format: self.xmlPath,
			parlsession,
			sittingnumber,
			sittingnumber,
			self.language
		)
		let xmllink = hosturl.appending(path: xmllinkpath)
		request = URLRequest(url: xmllink, cachePolicy: .reloadIgnoringLocalCacheData)
		(data, _) = try await URLSession.shared.data(for: request)
		guard let utfstringvalue = String(data: data, encoding: .utf8) else {
			throw NSError(domain: "", code: 7)
		}
		return utfstringvalue
	}

	static func downloadCalendar(year: Int) async throws -> [Date] {
		print("Downloading calendar")
		let path = String(format: calendarPath, year)
		let request = URLRequest(url: hosturl.appending(path: path), cachePolicy: .reloadIgnoringLocalCacheData)
		let (data, _) = try await URLSession.shared.data(for: request)
		print("Downloaded \(data.count) bytes")

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
}
