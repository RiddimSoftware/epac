//
//  Fetch.swift
//  epac
//
//  Created by Sunny on 2024-12-12.
//

import Foundation
import SwiftData
import Kanna
import SWXMLHash

@ModelActor
actor Fetch: ObservableObject {
        private let hosturl: URL = URL(string: "https://www.ourcommons.ca")!
        private let calendarPath: String = "en/sitting-calendar/%d"
        private let dailyPath: String = "en/parliamentary-business/"
        private let xmlPath: String = "Content/House/%@/Debates/%@/HAN%@-%@.XML"
        private let membersPath: String = "Members/en/search/XML?parliament=all&caucusId=all&province=all&gender=all"
        private let membersSearchPath: String = "Members/search/members"
        private let constituenciesPath: String = "Members/en/constituencies/XML"
        private let leadersPath: String = "members/en/house-officers/xml?parliament=%d&caucusId=all&province=all&gender=all" // replace #d with parliament number 1-45
        private let cabinetPath: String = "members/en/ministries/xml?ministry=%d&province=all&gender=all&lastName=all" // replace %d with parliament number 1-30
        private let chairsPath: String = "members/en/chair-occupants/xml?parliament=%d&caucusId=all&province=all&gender=all" // replace %d with ministry number 1-45
        private let memberPath: String = "members/en/%@-%@(%@)/xml" // replace with first name, last name, personID
        /// expenditurePath is an HTML page with a link to a CSV export of the expenditures for that year/quarter. The CSV export does not change since it is a historical record of expenditures.
        /// The HTML page also has a number of links in the table under the Travel, Hospitality, and Contracts columns. Clicking on these links gives more details about each expenditure type for a specific member.
        /// There is a CSV export link on each of those Travel/Hospitality/Contracts pages as well.
        /// The CSV exports are of interest so that they can be downloaded and data extracted from them to populate our data model.
        private let expenditurePath: String = "proactivedisclosure/en/members/%d/%d" // replace with Year 2021+ and Quarter 1-4.
        private var language: String = {
                if Locale.current.identifier.contains("fr") {
                        return "F"
                } else {
                        return "E"
                }
        }()

        private var downloadsInProgress: Set<String> = []
        private var failedDownloads: Set<String> = []
	private let openAPIURL = URL(string: "https://api.open.ourcommons.ca")!
	func sittingCalendar(_ year: Int) async throws -> SittingCalendar {
		Log.debug("Fetch.sittingCalendar(year: \(year))")
		let calendar = try modelContext.fetch(FetchDescriptor<SittingCalendar>(predicate: #Predicate { $0.year == year }))
		if let first = calendar.first {
			return first
		} else {
			try await downloadSittingCalendar(year)
			return try await sittingCalendar(year)
		}
	}
	
	func downloadSittingCalendar(_ year: Int) async throws {
		Log.debug("Fetch.downloadSittingCalendar(year: \(year))")
		let dates = try await downloadCalendar(year: year)
		// Upsert: update existing record if present, insert if not
		let existing = try modelContext.fetch(FetchDescriptor<SittingCalendar>(predicate: #Predicate { $0.year == year }))
		if let record = existing.first {
			record.sittings = dates
		} else {
			let calendar = SittingCalendar(year: year, sittings: dates)
			modelContext.insert(calendar)
		}
		try modelContext.save()
	}

	func backgroundRefresh() async {
		Log.debug("Fetch.backgroundRefresh()")
		let year = Calendar.current.component(.year, from: Date())
		try? await downloadSittingCalendar(year)
	}

	func hansard(_ date: Date) async throws -> PersistentIdentifier {
		Log.debug("Fetch.hansard(date: \(date))")
		let fetched = try modelContext.fetchIdentifiers(FetchDescriptor<Hansard>(predicate: #Predicate { $0.date == date }))
		if let first = fetched.first {
			return first
		} else {
			try await downloadHansard(date)
			return try await hansard(date)
		}
	}
	
	func downloadHansard(_ date: Date) async throws {
		Log.debug("Fetch.downloadHansard(date: \(date))")
		let xml = try await downloadXML(forDate: date)
		let hansard = Hansard(xml: xml)
		modelContext.insert(hansard)
		try modelContext.save()
		UserDefaults.standard.set(Date(), forKey: "epac.sync.hansard")
	}

	func member(_ firstName: String, _ lastName: String) async throws -> ParliamentMember {
		Log.debug("Fetch.member(firstName: \(firstName), lastName: \(lastName))")
		let fetched = try modelContext.fetch(FetchDescriptor<ParliamentMember>(predicate: #Predicate { $0.firstName == firstName && $0.lastName == lastName }))
		if let first = fetched.first {
			return first
		} else {
			try await downloadMember(firstName, lastName)
			return try await self.member(firstName, lastName)
		}
	}

	func members() async throws -> [ParliamentMember] {
		Log.debug("Fetch.members()")
		let fetched = try modelContext.fetch(FetchDescriptor<ParliamentMember>())
		if !fetched.isEmpty {
			return fetched
		} else {
			try await downloadMembers()
			return try await self.members()
		}
	}

	func constituencies() async throws -> [Constituency] {
		Log.debug("Fetch.constituencies()")
		let fetched = try modelContext.fetch(FetchDescriptor<Constituency>())
		if !fetched.isEmpty {
			return fetched
		} else {
			try await downloadConstituencies()
			return try await self.constituencies()
		}
	}

	func expenditures(year: Int, quarter: Int) async throws {
		Log.debug("Fetch.expenditures(year: \(year), quarter: \(quarter))")
		let fetched = try modelContext.fetch(FetchDescriptor<SummaryExpenditure>(predicate: #Predicate { $0.year == year && $0.quarter == quarter }))
		if fetched.isEmpty {
			try await downloadExpenditures(year: year, quarter: quarter)
		}
	}

	func downloadExpenditures(year: Int, quarter: Int) async throws {
		Log.debug("Fetch.downloadExpenditures(year: \(year), quarter: \(quarter))")
		let path = String(format: expenditurePath, year, quarter)
		let url = hosturl.appending(path: path)
		let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
		let (data, _) = try await NetworkService.shared.data(for: request)

		guard let htmlstring = String(data: data, encoding: .utf8),
			  let doc = try? HTML(html: htmlstring, url: nil, encoding: .utf8) else {
			throw NSError(domain: "Fetch", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse HTML"])
		}
		
		let allLinks = doc.css("a")
		Log.debug("Found \(allLinks.count) links on the page")
		
		var csvURL: URL?
		
		// Try finding by class first (common pattern in this site)
		if let csvLinkElement = doc.css("a.btn-export-csv").first,
		   let href = csvLinkElement["href"],
		   let url = URL(string: href, relativeTo: hosturl) {
			csvURL = url
		}
		
		// Fallback to searching for .csv in href
		if csvURL == nil {
			if let csvLinkElement = allLinks.first(where: { $0["href"]?.lowercased().contains(".csv") == true }),
			   let href = csvLinkElement["href"],
			   let url = URL(string: href, relativeTo: hosturl) {
				csvURL = url
			}
		}
		
		// Final fallback: search for "CSV" in text
		if csvURL == nil {
			if let csvLinkElement = allLinks.first(where: { $0.text?.contains("CSV") == true }),
			   let href = csvLinkElement["href"],
			   let url = URL(string: href, relativeTo: hosturl) {
				csvURL = url
			}
		}

		guard let csvURL else {
			for link in allLinks.prefix(10) {
				Log.debug("Link: text='\(link.text ?? "")', href='\(link["href"] ?? "")'")
			}
			throw NSError(domain: "Fetch", code: 2, userInfo: [NSLocalizedDescriptionKey: "CSV link not found after checking \(allLinks.count) links"])
		}
		
		Log.debug("Found CSV URL: \(csvURL.absoluteString)")
		let (csvData, _) = try await NetworkService.shared.data(from: csvURL)
		Log.debug("Downloaded \(csvData.count) bytes of CSV data")
		
		let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("expenditures-\(year)-Q\(quarter).csv")
		try csvData.write(to: tempURL)
		
		let parser = CSVParser(file: tempURL)
		let stream = SummaryExpenditure.fromCSV(parser, year: year, quarter: quarter)
		
		var expenditures: [SummaryExpenditure] = []
		for await expenditure in stream {
			expenditures.append(expenditure)
		}
		
		// Parse detailed links from HTML
		let rows = doc.css("table tbody tr")
		Log.debug("Found \(rows.count) rows in HTML table")
		
		let existingExpenditures = try modelContext.fetch(FetchDescriptor<SummaryExpenditure>(predicate: #Predicate { $0.year == year && $0.quarter == quarter }))
		
		if !expenditures.isEmpty && !existingExpenditures.isEmpty {
			Log.debug("Summary data already exists for \(year) Q\(quarter), skipping insertion but updating links.")
		}
		
		for (index, row) in rows.enumerated() {
			let cells = row.css("td")
			if cells.count < 7 { continue }
			
			let nameText = cells[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			// The name in HTML is usually "LastName, FirstName"
			
			let targetExpenditures = expenditures.isEmpty ? existingExpenditures : expenditures
			if let match = targetExpenditures.first(where: { 
				let fullName = "\($0.lastName), \($0.firstName)"
				return nameText.caseInsensitiveCompare(fullName) == .orderedSame || nameText.contains($0.lastName) && nameText.contains($0.firstName)
			}) {
				var foundLink = false
				if let travelLink = cells[4].css("a").first?["href"] {
					match.travelURL = URL(string: travelLink, relativeTo: hosturl)?.absoluteString
					foundLink = true
				}
				if let hospitalityLink = cells[5].css("a").first?["href"] {
					match.hospitalityURL = URL(string: hospitalityLink, relativeTo: hosturl)?.absoluteString
					foundLink = true
				}
				if let contractsLink = cells[6].css("a").first?["href"] {
					match.contractsURL = URL(string: contractsLink, relativeTo: hosturl)?.absoluteString
					foundLink = true
				}
				if foundLink {
					Log.debug("Associated links for \(match.lastName) (\(match.firstName))")
				}
			} else if index < 5 && expenditures.count > 0 {
				Log.debug("Could not match HTML row \(index): '\(nameText)'")
			}
		}

		if !expenditures.isEmpty && existingExpenditures.isEmpty {
			for expenditure in expenditures {
				modelContext.insert(expenditure)
			}
			Log.debug("Inserted \(expenditures.count) new expenditures into database")
		}
		try modelContext.save()
		UserDefaults.standard.set(Date(), forKey: "epac.sync.expenditures")
		try? FileManager.default.removeItem(at: tempURL)
	}

	func downloadDetailedExpenditures(identifier: PersistentIdentifier) async throws {
		guard let expenditure = modelContext.model(for: identifier) as? SummaryExpenditure else {
			Log.error("Expenditure not found for identifier")
			return
		}
		
		// If URLs are missing, we might need to re-fetch the summary HTML to get them
		if expenditure.travelURL == nil && expenditure.hospitalityURL == nil && expenditure.contractsURL == nil {
			Log.debug("URLs missing for \(expenditure.lastName), attempting to re-fetch summary HTML")
			try await downloadExpenditures(year: expenditure.year, quarter: expenditure.quarter)
		}
		
		// Re-fetch to get updated URLs if they were just downloaded
		guard let updatedExpenditure = modelContext.model(for: identifier) as? SummaryExpenditure else {
			return
		}

		Log.debug("Fetch.downloadDetailedExpenditures for \(updatedExpenditure.lastName). TravelURL: \(updatedExpenditure.travelURL != nil), HospitalityURL: \(updatedExpenditure.hospitalityURL != nil), ContractsURL: \(updatedExpenditure.contractsURL != nil)")
		
		if let travelURL = updatedExpenditure.travelURL, let url = URL(string: travelURL) {
			try await downloadDetail(url: url, type: .travel, member: updatedExpenditure)
		}
		if let hospitalityURL = updatedExpenditure.hospitalityURL, let url = URL(string: hospitalityURL) {
			try await downloadDetail(url: url, type: .hospitality, member: updatedExpenditure)
		}
		if let contractsURL = updatedExpenditure.contractsURL, let url = URL(string: contractsURL) {
			try await downloadDetail(url: url, type: .contracts, member: updatedExpenditure)
		}
	}

	private enum DetailType {
		case travel, hospitality, contracts
	}

	private func downloadDetail(url: URL, type: DetailType, member: SummaryExpenditure) async throws {
		Log.debug("Downloading detail from \(url.absoluteString)")
		let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
		let (data, _) = try await NetworkService.shared.data(for: request)
		
		guard let htmlstring = String(data: data, encoding: .utf8),
			  let doc = try? HTML(html: htmlstring, url: nil, encoding: .utf8) else {
			Log.error("Failed to parse detail HTML from \(url.absoluteString)")
			return
		}
		
		let csvSelectors = ["a.btn-export-csv", "a.csv-btn.view-report-link"]
		var csvLinkElement: Kanna.XMLElement?
		for selector in csvSelectors {
			if let element = doc.css(selector).first {
				csvLinkElement = element
				Log.debug("Found CSV link using selector: \(selector)")
				break
			}
		}
		
		if csvLinkElement == nil {
			csvLinkElement = doc.css("a").first(where: { $0["href"]?.lowercased().contains(".csv") == true })
			if csvLinkElement != nil {
				Log.debug("Found CSV link by searching for .csv in href")
			}
		}

		guard let csvLinkElement = csvLinkElement,
			  let href = csvLinkElement["href"],
			  let csvURL = URL(string: href, relativeTo: hosturl) else {
			Log.error("CSV link not found in detail page \(url.absoluteString)")
			Log.debug("HTML content of failing page: \n\(htmlstring)")
			return
		}
		
		Log.debug("Found detailed CSV URL: \(csvURL.absoluteString)")
		let (csvData, _) = try await NetworkService.shared.data(from: csvURL)
		let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("detail-\(UUID().uuidString).csv")
		try csvData.write(to: tempURL)
		
		let parser = CSVParser(file: tempURL)
		var count = 0
		
		switch type {
		case .travel:
			let stream = TravelClaim.fromCSV(parser)
			for await claimData in stream {
				let claim = TravelClaim(
					claimID: claimData.claimID,
					startDate: claimData.startDate,
					endDate: claimData.endDate,
					transportation: claimData.transportation,
					accommodations: claimData.accommodations,
					mealsAndIncidentals: claimData.mealsAndIncidentals,
					total: claimData.total
				)
				claim.summary = member
				for detailData in claimData.details {
					let detail = TravelExpenditureDetail(
						travellerName: detailData.travellerName,
						travellerType: detailData.travellerType,
						purposeOfTravel: detailData.purposeOfTravel,
						date: detailData.date,
						departure: detailData.departure,
						destination: detailData.destination
					)
					detail.claim = claim
					claim.details.append(detail)
				}
				modelContext.insert(claim)
				count += 1
			}
		case .hospitality:
			let stream = HospitalityExpenditure.fromCSV(parser)
			for await itemData in stream { 
				let item = HospitalityExpenditure(
					date: itemData.date,
					location: itemData.location,
					totalOfAttendees: itemData.totalOfAttendees,
					purposeOfHospitality: itemData.purposeOfHospitality,
					total: itemData.total,
					typeOfEvent: itemData.typeOfEvent,
					claim: itemData.claim,
					supplier: itemData.supplier,
					memberID: 0,
					year: member.year,
					quarter: member.quarter
				)
				item.summary = member
				modelContext.insert(item)
				count += 1
			}
		case .contracts:
			let stream = ContractExpenditure.fromCSV(parser)
			for await itemData in stream { 
				let item = ContractExpenditure(
					supplier: itemData.supplier,
					details: itemData.details,
					date: itemData.date,
					total: itemData.total,
					memberID: 0,
					year: member.year,
					quarter: member.quarter
				)
				item.summary = member
				modelContext.insert(item)
				count += 1
			}
		}
		
		Log.debug("Inserted \(count) detailed items for \(type)")
		try modelContext.save()
		try? FileManager.default.removeItem(at: tempURL)
	}

	func downloadXML(forDate date: Date) async throws -> String {
		Log.debug("Fetch.downloadXML(date: \(date))")
		let url = hosturl.appending(path: dailyPath).appending(path: DateUtils.getCSVStringFromDate(date))
		var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
		var (data, _) = try await NetworkService.shared.data(for: request)
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
		guard let url = URL(string: href, relativeTo: hosturl) else {
			throw NSError(domain: "", code: 6)
		}
		request = URLRequest(url: url)
		(data, _) = try await NetworkService.shared.data(for: request)
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
		guard let xmllink = URL(string: href, relativeTo: hosturl) else {
			throw NSError(domain: "", code: 6)
		}
		request = URLRequest(url: xmllink, cachePolicy: .reloadIgnoringLocalCacheData)
		(data, _) = try await NetworkService.shared.data(for: request)
		guard let utfstringvalue = String(data: data, encoding: .utf8) else {
			throw NSError(domain: "", code: 7)
		}
		return utfstringvalue
	}

	func downloadCalendar(year: Int) async throws -> [Date] {
		Log.debug("Fetch.downloadCalendar(year: \(year))")
		Log.debug("Downloading calendar \(year)")
		let path = String(format: calendarPath, year)
		let request = URLRequest(url: hosturl.appending(path: path), cachePolicy: .reloadIgnoringLocalCacheData)
		let (data, _) = try await NetworkService.shared.data(for: request)
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
			// Write next sitting to App Group for widget. No-op if App Group is not registered.
			let nextSitting = dates.filter { $0 >= Calendar.current.startOfDay(for: Date()) }.last
			WidgetDataWriter.writeNextSitting(nextSitting)
			WidgetDataWriter.reloadWidgets()
			return dates
		} else {
			return []
		}

	}

	func downloadMembers() async throws {
		Log.debug("Fetch.downloadMembers()")
		guard let url = URL(string: membersPath, relativeTo: hosturl) else {
			throw NSError(domain: "", code: 6)
		}
		let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
		let (data, _) = try await NetworkService.shared.data(for: request)
		Log.debug("got data \(data.count)")
		guard let utfstringvalue = String(data: data, encoding: .utf8) else {
			throw NSError(domain: "", code: 7)
		}
		Log.debug("Got XML string")
		let members = XMLBro.parseMembers(utfstringvalue)
		Log.debug("parsed XML \(members.count) members")
		let existingMembers = try modelContext.fetch(FetchDescriptor<ParliamentMember>())
		Log.debug("Found \(existingMembers.count) existing members")
		let existingNames = Set(existingMembers.map { $0.name })

		Log.debug("Inserting members")
		try? modelContext.transaction {
			for member in members {
				if !existingNames.contains(member.name) {
					modelContext.insert(member)
				}
			}
		}
	}
	                func downloadMember(_ firstName: String, _ lastName: String) async throws {
	                        let identifier = "\(firstName) \(lastName)"
	                        guard !downloadsInProgress.contains(identifier), !failedDownloads.contains(identifier) else {
	                                return
	                        }
	                        downloadsInProgress.insert(identifier)
	                        defer { downloadsInProgress.remove(identifier) }
	        
	                        Log.debug("Fetch.downloadMember(firstName: \(firstName), lastName: \(lastName))")
	                        let url = hosturl.appending(path: membersSearchPath)
	                        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
	                        request.httpMethod = "POST"
	                        request.httpBody = try! JSONSerialization.data(withJSONObject: ["searchText": "\(firstName) \(lastName)"])
	                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
	                        request.setValue("application/json", forHTTPHeaderField: "Accept")
	                        let (data, _) = try await NetworkService.shared.data(for: request)
	                        guard let responseBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
	                                failedDownloads.insert(identifier)
	                                throw NSError(domain: "", code: 7)
	                        }
	                        let pastMembers = responseBody["pastMembers"] as? [[String: Any]] ?? []
	                        let currentMembers = responseBody["currentMembers"] as? [[String: Any]] ?? []
	                        let allMembers = currentMembers + pastMembers
	        
	                        if let member = allMembers.first {
	                                let name = "\(firstName) \(lastName)"
	                                let personID = member["personId"] as? Int ?? 0
	                                let existing = try? modelContext.fetch(FetchDescriptor<ParliamentMember>(predicate: #Predicate { $0.name == name })).first
	                                if existing == nil {
	                                        let mp = ParliamentMember(
	                                                name: name,
	                                                lastName: lastName,
	                                                firstName: firstName,
	                                                photoURL: URL(string: member["officialPhotoUrl"] as! String, relativeTo: hosturl)!,
	                                                riding: member["constituencyNameEn"] as! String,
	                                                province: Province(rawValue: (member["provinceNameEn"] as? String) ?? "") ?? .Ontario,
	                                                party: Party.partyWithAbbreviation((member["caucusAbbreviationEn"] as! String).trimmingCharacters(in: .alphanumerics.inverted)),
	                                                memberID: personID
	                                        )
	                                        modelContext.insert(mp)
	                                        try modelContext.save()
	                                }
	                        } else {
	                                failedDownloads.insert(identifier)
	                        }
	                }
	        

	func downloadConstituencies() async throws {
		Log.debug("Fetch.downloadConstituencies()")
		guard let url = URL(string: constituenciesPath, relativeTo: hosturl) else {
			throw NSError(domain: "", code: 6)
		}
		let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
		let (data, _) = try await NetworkService.shared.data(for: request)
		guard let utfstringvalue = String(data: data, encoding: .utf8) else {
			throw NSError(domain: "", code: 7)
		}
		let constituencies = XMLBro.parseConstituencies(utfstringvalue)
		constituencies.forEach { modelContext.insert($0) }
		try modelContext.save()
	}

	func downloadMemberContact(identifier: PersistentIdentifier) async throws {
		guard let member = modelContext.model(for: identifier) as? ParliamentMember,
			  member.memberID > 0,
			  !member.contactFetched else { return }
		let first = member.firstName.lowercased()
			.replacingOccurrences(of: " ", with: "-")
			.folding(options: .diacriticInsensitive, locale: .current)
		let last = member.lastName.lowercased()
			.replacingOccurrences(of: " ", with: "-")
			.folding(options: .diacriticInsensitive, locale: .current)
		let path = String(format: memberPath, first, last, String(member.memberID))
		guard let url = URL(string: path, relativeTo: hosturl) else { return }
		let (data, response) = try await NetworkService.shared.data(from: url)
		guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
			  let xmlString = String(data: data, encoding: .utf8) else { return }
		let contact = XMLBro.parseMemberContact(xmlString)
		member.email = contact.email
		member.hillPhone = contact.hillPhone
		member.constituencyPhone = contact.constituencyPhone
		member.constituencyAddress = contact.constituencyAddress
		member.contactFetched = true
		try? modelContext.save()
	}

	func downloadVotingRecords(parliament: Int = 44) async throws {
		guard (try modelContext.fetchCount(FetchDescriptor<RecordedVote>())) == 0 else { return }

		var page = 1
		var hasMore = true
		let isoFormatter = ISO8601DateFormatter()
		isoFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
		while hasMore {
			var components = URLComponents(url: openAPIURL, resolvingAgainstBaseURL: false)!
			components.path = "/ocd/votes/"
			components.queryItems = [
				URLQueryItem(name: "parliament", value: String(parliament)),
				URLQueryItem(name: "pageSize", value: "200"),
				URLQueryItem(name: "page", value: String(page)),
				URLQueryItem(name: "format", value: "json")
			]
			guard let url = components.url else { break }
			let (data, response) = try await NetworkService.shared.data(from: url)
			guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
				  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
				  let items = json["items"] as? [[String: Any]] else { break }
			hasMore = !items.isEmpty && items.count == 200
			page += 1
			for item in items {
				guard let id = item["id"] as? Int else { continue }
				let dateStr = item["date"] as? String ?? ""
				let date = isoFormatter.date(from: dateStr) ?? Date()
				let descObj = item["description"] as? [String: String]
				let desc = descObj?["en"] ?? item["description"] as? String ?? ""
				let resultObj = item["result"] as? [String: String]
				let result = resultObj?["en"] ?? item["result"] as? String ?? ""
				let vote = RecordedVote(
					voteID: id,
					parliament: item["parliament"] as? Int ?? parliament,
					session: item["session"] as? Int ?? 0,
					number: item["number"] as? Int ?? 0,
					date: date,
					descriptionEn: desc,
					billNumberCode: item["billNumberCode"] as? String ?? "",
					yea: item["yea"] as? Int ?? 0,
					nay: item["nay"] as? Int ?? 0,
					paired: item["paired"] as? Int ?? 0,
					resultEn: result
				)
				modelContext.insert(vote)
			}
			try modelContext.save()
			UserDefaults.standard.set(Date(), forKey: "epac.sync.votes")
		}
	}

	func downloadMemberVotes(memberID: Int) async throws {
		let existing = try modelContext.fetch(FetchDescriptor<MemberVote>(
			predicate: #Predicate { $0.memberID == memberID }
		))
		guard existing.isEmpty else { return }

		var page = 1
		var hasMore = true
		while hasMore {
			var components = URLComponents(url: openAPIURL, resolvingAgainstBaseURL: false)!
			components.path = "/ocd/members/\(memberID)/votes/"
			components.queryItems = [
				URLQueryItem(name: "pageSize", value: "200"),
				URLQueryItem(name: "page", value: String(page)),
				URLQueryItem(name: "format", value: "json")
			]
			guard let url = components.url else { break }
			let (data, response) = try await NetworkService.shared.data(from: url)
			guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
				  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
				  let items = json["items"] as? [[String: Any]] else { break }
			hasMore = !items.isEmpty && items.count == 200
			page += 1
			for item in items {
				guard let voteID = item["voteId"] as? Int,
					  let ballot = item["recordedVote"] as? String else { continue }
				let mv = MemberVote(voteID: voteID, memberID: memberID, recordedVote: ballot)
				// link to RecordedVote if already stored
				mv.vote = try? modelContext.fetch(FetchDescriptor<RecordedVote>(
					predicate: #Predicate { $0.voteID == voteID }
				)).first
				modelContext.insert(mv)
			}
			try modelContext.save()
		}
	}
}
