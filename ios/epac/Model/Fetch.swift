//
//  Fetch.swift
//  epac
//
//  Created by Sunny on 2024-12-12.
//

import Foundation
import Kanna
import Sentry
import SwiftData
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
	private let openAPIURL = URL(string: "https://api.openparliament.ca")!
	private let openParliamentAPIURL = URL(string: "https://api.openparliament.ca")!
	private let votePageSize = 200

	private enum VotingEndpoint {
		case openCommons
		case openParliament
	}
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
		try? await downloadSittingCalendar(year - 1)
		try? await downloadFiscalMonitorEntries()
		try? loadCabinetPositions()
		await refreshNearbyHansardsForNotifications()
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

	private func refreshNearbyHansardsForNotifications() async {
		let topicEnabled = await MainActor.run {
			NotificationPreferenceStore.shared.topicConsultations && !TopicFollowStore.shared.followedIDs.isEmpty
		}
		guard topicEnabled else { return }

		let cal = Calendar.current
		let today = cal.startOfDay(for: Date())
		let minDate = cal.date(byAdding: .day, value: -2, to: today) ?? today
		let maxDate = cal.date(byAdding: .day, value: 1, to: today) ?? today

		let calendars = (try? modelContext.fetch(FetchDescriptor<SittingCalendar>())) ?? []
		let allSittings = Set(calendars.flatMap(\.sittings))
		let targetSittings = allSittings
			.map { cal.startOfDay(for: $0) }
			.filter { $0 >= minDate && $0 <= maxDate }
			.sorted(by: >)

		guard !targetSittings.isEmpty else { return }

		let existingHansards = Set(
			(try? modelContext.fetch(FetchDescriptor<Hansard>()).map { cal.startOfDay(for: $0.date) }) ?? []
		)

		for date in targetSittings {
			guard !existingHansards.contains(date) else { continue }
			do {
				let identifier = try await hansard(date)
				guard let hansard = modelContext.model(for: identifier) as? Hansard else { continue }
				let subjects = hansard.orders.flatMap { $0.subjects }.map {
					(title: $0.title, date: hansard.date)
				}
				let titles = hansard.orders.flatMap { $0.subjects }.map(\.title)
				await MainActor.run {
					TopicNotificationScheduler.checkAndNotify(subjectTitles: subjects)
					WidgetDataWriter.writeRecentSubjects(titles)
					WidgetDataWriter.reloadWidgets()
				}
				Log.debug("Background refresher downloaded Hansard for \(DateUtils.getCSVStringFromDate(date))")
			} catch {
				Log.debug("Background refresher failed to download \(DateUtils.getCSVStringFromDate(date)): \(error.localizedDescription)")
			}
		}
	}
	
	func downloadHansard(_ date: Date) async throws {
		Log.debug("Fetch.downloadHansard(date: \(date))")
		let transaction = SentrySDK.startTransaction(name: "hansard.sync", operation: "fetch.hansard")
		do {
			let xml = try await downloadXML(forDate: date)
			let hansard = Hansard(domain: XMLBro(xml: xml).parseXML().hansard())
			modelContext.insert(hansard)
			try modelContext.save()
			UserDefaults.standard.set(Date(), forKey: "epac.sync.hansard")
			transaction.finish(status: .ok)
		} catch {
			transaction.finish(status: .internalError)
			throw error
		}
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

	func fiscalMonitorEntries() async throws {
		Log.debug("Fetch.fiscalMonitorEntries()")
		let fetched = try modelContext.fetch(FetchDescriptor<FiscalMonitorEntry>())
		if fetched.isEmpty || shouldRefreshFiscalMonitor() {
			try await downloadFiscalMonitorEntries()
		}
	}

	func downloadFiscalMonitorEntries() async throws {
		Log.debug("Fetch.downloadFiscalMonitorEntries()")
		let parsedEntries = try await FiscalMonitorService().currentFiscalYearEntries()
		guard !parsedEntries.isEmpty else { return }

		let existing = try modelContext.fetch(FetchDescriptor<FiscalMonitorEntry>())
		for entry in existing where entry.fiscalYearStart == parsedEntries[0].fiscalYearStart {
			modelContext.delete(entry)
		}

		for parsed in parsedEntries {
			modelContext.insert(FiscalMonitorEntry(
				fiscalYearStart: parsed.fiscalYearStart,
				month: parsed.month,
				monthName: parsed.monthName,
				periodDate: parsed.periodDate,
				publicationDate: parsed.publicationDate,
				revenueMillions: parsed.revenueMillions,
				programExpenseMillions: parsed.programExpenseMillions,
				publicDebtChargesMillions: parsed.publicDebtChargesMillions,
				netActuarialLossesMillions: parsed.netActuarialLossesMillions,
				budgetaryBalanceMillions: parsed.budgetaryBalanceMillions,
				yearToDateBudgetaryBalanceMillions: parsed.yearToDateBudgetaryBalanceMillions,
				annualBudgetProjectionMillions: parsed.annualBudgetProjectionMillions,
				sourceTitle: parsed.sourceTitle,
				sourceURL: parsed.sourceURL
			))
		}
		try modelContext.save()
		UserDefaults.standard.set(Date(), forKey: "epac.sync.fiscalMonitor")
	}

	private func shouldRefreshFiscalMonitor() -> Bool {
		guard let lastSync = UserDefaults.standard.object(forKey: "epac.sync.fiscalMonitor") as? Date else {
			return true
		}
		return Date().timeIntervalSince(lastSync) > 60 * 60 * 24
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
			} else if index < 5 && !expenditures.isEmpty {
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
			} else if text.contains("projected") {
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
				guard let date = classes.compactMap(DateUtils.parseCSVDateString).first else {
					continue
				}
				dates.append(date)
			}
			dates.sort(by: >)
			UserDefaults.standard.set(dates, forKey: "calendardates_v2")
			// Write next sitting to App Group for widget. No-op if App Group is not registered.
			let nextSitting = dates.filter { $0 >= Calendar.current.startOfDay(for: Date()) }.last
			WidgetDataWriter.writeNextSitting(nextSitting)
			WidgetDataWriter.writeParliamentStatus(sittingDates: dates)
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
		let memberDTOs = XMLBro.parseMembers(utfstringvalue)
		Log.debug("parsed XML \(memberDTOs.count) members")
		let existingMembers = try modelContext.fetch(FetchDescriptor<ParliamentMember>())
		Log.debug("Found \(existingMembers.count) existing members")
		let existingNames = Set(existingMembers.map { $0.name })

		Log.debug("Inserting members")
		try? modelContext.transaction {
			for dto in memberDTOs {
				if !existingNames.contains(dto.name) {
					modelContext.insert(ParliamentMember(domain: dto))
				}
			}
		}
		UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "epac.sync.members")
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
	                        // [String: String] is always JSON-serializable; force-try here is safe by construction.
	                        // swiftlint:disable:next force_try
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
	                                        let dto = ParliamentMemberDTO(
	                                                name: name,
	                                                memberID: personID,
	                                                lastName: lastName,
	                                                firstName: firstName,
	                                                // ourcommons.ca members search response shape is part of the API contract; a missing
                                                // field here means the API broke and we want to fail loudly. Replace with guard-let
                                                // when the upstream API stabilises around a typed schema.
                                                // swiftlint:disable force_cast
                                                photoURL: URL(string: member["officialPhotoUrl"] as! String, relativeTo: hosturl)!,
	                                                riding: member["constituencyNameEn"] as! String,
	                                                province: Province(rawValue: (member["provinceNameEn"] as? String) ?? "") ?? .Ontario,
	                                                party: Party.partyWithAbbreviation((member["caucusAbbreviationEn"] as! String).trimmingCharacters(in: .alphanumerics.inverted)),
	                                                websiteURL: nil,
	                                                imageData: nil,
                                                // swiftlint:enable force_cast
	                                                fromDateTime: nil,
	                                                toDateTime: nil,
	                                                email: nil,
	                                                hillPhone: nil,
	                                                constituencyPhone: nil,
	                                                constituencyAddress: nil,
	                                                contactFetched: false
	                                        )
	                                        modelContext.insert(ParliamentMember(domain: dto))
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
		let constituencyDTOs = XMLBro.parseConstituencies(utfstringvalue)
		constituencyDTOs.map(Constituency.init(domain:)).forEach { modelContext.insert($0) }
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
		if try modelContext.fetchCount(FetchDescriptor<RecordedVote>()) > 0 {
			writeLatestVoteSummaryForWidgets()
			return
		}

		let transaction = SentrySDK.startTransaction(name: "votes.sync", operation: "fetch.votes")
		do {
			do {
				try await fetchVotingRecords(parliament: parliament, from: .openCommons)
			} catch {
				if shouldFallbackVotes(error: error),
				   try modelContext.fetchCount(FetchDescriptor<RecordedVote>()) == 0 {
					Log.debug("downloadVotingRecords: falling back to openparliament API due legacy host error: \(error.localizedDescription)")
					try await fetchVotingRecords(parliament: parliament, from: .openParliament)
				} else {
					throw error
				}
			}
			writeLatestVoteSummaryForWidgets()
			transaction.finish(status: .ok)
		} catch {
			transaction.finish(status: .internalError)
			throw error
		}
	}

	private func writeLatestVoteSummaryForWidgets() {
		let descriptor = FetchDescriptor<RecordedVote>(
			sortBy: [SortDescriptor(\RecordedVote.date, order: .reverse)]
		)
		guard let vote = try? modelContext.fetch(descriptor).first else { return }
		let title = vote.descriptionEn.isEmpty ? "Vote #\(vote.number)" : vote.descriptionEn
		WidgetDataWriter.writeLastVote(
			title: title,
			billNumber: vote.billNumberCode,
			result: vote.resultEn,
			date: vote.date,
			yea: vote.yea,
			nay: vote.nay
		)
		WidgetDataWriter.reloadWidgets()
	}

	/// Force-refreshes vote history for a member by deleting stored votes and re-downloading.
	func refreshMemberVotes(memberID: Int) async throws {
		let existing = try modelContext.fetch(FetchDescriptor<MemberVote>(
			predicate: #Predicate { $0.memberID == memberID }
		))
		for vote in existing { modelContext.delete(vote) }
		try modelContext.save()
		try await downloadMemberVotes(memberID: memberID)
	}

	func downloadMemberVotes(memberID: Int) async throws {
		let existing = try modelContext.fetch(FetchDescriptor<MemberVote>(
			predicate: #Predicate { $0.memberID == memberID }
		))
		guard existing.isEmpty else { return }

		do {
			try await downloadMemberVotes(memberID: memberID, from: .openCommons)
		} catch {
			if shouldFallbackVotes(error: error),
			   try modelContext.fetchCount(FetchDescriptor<MemberVote>(predicate: #Predicate { $0.memberID == memberID })) == 0 {
				Log.debug("downloadMemberVotes(\(memberID)): falling back to openparliament API due legacy host error: \(error.localizedDescription)")
				try await downloadMemberVotes(memberID: memberID, from: .openParliament)
			} else {
				throw error
			}
		}
	}

	private func fetchVotingRecords(parliament: Int, from source: VotingEndpoint) async throws {
		var page = 1
		var hasMore = true
		let isoFormatter = ISO8601DateFormatter()
		isoFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
		while hasMore {
			let (voteItems, continuePagination) = try await loadVotingPage(
				parliament: parliament,
				page: page,
				from: source,
				isoFormatter: isoFormatter
			)
			for vote in voteItems {
				modelContext.insert(vote)
			}
			hasMore = continuePagination
			page += 1
		}
		try modelContext.save()
	}

	private func downloadMemberVotes(memberID: Int, from source: VotingEndpoint) async throws {
		var page = 1
		var hasMore = true
		while hasMore {
			let (votes, continuePagination) = try await loadMemberVotes(
				memberID: memberID,
				page: page,
				from: source
			)
			for (voteID, ballot) in votes {
				let memberVote = MemberVote(voteID: voteID, memberID: memberID, recordedVote: ballot)
				memberVote.vote = try? modelContext.fetch(FetchDescriptor<RecordedVote>(
					predicate: #Predicate { $0.voteID == voteID }
				)).first
				modelContext.insert(memberVote)
			}
			try modelContext.save()
			hasMore = continuePagination
			page += 1
		}
	}

	private func shouldFallbackVotes(error: Error) -> Bool {
		if let nsError = error as? URLError {
			switch nsError.code {
			case .cannotFindHost, .cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost:
				return true
			default:
				return false
			}
		}
		return false
	}

	private func loadVotingPage(
		parliament: Int,
		page: Int,
		from source: VotingEndpoint,
		isoFormatter: ISO8601DateFormatter
	) async throws -> (votes: [RecordedVote], hasMore: Bool) {
		let components: URLComponents = {
			switch source {
			case .openCommons:
				var components = URLComponents(url: openAPIURL, resolvingAgainstBaseURL: false)!
				components.path = "/ocd/votes/"
				components.queryItems = [
					URLQueryItem(name: "parliament", value: String(parliament)),
					URLQueryItem(name: "pageSize", value: String(votePageSize)),
					URLQueryItem(name: "page", value: String(page)),
					URLQueryItem(name: "format", value: "json")
				]
				return components
			case .openParliament:
				var components = URLComponents(url: openParliamentAPIURL, resolvingAgainstBaseURL: false)!
				components.path = "/votes/"
				let offset = max(0, (page - 1) * votePageSize)
				components.queryItems = [
					URLQueryItem(name: "parliament", value: String(parliament)),
					URLQueryItem(name: "limit", value: String(votePageSize)),
					URLQueryItem(name: "offset", value: String(offset)),
					URLQueryItem(name: "format", value: "json")
				]
				return components
			}
		}()

		guard let url = components.url else { return ([], false) }
		let (data, response) = try await NetworkService.shared.data(from: url)
		guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
			  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			return ([], false)
		}

		switch source {
		case .openCommons:
			guard let items = json["items"] as? [[String: Any]] else { return ([], false) }
			let votes = items.compactMap { parseOpenCommonsVote($0, parliament: parliament, isoFormatter: isoFormatter) }
			return (votes, !votes.isEmpty && votes.count == votePageSize)
			case .openParliament:
				guard let objects = json["objects"] as? [[String: Any]] else { return ([], false) }
				let votes = objects.compactMap { parseOpenParliamentVote($0, isoFormatter: isoFormatter) }
				let nextURL = (json["pagination"] as? [String: Any])?["next_url"] as? String
				return (votes, nextURL?.isEmpty == false)
		}
	}

	private func parseOpenCommonsVote(_ item: [String: Any], parliament: Int, isoFormatter: ISO8601DateFormatter) -> RecordedVote? {
		guard let id = item["id"] as? Int else { return nil }
		let dateStr = item["date"] as? String ?? ""
		let date = isoFormatter.date(from: dateStr) ?? Date()
		let descObj = item["description"] as? [String: String]
		let desc = descObj?["en"] ?? item["description"] as? String ?? ""
		let resultObj = item["result"] as? [String: String]
		let result = resultObj?["en"] ?? item["result"] as? String ?? ""
		return RecordedVote(
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
	}

	private func parseOpenParliamentVote(_ item: [String: Any], isoFormatter: ISO8601DateFormatter) -> RecordedVote? {
		guard let number = item["number"] as? Int,
			  let sessionText = item["session"] as? String else { return nil }
		let (voteParliament, session) = parseSessionComponents(from: sessionText)
		let voteID = makeStableVoteID(parliament: voteParliament, session: session, number: number)
		let dateStr = item["date"] as? String ?? ""
		let date = isoFormatter.date(from: dateStr) ?? Date()
		let descObj = item["description"] as? [String: Any]
		let desc = descObj?["en"] as? String ?? ""
		let result = item["result"] as? String ?? ""
		let bill = item["bill_url"] as? String
		return RecordedVote(
			voteID: voteID,
			parliament: voteParliament,
			session: session,
			number: number,
			date: date,
			descriptionEn: desc,
			billNumberCode: openParliamentBillCode(from: bill),
			yea: item["yea_total"] as? Int ?? 0,
			nay: item["nay_total"] as? Int ?? 0,
			paired: item["paired_total"] as? Int ?? 0,
			resultEn: result
		)
	}

	private func loadMemberVotes(
		memberID: Int,
		page: Int,
		from source: VotingEndpoint
	) async throws -> (votes: [(voteID: Int, ballot: String)], hasMore: Bool) {
		let politicianSlug: String?
		if source == .openParliament {
			politicianSlug = await openParliamentSlug(for: memberID)
		} else {
			politicianSlug = nil
		}

		let components: URLComponents = {
			switch source {
			case .openCommons:
				var components = URLComponents(url: openAPIURL, resolvingAgainstBaseURL: false)!
				components.path = "/ocd/members/\(memberID)/votes/"
				components.queryItems = [
					URLQueryItem(name: "pageSize", value: String(votePageSize)),
					URLQueryItem(name: "page", value: String(page)),
					URLQueryItem(name: "format", value: "json")
				]
				return components
			case .openParliament:
				var components = URLComponents(url: openParliamentAPIURL, resolvingAgainstBaseURL: false)!
				let offset = max(0, (page - 1) * votePageSize)
				let slug = politicianSlug ?? ""
				components.path = "/votes/ballots/"
				components.queryItems = [
					URLQueryItem(name: "politician", value: slug),
					URLQueryItem(name: "limit", value: String(votePageSize)),
					URLQueryItem(name: "offset", value: String(offset)),
					URLQueryItem(name: "format", value: "json")
				]
				return components
			}
		}()

		guard let url = components.url else { return ([], false) }
		let (data, response) = try await NetworkService.shared.data(from: url)
		guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
			  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			return ([], false)
		}

		switch source {
		case .openCommons:
			guard let items = json["items"] as? [[String: Any]] else { return ([], false) }
			let votes = items.compactMap { item -> (Int, String)? in
				guard let voteID = item["voteId"] as? Int,
					  let ballot = item["recordedVote"] as? String else { return nil }
				return (voteID, ballot)
			}
			return (votes, !votes.isEmpty && votes.count == votePageSize)
		case .openParliament:
			guard let items = json["objects"] as? [[String: Any]] else { return ([], false) }
			let votes = items.compactMap { item -> (Int, String)? in
				guard let ballotRaw = item["ballot"] as? String,
					  let vote = openParliamentBallotID(from: item["vote_url"] as? String ?? "") else {
					return nil
				}
				return (vote, normalizedBallot(ballotRaw))
			}
			let nextURL = (json["pagination"] as? [String: Any])?["next_url"] as? String
			return (votes, nextURL?.isEmpty == false)
		}
	}

	private func openParliamentSlug(for memberID: Int) async -> String {
		// Open a conservative fallback: start with ourcommons-style slug and then look up a
		// matching politician page if the guessed slug is not available.
		guard let member = try? modelContext.fetch(FetchDescriptor<ParliamentMember>(
			predicate: #Predicate { $0.memberID == memberID }
		)).first else { return "" }
		let fallbackID = openParliamentSlug(firstName: member.firstName, lastName: member.lastName)
		if await openParliamentSlugMatches(memberID: memberID, slug: fallbackID) {
			return fallbackID
		}
		return await openParliamentSearchSlug(memberID: memberID, firstName: member.firstName, lastName: member.lastName) ?? fallbackID
	}

	private func openParliamentSlug(firstName: String, lastName: String) -> String {
		return "\(firstName)-\(lastName)"
			.lowercased()
			.folding(options: .diacriticInsensitive, locale: .current)
			.replacingOccurrences(of: " ", with: "-")
			.filter { $0.isLetter || $0 == "-" }
	}

	private func openParliamentSlugMatches(memberID: Int, slug: String) async -> Bool {
		guard !slug.isEmpty else { return false }
		guard let url = URL(string: "/politicians/\(slug)/?format=json", relativeTo: openParliamentAPIURL) else { return false }
		guard let (data, response) = try? await NetworkService.shared.data(from: url),
			  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
			  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			return false
		}
		return openParliamentOtherInfoMemberIDs(json).contains(String(memberID))
	}

	private func openParliamentSearchSlug(memberID: Int, firstName: String, lastName: String) async -> String? {
		guard let components = makePoliticianSearchComponents(
			firstName: firstName,
			lastName: lastName
		),
			  let url = components.url else { return nil }

		guard let (data, response) = try? await NetworkService.shared.data(from: url),
			  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
			  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let objects = json["objects"] as? [[String: Any]] else {
			return nil
		}

		for item in objects {
			guard let url = item["url"] as? String else { continue }
			if openParliamentOtherInfoMemberIDs(item).contains(String(memberID)) {
				let slug = url.split(separator: "/").last.map(String.init)
				return slug?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
			}
		}
		return nil
	}

	private func makePoliticianSearchComponents(firstName: String, lastName: String) -> URLComponents? {
		guard var components = URLComponents(url: openParliamentAPIURL, resolvingAgainstBaseURL: false) else { return nil }
		components.path = "/politicians/"
		components.queryItems = [
			URLQueryItem(name: "q", value: "\(firstName) \(lastName)"),
			URLQueryItem(name: "format", value: "json"),
			URLQueryItem(name: "limit", value: String(votePageSize)),
			URLQueryItem(name: "page", value: "1")
		]
		return components
	}

	private func openParliamentOtherInfoMemberIDs(_ object: [String: Any]) -> [String] {
		guard let otherInfo = object["other_info"] as? [String: Any],
			  let ids = otherInfo["parl_mp_id"] as? [String] else {
			return []
		}
		return ids
	}

	private func normalizedBallot(_ rawBallot: String) -> String {
		switch rawBallot.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
		case "yes", "for", "aye":
			return "Yea"
		case "no", "against":
			return "Nay"
		case "paired":
			return "Paired"
		case "abstain", "absent":
			return "Abstained"
		default:
			return rawBallot
		}
	}

	private func makeStableVoteID(parliament: Int, session: Int, number: Int) -> Int {
		let safeParliament = max(0, parliament)
		let safeSession = max(0, session)
		let safeNumber = max(0, number)
		return (safeParliament * 1_000_000) + (safeSession * 10_000) + safeNumber
	}

	private func parseSessionComponents(from session: String) -> (Int, Int) {
		let parts = session.split(separator: "-")
		guard parts.count >= 2,
			  let parliament = Int(parts[0]),
			  let sessionNum = Int(parts[1]) else {
			return (0, 0)
		}
		return (parliament, sessionNum)
	}

	private func openParliamentBillCode(from url: String?) -> String {
		guard let url else { return "" }
		let trimmed = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		let segments = trimmed.split(separator: "/")
		guard let last = segments.last, !last.isEmpty, !segments.isEmpty else { return "" }
		return String(last)
	}

	private func openParliamentBallotID(from voteURL: String) -> Int? {
		let trimmed = voteURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		let segments = trimmed.split(separator: "/")
		guard segments.count >= 3,
			  segments[0] == "votes",
			  let vote = Int(segments.last ?? ""),
			  let (parliament, session) = Optional(parseSessionComponents(from: String(segments[1]))) else {
			return nil
		}
		return makeStableVoteID(parliament: parliament, session: session, number: vote)
	}

	func downloadWrittenQuestions(memberID: Int, parliament: Int = 45) async throws {
		let existing = try modelContext.fetch(FetchDescriptor<WrittenQuestion>(
			predicate: #Predicate { $0.memberID == memberID }
		))
		guard existing.isEmpty else { return }

		let isoFormatter = ISO8601DateFormatter()
		isoFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]

		var page = 1
		var hasMore = true
		while hasMore {
			var components = URLComponents(url: openAPIURL, resolvingAgainstBaseURL: false)!
			components.path = "/ocd/questions/"
			components.queryItems = [
				URLQueryItem(name: "parliament", value: String(parliament)),
				URLQueryItem(name: "memberId", value: String(memberID)),
				URLQueryItem(name: "pageSize", value: "100"),
				URLQueryItem(name: "page", value: String(page)),
				URLQueryItem(name: "format", value: "json")
			]
			guard let url = components.url else { break }
			let (data, response) = try await NetworkService.shared.data(from: url)
			guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
				  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
				  let items = json["items"] as? [[String: Any]] else { break }
			hasMore = !items.isEmpty && items.count == 100
			page += 1
			for item in items {
				guard let id = item["id"] as? Int else { continue }
				let dateStr = item["dateSubmitted"] as? String ?? ""
				let date = isoFormatter.date(from: dateStr) ?? Date()
				let responseDateStr = item["responseDate"] as? String
				let responseDate = responseDateStr.flatMap { isoFormatter.date(from: $0) }
				let q = WrittenQuestion(
					questionID: id,
					memberID: memberID,
					parliament: item["parliament"] as? Int ?? parliament,
					session: item["session"] as? Int ?? 0,
					number: item["questionNumber"] as? Int ?? 0,
					dateSubmitted: date,
					subject: item["subject"] as? String ?? "",
					questionTextEn: item["textEn"] as? String ?? item["text"] as? String ?? "",
					statusEn: item["statusEn"] as? String ?? item["status"] as? String ?? "Pending",
					responseDate: responseDate,
					responseTextEn: item["responseTextEn"] as? String ?? item["responseText"] as? String,
					daysElapsed: item["daysElapsed"] as? Int ?? 0
				)
				modelContext.insert(q)
			}
			try modelContext.save()
		}
	}

	// MARK: - Cabinet positions

	// Loads the bundled cabinet snapshot into SwiftData. Re-seeds on every call:
	// the source file is a small (~28-row) snapshot regenerated whenever Cabinet
	// changes, and replacement is simpler than diffing portfolios across shuffles.
	func loadCabinetPositions() throws {
		Log.debug("Fetch.loadCabinetPositions()")
		let snapshot = try CabinetService().loadSnapshot()
		let asOfDate = (try? CabinetService.parseAsOfDate(snapshot.asOfDate)) ?? Date()

		let existing = try modelContext.fetch(FetchDescriptor<CabinetPosition>())
		for entry in existing {
			modelContext.delete(entry)
		}

		for position in snapshot.positions {
			modelContext.insert(CabinetPosition(
				ministerName: position.ministerName,
				firstName: position.firstName,
				lastName: position.lastName,
				portfolio: position.portfolio,
				isPrimeMinister: position.isPrimeMinister ?? false,
				mandateLetterURL: position.mandateLetterURL,
				sourceTitle: snapshot.source.title,
				sourceURL: snapshot.source.url,
				asOfDate: asOfDate
			))
		}
		try modelContext.save()
	}

	// Best-effort seeding: only loads on first launch (or after a wipe). The JSON
	// is bundled with the app, so this is a synchronous decode + write — fast
	// enough to run during startup without blocking the UI.
	func ensureCabinetPositionsSeeded() throws {
		let existing = try modelContext.fetch(FetchDescriptor<CabinetPosition>())
		guard existing.isEmpty else { return }
		try loadCabinetPositions()
	}
}
