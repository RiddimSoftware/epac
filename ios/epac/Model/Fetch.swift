//
//  Fetch.swift
//  epac
//
//  Created by Sunny on 2024-12-12.
//

import Foundation
import Kanna
import SwiftData
import SWXMLHash

actor Fetch: ModelActor, ObservableObject {
	nonisolated let modelExecutor: any ModelExecutor
	nonisolated let modelContainer: ModelContainer

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
	private let networkService: NetworkService
	private let voteDateFormatter: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
		return f
	}()

	init(modelContainer: ModelContainer, networkService: NetworkService = .shared) {
		let modelContext = ModelContext(modelContainer)
		self.modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
		self.modelContainer = modelContainer
		self.networkService = networkService
	}

	private enum Constants {
		static let secondsPerMinute: TimeInterval = 60
		static let minutesPerHour: TimeInterval = 60
		static let hoursPerDay: TimeInterval = 24
		static let fiscalMonitorRefreshInterval = secondsPerMinute * minutesPerHour * hoursPerDay
		static let csvPreviewLinkLimit = 10
		static let csvLinkNotFoundErrorCode = 2
		static let parseExpendituresHTMLErrorCode = 1
		static let expenditureTableColumnCount = 7
		static let unmatchedRowLogLimit = 5
		static let travelColumnIndex = 4
		static let hospitalityColumnIndex = 5
		static let contractsColumnIndex = 6
		static let emptyMemberID = 0
		static let invalidUTF8ErrorCode = 7
		static let htmlParseErrorCode = 1
		static let urlBuildErrorCode = 6
		static let missingPublicationErrorCode = 4
		static let activePublicationTextErrorCode = 2
		static let projectedPublicationErrorCode = 3
		static let missingXMLExportErrorCode = 5
		static let successfulHTTPStatusCodes = 200..<300
		static let stableVoteParliamentMultiplier = 1_000_000
		static let stableVoteSessionMultiplier = 10_000
		static let sessionComponentCount = 2
		static let voteURLSegmentCount = 3
		static let ontarioDefaultSession = 1
		static let missingSittingDateErrorCode = 8
	}

	private enum VotingEndpoint {
		case openCommons
		case openParliament
	}

	private struct ParsedRecordedVote: Sendable {
		let voteID: Int
		let parliament: Int
		let session: Int
		let number: Int
		let date: Date
		let descriptionEn: String
		let billNumberCode: String
		let yea: Int
		let nay: Int
		let paired: Int
		let resultEn: String

		var model: RecordedVote {
			RecordedVote(
				voteID: voteID,
				parliament: parliament,
				session: session,
				number: number,
				date: date,
				descriptionEn: descriptionEn,
				billNumberCode: billNumberCode,
				yea: yea,
				nay: nay,
				paired: paired,
				resultEn: resultEn
			)
		}
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
		try? loadMinisterialExpenses()
		try? await downloadHansard(Date())
		if let bills = try? await BillsService.fetchBills() {
			await BillFollowStore.shared.updateStoredState(in: bills)
		}
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
		let span = Telemetry.startSpan(name: "hansard.sync", operation: "fetch.hansard")
		do {
			let xml = try await downloadXML(forDate: date)
			try ingestHansard(xml: xml)
			UserDefaults.standard.set(Date(), forKey: "epac.sync.hansard")
			span.finish()
		} catch {
			span.finish()
			throw error
		}
	}

	/// Parses a Hansard XML string and persists it into the model context, deduping
	/// against any existing Hansard with the same date. Extracted from `downloadHansard`
	/// so non-network callers (e.g. evidence-mode fixture seeding) can drive the same
	/// parse-and-persist code path without going through the live ourcommons.ca fetch.
	func ingestHansard(xml: String) throws {
		let incoming = XMLBro(xml: xml).parseXML().hansard()
		let existing = try modelContext.fetch(FetchDescriptor<Hansard>(
			predicate: #Predicate { $0.date == incoming.date }
		))
		if existing.count == 1, existing.first?.domainDTO == incoming {
			return
		}
		for hansard in existing {
			deleteHansardAggregate(hansard)
		}
		modelContext.insert(Hansard(domain: incoming))
		try modelContext.save()
	}

	func ingestSaskatchewanVotes(document: String, sittingDate: Date) throws {
		let parser = SaskatchewanVotesParser()
		let votes = try parser.parse(document: document, sittingDate: sittingDate)
		for vote in votes {
			modelContext.insert(vote)
		}
		try modelContext.save()
	}

	func ingestOntarioVotes(document: String, sittingDate: Date) throws {
		let parser = OntarioVotesParser()
		let votes = try parser.parse(document: document, sittingDate: sittingDate)
		for vote in votes {
			modelContext.insert(vote)
		}
		try modelContext.save()
	}

	func ingestNovaScotiaVotes(document: String, sittingDate: Date) throws {
		let parser = NovaScotiaVotesParser()
		let votes = try parser.parse(document: document, sittingDate: sittingDate)
		for vote in votes {
			modelContext.insert(vote)
		}
		try modelContext.save()
	}

	func member(_ firstName: String, _ lastName: String) async throws -> ParliamentMember {
		Log.debug("Fetch.member(firstName: \(firstName), lastName: \(lastName))")
		let fetched = try modelContext.fetch(FetchDescriptor<ParliamentMember>())
			.filter {
				$0.jurisdiction == .federal && $0.firstName == firstName && $0.lastName == lastName
			}
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
			.filter { $0.jurisdiction == .federal }
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
		return Date().timeIntervalSince(lastSync) > Constants.fiscalMonitorRefreshInterval
	}

	func downloadExpenditures(year: Int, quarter: Int) async throws {
		Log.debug("Fetch.downloadExpenditures(year: \(year), quarter: \(quarter))")
		let path = String(format: expenditurePath, year, quarter)
		let url = hosturl.appending(path: path)
		let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
		let (data, _) = try await networkService.data(for: request)

		let doc = try parseExpendituresHTML(from: data)
		let allLinks = doc.css("a")
		Log.debug("Found \(allLinks.count) links on the page")

		guard let csvURL = findCSVURL(in: doc, relativeTo: hosturl) else {
			for link in allLinks.prefix(Constants.csvPreviewLinkLimit) {
				Log.debug("Link: text='\(link.text ?? "")', href='\(link["href"] ?? "")'")
			}
			throw NSError(domain: "Fetch", code: Constants.csvLinkNotFoundErrorCode, userInfo: [NSLocalizedDescriptionKey: "CSV link not found after checking \(allLinks.count) links"])
		}

		Log.debug("Found CSV URL: \(csvURL.absoluteString)")
		let (csvData, _) = try await networkService.data(from: csvURL)
		Log.debug("Downloaded \(csvData.count) bytes of CSV data")

		let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("expenditures-\(year)-Q\(quarter).csv")
		try csvData.write(to: tempURL)
		let expenditures = await parseSummaryExpenditures(from: tempURL, year: year, quarter: quarter)

		// Parse detailed links from HTML
		let rows = doc.css("table tbody tr")
		Log.debug("Found \(rows.count) rows in HTML table")
		let existingExpenditures = try modelContext.fetch(FetchDescriptor<SummaryExpenditure>(predicate: #Predicate { $0.year == year && $0.quarter == quarter }))

		if !expenditures.isEmpty && !existingExpenditures.isEmpty {
			Log.debug("Summary data already exists for \(year) Q\(quarter), skipping insertion but updating links.")
		}

		associateDetailLinks(from: rows, parsed: expenditures, existing: existingExpenditures)
		insertNewSummaryExpenditures(expenditures, existing: existingExpenditures)
		try modelContext.save()
		UserDefaults.standard.set(Date(), forKey: "epac.sync.expenditures")
		try? FileManager.default.removeItem(at: tempURL)
	}

	private func parseExpendituresHTML(from data: Data) throws -> HTMLDocument {
		guard let htmlstring = String(data: data, encoding: .utf8),
			  let doc = try? HTML(html: htmlstring, url: nil, encoding: .utf8) else {
			throw NSError(domain: "Fetch", code: Constants.parseExpendituresHTMLErrorCode, userInfo: [NSLocalizedDescriptionKey: "Failed to parse HTML"])
		}
		return doc
	}

	private func findCSVURL(in doc: HTMLDocument, relativeTo baseURL: URL) -> URL? {
		return csvURLByExportButton(in: doc, relativeTo: baseURL)
			?? csvURLByHref(in: doc, relativeTo: baseURL)
			?? csvURLByText(in: doc, relativeTo: baseURL)
	}

	private func csvURLByExportButton(in doc: HTMLDocument, relativeTo baseURL: URL) -> URL? {
		return doc.css("a.btn-export-csv").first.flatMap { csvURL(from: $0, relativeTo: baseURL) }
	}

	private func csvURLByHref(in doc: HTMLDocument, relativeTo baseURL: URL) -> URL? {
		return doc.css("a")
			.first(where: { $0["href"]?.lowercased().contains(".csv") == true })
			.flatMap { csvURL(from: $0, relativeTo: baseURL) }
	}

	private func csvURLByText(in doc: HTMLDocument, relativeTo baseURL: URL) -> URL? {
		return doc.css("a")
			.first(where: { $0.text?.contains("CSV") == true })
			.flatMap { csvURL(from: $0, relativeTo: baseURL) }
	}

	private func csvURL(from element: Kanna.XMLElement, relativeTo baseURL: URL) -> URL? {
		guard let href = element["href"] else { return nil }
		return URL(string: href, relativeTo: baseURL)
	}

	private func parseSummaryExpenditures(from tempURL: URL, year: Int, quarter: Int) async -> [SummaryExpenditure] {
		let parser = CSVParser(file: tempURL)
		let stream = SummaryExpenditure.fromCSV(parser, year: year, quarter: quarter)
		var expenditures: [SummaryExpenditure] = []
		for await expenditure in stream {
			expenditures.append(expenditure)
		}
		return expenditures
	}

	private func associateDetailLinks(
		from rows: XPathObject,
		parsed expenditures: [SummaryExpenditure],
		existing existingExpenditures: [SummaryExpenditure]
	) {
		let targetExpenditures = expenditures.isEmpty ? existingExpenditures : expenditures
		for (index, row) in rows.enumerated() {
			associateDetailLinks(from: row, index: index, targetExpenditures: targetExpenditures, hasParsedRows: !expenditures.isEmpty)
		}
	}

	private func associateDetailLinks(
		from row: Kanna.XMLElement,
		index: Int,
		targetExpenditures: [SummaryExpenditure],
		hasParsedRows: Bool
	) {
		let cells = row.css("td")
		guard cells.count >= Constants.expenditureTableColumnCount else { return }
		let nameText = cells[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

		if let match = matchingSummaryExpenditure(for: nameText, in: targetExpenditures) {
			updateDetailLinks(for: match, cells: cells)
		} else if index < Constants.unmatchedRowLogLimit && hasParsedRows {
			Log.debug("Could not match HTML row \(index): '\(nameText)'")
		}
	}

	private func matchingSummaryExpenditure(
		for nameText: String,
		in expenditures: [SummaryExpenditure]
	) -> SummaryExpenditure? {
		return expenditures.first { expenditure in
			let fullName = "\(expenditure.lastName), \(expenditure.firstName)"
			return nameText.caseInsensitiveCompare(fullName) == .orderedSame
				|| nameText.contains(expenditure.lastName) && nameText.contains(expenditure.firstName)
		}
	}

	private func updateDetailLinks(for expenditure: SummaryExpenditure, cells: XPathObject) {
		var foundLink = false
		foundLink = updateDetailLink(at: Constants.travelColumnIndex, in: cells, assign: { expenditure.travelURL = $0 }) || foundLink
		foundLink = updateDetailLink(at: Constants.hospitalityColumnIndex, in: cells, assign: { expenditure.hospitalityURL = $0 }) || foundLink
		foundLink = updateDetailLink(at: Constants.contractsColumnIndex, in: cells, assign: { expenditure.contractsURL = $0 }) || foundLink
		if foundLink {
			Log.debug("Associated links for \(expenditure.lastName) (\(expenditure.firstName))")
		}
	}

	private func updateDetailLink(at index: Int, in cells: XPathObject, assign: (String?) -> Void) -> Bool {
		guard let href = cells[index].css("a").first?["href"] else { return false }
		assign(URL(string: href, relativeTo: hosturl)?.absoluteString)
		return true
	}

	private func insertNewSummaryExpenditures(
		_ expenditures: [SummaryExpenditure],
		existing existingExpenditures: [SummaryExpenditure]
	) {
		guard !expenditures.isEmpty && existingExpenditures.isEmpty else { return }
		for expenditure in expenditures {
			modelContext.insert(expenditure)
		}
		Log.debug("Inserted \(expenditures.count) new expenditures into database")
	}

	func downloadDetailedExpenditures(identifier: PersistentIdentifier) async throws {
		guard let expenditure = modelContext.model(for: identifier) as? SummaryExpenditure else {
			Log.error("Expenditure not found for identifier")
			return
		}

		// If URLs are missing, we might need to re-fetch the summary HTML to get them
		try await refreshDetailLinksIfMissing(for: expenditure)

		// Re-fetch to get updated URLs if they were just downloaded
		guard let updatedExpenditure = modelContext.model(for: identifier) as? SummaryExpenditure else {
			return
		}

		Log.debug("Fetch.downloadDetailedExpenditures for \(updatedExpenditure.lastName). TravelURL: \(updatedExpenditure.travelURL != nil), HospitalityURL: \(updatedExpenditure.hospitalityURL != nil), ContractsURL: \(updatedExpenditure.contractsURL != nil)")
		try await downloadDetailIfPresent(updatedExpenditure.travelURL, type: .travel, member: updatedExpenditure)
		try await downloadDetailIfPresent(updatedExpenditure.hospitalityURL, type: .hospitality, member: updatedExpenditure)
		try await downloadDetailIfPresent(updatedExpenditure.contractsURL, type: .contracts, member: updatedExpenditure)
	}

	private func refreshDetailLinksIfMissing(for expenditure: SummaryExpenditure) async throws {
		guard !hasAnyDetailURL(expenditure) else { return }
		Log.debug("URLs missing for \(expenditure.lastName), attempting to re-fetch summary HTML")
		try await downloadExpenditures(year: expenditure.year, quarter: expenditure.quarter)
	}

	private func hasAnyDetailURL(_ expenditure: SummaryExpenditure) -> Bool {
		return expenditure.travelURL != nil || expenditure.hospitalityURL != nil || expenditure.contractsURL != nil
	}

	private func downloadDetailIfPresent(
		_ urlString: String?,
		type: DetailType,
		member: SummaryExpenditure
	) async throws {
		guard let urlString, let url = URL(string: urlString) else { return }
		try await downloadDetail(url: url, type: type, member: member)
	}

	private enum DetailType {
		case travel, hospitality, contracts
	}

	private func downloadDetail(url: URL, type: DetailType, member: SummaryExpenditure) async throws {
		Log.debug("Downloading detail from \(url.absoluteString)")
		let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
		let (data, _) = try await networkService.data(for: request)

		guard let htmlstring = String(data: data, encoding: .utf8),
			  let doc = try? HTML(html: htmlstring, url: nil, encoding: .utf8) else {
			Log.error("Failed to parse detail HTML from \(url.absoluteString)")
			return
		}

		guard let csvURL = findDetailCSVURL(in: doc, relativeTo: hosturl) else {
			Log.error("CSV link not found in detail page \(url.absoluteString)")
			Log.debug("HTML content of failing page: \n\(htmlstring)")
			return
		}

		Log.debug("Found detailed CSV URL: \(csvURL.absoluteString)")
		let (csvData, _) = try await networkService.data(from: csvURL)
		let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("detail-\(UUID().uuidString).csv")
		try csvData.write(to: tempURL)

		let parser = CSVParser(file: tempURL)
		let count = await insertDetailRows(type: type, parser: parser, member: member)

		Log.debug("Inserted \(count) detailed items for \(type)")
		try modelContext.save()
		try? FileManager.default.removeItem(at: tempURL)
	}

	private func findDetailCSVURL(in doc: HTMLDocument, relativeTo baseURL: URL) -> URL? {
		if let element = detailCSVElementBySelector(in: doc) {
			return csvURL(from: element, relativeTo: baseURL)
		}
		return detailCSVURLByHref(in: doc, relativeTo: baseURL)
	}

	private func detailCSVElementBySelector(in doc: HTMLDocument) -> Kanna.XMLElement? {
		for selector in ["a.btn-export-csv", "a.csv-btn.view-report-link"] {
			if let element = doc.css(selector).first {
				Log.debug("Found CSV link using selector: \(selector)")
				return element
			}
		}
		return nil
	}

	private func detailCSVURLByHref(in doc: HTMLDocument, relativeTo baseURL: URL) -> URL? {
		let url = csvURLByHref(in: doc, relativeTo: baseURL)
		if url != nil {
			Log.debug("Found CSV link by searching for .csv in href")
		}
		return url
	}

	private func insertDetailRows(
		type: DetailType,
		parser: CSVParser,
		member: SummaryExpenditure
	) async -> Int {
		switch type {
		case .travel:
			return await insertTravelClaims(from: parser, member: member)
		case .hospitality:
			return await insertHospitalityExpenditures(from: parser, member: member)
		case .contracts:
			return await insertContractExpenditures(from: parser, member: member)
		}
	}

	private func insertTravelClaims(from parser: CSVParser, member: SummaryExpenditure) async -> Int {
		var count = 0
		let stream = TravelClaim.fromCSV(parser)
		for await claimData in stream {
			let claim = makeTravelClaim(from: claimData, member: member)
			modelContext.insert(claim)
			count += 1
		}
		return count
	}

	private func makeTravelClaim(from claimData: TravelClaimData, member: SummaryExpenditure) -> TravelClaim {
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
			claim.details.append(makeTravelExpenditureDetail(from: detailData, claim: claim))
		}
		return claim
	}

	private func makeTravelExpenditureDetail(
		from detailData: TravelExpenditureDetailData,
		claim: TravelClaim
	) -> TravelExpenditureDetail {
		let detail = TravelExpenditureDetail(
			travellerName: detailData.travellerName,
			travellerType: detailData.travellerType,
			purposeOfTravel: detailData.purposeOfTravel,
			date: detailData.date,
			departure: detailData.departure,
			destination: detailData.destination
		)
		detail.claim = claim
		return detail
	}

	private func insertHospitalityExpenditures(from parser: CSVParser, member: SummaryExpenditure) async -> Int {
		var count = 0
		let stream = HospitalityExpenditure.fromCSV(parser)
		for await itemData in stream {
			let item = makeHospitalityExpenditure(from: itemData, member: member)
			modelContext.insert(item)
			count += 1
		}
		return count
	}

	private func makeHospitalityExpenditure(
		from itemData: HospitalityExpenditureData,
		member: SummaryExpenditure
	) -> HospitalityExpenditure {
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
		return item
	}

	private func insertContractExpenditures(from parser: CSVParser, member: SummaryExpenditure) async -> Int {
		var count = 0
		let stream = ContractExpenditure.fromCSV(parser)
		for await itemData in stream {
			let item = makeContractExpenditure(from: itemData, member: member)
			modelContext.insert(item)
			count += 1
		}
		return count
	}

	private func makeContractExpenditure(
		from itemData: ContractExpenditureData,
		member: SummaryExpenditure
	) -> ContractExpenditure {
		let item = ContractExpenditure(
			supplier: itemData.supplier,
			details: itemData.details,
			date: itemData.date,
			total: itemData.total,
			memberID: Constants.emptyMemberID,
			year: member.year,
			quarter: member.quarter
		)
		item.summary = member
		return item
	}

	func downloadXML(forDate date: Date) async throws -> String {
		Log.debug("Fetch.downloadXML(date: \(date))")
		let url = hosturl.appending(path: dailyPath).appending(path: DateUtils.getCSVStringFromDate(date))
		let publicationDoc = try await downloadHTMLDocument(from: url, cachePolicy: .reloadIgnoringLocalCacheData)
		let publicationURL = try hansardPublicationURL(from: publicationDoc, relativeTo: hosturl)
		let hansardDoc = try await downloadHTMLDocument(from: publicationURL)
		let xmlURL = try xmlExportURL(from: hansardDoc, relativeTo: hosturl)
		let request = URLRequest(url: xmlURL, cachePolicy: .reloadIgnoringLocalCacheData)
		let (data, _) = try await networkService.data(for: request)
		guard let utfstringvalue = String(data: data, encoding: .utf8) else {
			throw NSError(domain: "", code: Constants.invalidUTF8ErrorCode)
		}
		return utfstringvalue
	}

	private func downloadHTMLDocument(
		from url: URL,
		cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
	) async throws -> HTMLDocument {
		let request = URLRequest(url: url, cachePolicy: cachePolicy)
		let (data, _) = try await networkService.data(for: request)
		guard let htmlstring = String(data: data, encoding: .utf8),
			  let doc = try? HTML(html: htmlstring, url: nil, encoding: .utf8) else {
			throw NSError(domain: "", code: Constants.htmlParseErrorCode)
		}
		return doc
	}

	private func hansardPublicationURL(from doc: HTMLDocument, relativeTo baseURL: URL) throws -> URL {
		let href = try hansardPublicationHref(from: doc)
		guard let url = URL(string: href, relativeTo: baseURL) else {
			throw NSError(domain: "", code: Constants.urlBuildErrorCode)
		}
		return url
	}

	private func hansardPublicationHref(from doc: HTMLDocument) throws -> String {
		var href: String?
		for debatelink in doc.css("a.active-publication-link") {
			let text = try activePublicationText(from: debatelink)
			href = try updatedHansardHref(current: href, candidate: debatelink["href"], text: text)
		}
		guard let href else {
			throw NSError(domain: "", code: Constants.missingPublicationErrorCode)
		}
		return href
	}

	private func activePublicationText(from link: Kanna.XMLElement) throws -> String {
		guard let text = link.text?.lowercased() else {
			throw NSError(domain: "", code: Constants.activePublicationTextErrorCode)
		}
		return text
	}

	private func updatedHansardHref(current: String?, candidate: String?, text: String) throws -> String? {
		if text.contains("hansard") {
			return candidate
		}
		if text.contains("projected") {
			throw NSError(domain: "", code: Constants.projectedPublicationErrorCode)
		}
		return current
	}

	private func xmlExportURL(from doc: HTMLDocument, relativeTo baseURL: URL) throws -> URL {
		guard let xmllinkelement = doc.css("a.btn-export-xml").first else {
			throw NSError(domain: "", code: Constants.missingXMLExportErrorCode)
		}
		guard let href = xmllinkelement["href"] else {
			throw NSError(domain: "", code: Constants.missingPublicationErrorCode)
		}
		guard let xmllink = URL(string: href, relativeTo: baseURL) else {
			throw NSError(domain: "", code: Constants.urlBuildErrorCode)
		}
		return xmllink
	}

	func downloadCalendar(year: Int) async throws -> [Date] {
		Log.debug("Fetch.downloadCalendar(year: \(year))")
		Log.debug("Downloading calendar \(year)")
		let path = String(format: calendarPath, year)
		let request = URLRequest(url: hosturl.appending(path: path), cachePolicy: .reloadIgnoringLocalCacheData)
		let (data, _) = try await networkService.data(for: request)
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

	func downloadMembers(jurisdiction: Jurisdiction = .federal) async throws {
		Log.debug("Fetch.downloadMembers(jurisdiction: \(jurisdiction.rawValue))")
		switch jurisdiction {
		case .federal:
			try await downloadFederalMembers()
		case .ontario:
			try await downloadOntarioMembers()
		case .novaScotia:
			try await downloadNovaScotiaMembers()
		case .saskatchewan:
			try await downloadSaskatchewanMembers()
		default:
			throw HansardAdapterError.unsupportedJurisdiction(jurisdiction)
		}
	}

	private func downloadFederalMembers() async throws {
		guard let url = URL(string: membersPath, relativeTo: hosturl) else {
			throw NSError(domain: "", code: Constants.urlBuildErrorCode)
		}
		let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
		let (data, _) = try await networkService.data(for: request)
		Log.debug("got data \(data.count)")
		guard let utfstringvalue = String(data: data, encoding: .utf8) else {
			throw NSError(domain: "", code: Constants.invalidUTF8ErrorCode)
		}
		Log.debug("Got XML string")
		let memberDTOs = XMLBro.parseMembers(utfstringvalue)
		Log.debug("parsed XML \(memberDTOs.count) members")
		try insertMembers(memberDTOs)
		UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "epac.sync.members")
	}

	private func downloadSaskatchewanMembers() async throws {
		let memberDTOs = try await SaskatchewanMemberDirectoryAdapter().fetchMembers()
		try insertMembers(memberDTOs)
		UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "epac.sync.members")
	}

	private func downloadOntarioMembers() async throws {
		let memberDTOs = try await OntarioMemberDirectoryAdapter().fetchMembers()
		try insertMembers(memberDTOs)
		UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "epac.sync.members")
	}

	private func downloadNovaScotiaMembers() async throws {
		let memberDTOs = try await NovaScotiaMemberDirectoryAdapter().fetchMembers()
		try insertMembers(memberDTOs)
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
		let (data, _) = try await networkService.data(for: request)
		guard let responseBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			failedDownloads.insert(identifier)
			throw NSError(domain: "", code: Constants.invalidUTF8ErrorCode)
		}
		let pastMembers = responseBody["pastMembers"] as? [[String: Any]] ?? []
		let currentMembers = responseBody["currentMembers"] as? [[String: Any]] ?? []
		let allMembers = currentMembers + pastMembers

		if let member = allMembers.first {
			let name = "\(firstName) \(lastName)"
			let personID = member["personId"] as? Int ?? 0
			let existing = try? modelContext.fetch(FetchDescriptor<ParliamentMember>())
				.first {
					$0.jurisdiction == .federal && $0.name == name
				}
			if existing == nil {
				let dto = makeFederalMemberDTO(
					from: member,
					firstName: firstName,
					lastName: lastName,
					personID: personID
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
			throw NSError(domain: "", code: Constants.urlBuildErrorCode)
		}
		let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
		let (data, _) = try await networkService.data(for: request)
		guard let utfstringvalue = String(data: data, encoding: .utf8) else {
			throw NSError(domain: "", code: Constants.invalidUTF8ErrorCode)
		}
		let constituencyDTOs = XMLBro.parseConstituencies(utfstringvalue)
		constituencyDTOs.map(Constituency.init(domain:)).forEach { modelContext.insert($0) }
		try modelContext.save()
	}

	private func insertMembers(_ memberDTOs: [ParliamentMemberDTO]) throws {
		let existingMembers = try modelContext.fetch(FetchDescriptor<ParliamentMember>())
		Log.debug("Found \(existingMembers.count) existing members")
		var existingDirectoryKeys = Set(existingMembers.map(\.directoryKey))

		Log.debug("Inserting members")
		try modelContext.transaction {
			for dto in memberDTOs where !existingDirectoryKeys.contains(dto.id) {
				modelContext.insert(ParliamentMember(domain: dto))
				existingDirectoryKeys.insert(dto.id)
			}
		}
	}

	private func makeFederalMemberDTO(
		from member: [String: Any],
		firstName: String,
		lastName: String,
		personID: Int
	) -> ParliamentMemberDTO {
		let name = "\(firstName) \(lastName)"
		// ourcommons.ca members search response shape is part of the API contract; a missing
		// field here means the API broke and we want to fail loudly. Replace with guard-let
		// when the upstream API stabilises around a typed schema.
		// swiftlint:disable force_cast
		let photoURL = URL(string: member["officialPhotoUrl"] as! String, relativeTo: hosturl)!
		let riding = member["constituencyNameEn"] as! String
		let provinceName = (member["provinceNameEn"] as? String) ?? ""
		let caucus = (member["caucusAbbreviationEn"] as! String)
			.trimmingCharacters(in: .alphanumerics.inverted)
		// swiftlint:enable force_cast

		return ParliamentMemberDTO(
			name: name,
			memberID: personID,
			lastName: lastName,
			firstName: firstName,
			photoURL: photoURL,
			riding: riding,
			province: Province(rawValue: provinceName) ?? .Ontario,
			party: Party.partyWithAbbreviation(caucus),
			websiteURL: nil,
			imageData: nil,
			fromDateTime: nil,
			toDateTime: nil,
			email: nil,
			hillPhone: nil,
			constituencyPhone: nil,
			constituencyAddress: nil,
			contactFetched: false,
			jurisdiction: .federal
		)
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
		let (data, response) = try await networkService.data(from: url)
		guard let http = response as? HTTPURLResponse, Constants.successfulHTTPStatusCodes.contains(http.statusCode),
			  let xmlString = String(data: data, encoding: .utf8) else { return }
		let contact = XMLBro.parseMemberContact(xmlString)
		member.email = contact.email
		member.hillPhone = contact.hillPhone
		member.constituencyPhone = contact.constituencyPhone
		member.constituencyAddress = contact.constituencyAddress
		member.contactFetched = true
		try? modelContext.save()
	}

	func downloadVotingRecords(
		jurisdiction: Jurisdiction = .federal,
		parliament: Int = 44,
		session: Int = Constants.ontarioDefaultSession,
		sittingDate: Date? = nil
	) async throws {
		guard try shouldDownloadVotingRecords(jurisdiction: jurisdiction) else { return }
		if jurisdiction == .ontario {
			guard let sittingDate else {
				throw NSError(domain: "OntarioVotes", code: Constants.missingSittingDateErrorCode)
			}
			try await downloadOntarioVotingRecords(parliament: parliament, session: session, sittingDate: sittingDate)
			return
		}
		guard jurisdiction == .federal else {
			throw HansardAdapterError.unsupportedJurisdiction(jurisdiction)
		}
		try await downloadFederalVotingRecords(parliament: parliament)
	}

	private func shouldDownloadVotingRecords(jurisdiction: Jurisdiction) throws -> Bool {
		guard try recordedVoteCount(jurisdiction: jurisdiction) > 0 else { return true }
		if jurisdiction == .federal {
			writeLatestVoteSummaryForWidgets()
		}
		return false
	}

	private func downloadFederalVotingRecords(parliament: Int) async throws {
		let span = Telemetry.startSpan(name: "votes.sync", operation: "fetch.votes")
		do {
			do {
				try await fetchVotingRecords(parliament: parliament, from: .openCommons)
			} catch {
				if shouldFallbackVotes(error: error),
				   try recordedVoteCount(jurisdiction: .federal) == 0 {
					Log.debug("downloadVotingRecords: falling back to openparliament API due legacy host error: \(error.localizedDescription)")
					try await fetchVotingRecords(parliament: parliament, from: .openParliament)
				} else {
					throw error
				}
			}
			writeLatestVoteSummaryForWidgets()
			span.finish()
		} catch {
			span.finish()
			throw error
		}
	}

	private func recordedVoteCount(jurisdiction: Jurisdiction) throws -> Int {
		let jurisdictionValue = jurisdiction.rawValue
		return try modelContext.fetchCount(FetchDescriptor<RecordedVote>(
			predicate: #Predicate { $0.jurisdiction == jurisdictionValue }
		))
	}

	private func downloadOntarioVotingRecords(parliament: Int, session: Int, sittingDate: Date) async throws {
		let datePath = DateUtils.getCSVStringFromDate(sittingDate)
		let path = "en/legislative-business/house-documents/parliament-\(parliament)/session-\(session)/\(datePath)/votes-proceedings"
		guard let url = URL(string: path, relativeTo: URL(string: "https://www.ola.org")) else {
			throw NSError(domain: "OntarioVotes", code: Constants.urlBuildErrorCode)
		}
		let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
		let (data, _) = try await networkService.data(for: request)
		guard let document = String(data: data, encoding: .utf8) else {
			throw NSError(domain: "OntarioVotes", code: Constants.invalidUTF8ErrorCode)
		}
		try ingestOntarioVotes(document: document, sittingDate: sittingDate)
	}

	private func writeLatestVoteSummaryForWidgets(jurisdiction: Jurisdiction = .federal) {
		let jurisdictionValue = jurisdiction.rawValue
		let descriptor = FetchDescriptor<RecordedVote>(
			predicate: #Predicate { $0.jurisdiction == jurisdictionValue },
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
		while hasMore {
			let (voteItems, continuePagination) = try await loadVotingPage(
				parliament: parliament,
				page: page,
				from: source
			)
			for vote in voteItems {
				modelContext.insert(vote.model)
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
		from source: VotingEndpoint
	) async throws -> (votes: [ParsedRecordedVote], hasMore: Bool) {
		guard let url = votingPageURL(parliament: parliament, page: page, from: source),
			  let json = try await fetchJSONDictionary(from: url) else {
			return ([], false)
		}

		return parseVotingPage(json, parliament: parliament, from: source)
	}

	private func votingPageURL(parliament: Int, page: Int, from source: VotingEndpoint) -> URL? {
		switch source {
		case .openCommons:
			return openCommonsVotingPageURL(parliament: parliament, page: page)
		case .openParliament:
			return openParliamentVotingPageURL(parliament: parliament, page: page)
		}
	}

	private func openCommonsVotingPageURL(parliament: Int, page: Int) -> URL? {
		var components = URLComponents(url: openAPIURL, resolvingAgainstBaseURL: false)!
		components.path = "/ocd/votes/"
		components.queryItems = [
			URLQueryItem(name: "parliament", value: String(parliament)),
			URLQueryItem(name: "pageSize", value: String(votePageSize)),
			URLQueryItem(name: "page", value: String(page)),
			URLQueryItem(name: "format", value: "json")
		]
		return components.url
	}

	private func openParliamentVotingPageURL(parliament: Int, page: Int) -> URL? {
		var components = URLComponents(url: openParliamentAPIURL, resolvingAgainstBaseURL: false)!
		components.path = "/votes/"
		components.queryItems = [
			URLQueryItem(name: "parliament", value: String(parliament)),
			URLQueryItem(name: "limit", value: String(votePageSize)),
			URLQueryItem(name: "offset", value: String(max(0, (page - 1) * votePageSize))),
			URLQueryItem(name: "format", value: "json")
		]
		return components.url
	}

	private func fetchJSONDictionary(from url: URL) async throws -> [String: Any]? {
		let (data, response) = try await networkService.data(from: url)
		guard let http = response as? HTTPURLResponse, Constants.successfulHTTPStatusCodes.contains(http.statusCode),
			  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			return nil
		}
		return json
	}

	private func parseVotingPage(
		_ json: [String: Any],
		parliament: Int,
		from source: VotingEndpoint
	) -> (votes: [ParsedRecordedVote], hasMore: Bool) {
		switch source {
		case .openCommons:
			return parseOpenCommonsVotingPage(json, parliament: parliament)
		case .openParliament:
			return parseOpenParliamentVotingPage(json)
		}
	}

	private func parseOpenCommonsVotingPage(
		_ json: [String: Any],
		parliament: Int
	) -> (votes: [ParsedRecordedVote], hasMore: Bool) {
		guard let items = json["items"] as? [[String: Any]] else { return ([], false) }
		let votes = items.compactMap { parseOpenCommonsVote($0, parliament: parliament) }
		return (votes, !votes.isEmpty && votes.count == votePageSize)
	}

	private func parseOpenParliamentVotingPage(
		_ json: [String: Any]
	) -> (votes: [ParsedRecordedVote], hasMore: Bool) {
		guard let objects = json["objects"] as? [[String: Any]] else { return ([], false) }
		let votes = objects.compactMap { parseOpenParliamentVote($0) }
		let nextURL = (json["pagination"] as? [String: Any])?["next_url"] as? String
		return (votes, nextURL?.isEmpty == false)
	}

	private func parseOpenCommonsVote(_ item: [String: Any], parliament: Int) -> ParsedRecordedVote? {
		guard let id = item["id"] as? Int else { return nil }
		let dateStr = item["date"] as? String ?? ""
		let date = voteDateFormatter.date(from: dateStr) ?? Date()
		let descObj = item["description"] as? [String: String]
		let desc = descObj?["en"] ?? item["description"] as? String ?? ""
		let resultObj = item["result"] as? [String: String]
		let result = resultObj?["en"] ?? item["result"] as? String ?? ""
		return ParsedRecordedVote(
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

	private func parseOpenParliamentVote(_ item: [String: Any]) -> ParsedRecordedVote? {
		guard let number = item["number"] as? Int,
			  let sessionText = item["session"] as? String else { return nil }
		let (voteParliament, session) = parseSessionComponents(from: sessionText)
		let voteID = makeStableVoteID(parliament: voteParliament, session: session, number: number)
		let dateStr = item["date"] as? String ?? ""
		let date = voteDateFormatter.date(from: dateStr) ?? Date()
		let descObj = item["description"] as? [String: Any]
		let desc = descObj?["en"] as? String ?? ""
		let result = item["result"] as? String ?? ""
		let bill = item["bill_url"] as? String
		return ParsedRecordedVote(
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
		guard let url = await memberVotesURL(memberID: memberID, page: page, from: source),
			  let json = try await fetchJSONDictionary(from: url) else {
			return ([], false)
		}

		return parseMemberVotesPage(json, from: source)
	}

	private func memberVotesURL(memberID: Int, page: Int, from source: VotingEndpoint) async -> URL? {
		switch source {
		case .openCommons:
			return openCommonsMemberVotesURL(memberID: memberID, page: page)
		case .openParliament:
			let slug = await openParliamentSlug(for: memberID)
			return openParliamentMemberVotesURL(slug: slug, page: page)
		}
	}

	private func openCommonsMemberVotesURL(memberID: Int, page: Int) -> URL? {
		var components = URLComponents(url: openAPIURL, resolvingAgainstBaseURL: false)!
		components.path = "/ocd/members/\(memberID)/votes/"
		components.queryItems = [
			URLQueryItem(name: "pageSize", value: String(votePageSize)),
			URLQueryItem(name: "page", value: String(page)),
			URLQueryItem(name: "format", value: "json")
		]
		return components.url
	}

	private func openParliamentMemberVotesURL(slug: String, page: Int) -> URL? {
		var components = URLComponents(url: openParliamentAPIURL, resolvingAgainstBaseURL: false)!
		components.path = "/votes/ballots/"
		components.queryItems = [
			URLQueryItem(name: "politician", value: slug),
			URLQueryItem(name: "limit", value: String(votePageSize)),
			URLQueryItem(name: "offset", value: String(max(0, (page - 1) * votePageSize))),
			URLQueryItem(name: "format", value: "json")
		]
		return components.url
	}

	private func parseMemberVotesPage(
		_ json: [String: Any],
		from source: VotingEndpoint
	) -> (votes: [(voteID: Int, ballot: String)], hasMore: Bool) {
		switch source {
		case .openCommons:
			return parseOpenCommonsMemberVotesPage(json)
		case .openParliament:
			return parseOpenParliamentMemberVotesPage(json)
		}
	}

	private func parseOpenCommonsMemberVotesPage(
		_ json: [String: Any]
	) -> (votes: [(voteID: Int, ballot: String)], hasMore: Bool) {
		guard let items = json["items"] as? [[String: Any]] else { return ([], false) }
		let votes = items.compactMap(openCommonsMemberVote(from:))
		return (votes, !votes.isEmpty && votes.count == votePageSize)
	}

	private func openCommonsMemberVote(from item: [String: Any]) -> (voteID: Int, ballot: String)? {
		guard let voteID = item["voteId"] as? Int,
			  let ballot = item["recordedVote"] as? String else { return nil }
		return (voteID, ballot)
	}

	private func parseOpenParliamentMemberVotesPage(
		_ json: [String: Any]
	) -> (votes: [(voteID: Int, ballot: String)], hasMore: Bool) {
		guard let items = json["objects"] as? [[String: Any]] else { return ([], false) }
		let votes = items.compactMap(openParliamentMemberVote(from:))
		let nextURL = (json["pagination"] as? [String: Any])?["next_url"] as? String
		return (votes, nextURL?.isEmpty == false)
	}

	private func openParliamentMemberVote(from item: [String: Any]) -> (voteID: Int, ballot: String)? {
		guard let ballotRaw = item["ballot"] as? String,
			  let vote = openParliamentBallotID(from: item["vote_url"] as? String ?? "") else {
			return nil
		}
		return (vote, normalizedBallot(ballotRaw))
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
		guard let (data, response) = try? await networkService.data(from: url),
			  let http = response as? HTTPURLResponse, Constants.successfulHTTPStatusCodes.contains(http.statusCode),
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

		guard let (data, response) = try? await networkService.data(from: url),
			  let http = response as? HTTPURLResponse, Constants.successfulHTTPStatusCodes.contains(http.statusCode),
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
		return (safeParliament * Constants.stableVoteParliamentMultiplier) + (safeSession * Constants.stableVoteSessionMultiplier) + safeNumber
	}

	private func parseSessionComponents(from session: String) -> (Int, Int) {
		let parts = session.split(separator: "-")
		guard parts.count >= Constants.sessionComponentCount,
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
		guard segments.count >= Constants.voteURLSegmentCount,
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

		var page = 1
		var hasMore = true
		while hasMore {
			guard let items = try await loadWrittenQuestionsPage(memberID: memberID, parliament: parliament, page: page) else { break }
			hasMore = !items.isEmpty && items.count == 100
			page += 1
			insertWrittenQuestions(items, memberID: memberID, parliament: parliament)
			try modelContext.save()
		}
	}

	private func loadWrittenQuestionsPage(memberID: Int, parliament: Int, page: Int) async throws -> [[String: Any]]? {
		guard let url = writtenQuestionsURL(memberID: memberID, parliament: parliament, page: page),
			  let json = try await fetchJSONDictionary(from: url) else {
			return nil
		}
		return json["items"] as? [[String: Any]]
	}

	private func writtenQuestionsURL(memberID: Int, parliament: Int, page: Int) -> URL? {
		var components = URLComponents(url: openAPIURL, resolvingAgainstBaseURL: false)!
		components.path = "/ocd/questions/"
		components.queryItems = [
			URLQueryItem(name: "parliament", value: String(parliament)),
			URLQueryItem(name: "memberId", value: String(memberID)),
			URLQueryItem(name: "pageSize", value: "100"),
			URLQueryItem(name: "page", value: String(page)),
			URLQueryItem(name: "format", value: "json")
		]
		return components.url
	}

	private func insertWrittenQuestions(
		_ items: [[String: Any]],
		memberID: Int,
		parliament: Int
	) {
		for item in items {
			guard let question = writtenQuestion(from: item, memberID: memberID, parliament: parliament) else {
				continue
			}
			modelContext.insert(question)
		}
	}

	private func writtenQuestion(
		from item: [String: Any],
		memberID: Int,
		parliament: Int
	) -> WrittenQuestion? {
		guard let id = item["id"] as? Int else { return nil }
		let dateStr = item["dateSubmitted"] as? String ?? ""
		let date = voteDateFormatter.date(from: dateStr) ?? Date()
		let responseDateStr = item["responseDate"] as? String
		let responseDate = responseDateStr.flatMap { voteDateFormatter.date(from: $0) }
		return WrittenQuestion(
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
	}

	private func deleteHansardAggregate(_ hansard: Hansard) {
		for order in hansard.orders {
			for subject in order.subjects {
				for speech in subject.speeches {
					for message in speech.messages {
						modelContext.delete(message)
					}
					modelContext.delete(speech)
				}
				modelContext.delete(subject)
			}
			modelContext.delete(order)
		}
		modelContext.delete(hansard)
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

	// MARK: - Ministerial expenses

	// Loads the bundled ministerial-expenses.json snapshot into SwiftData.
	// Re-seeds on every call: the bundled file is regenerated quarterly by
	// backend/expenses/ministerial_ingest.py, and full replacement is cheaper
	// than diffing records across department format changes.
	func loadMinisterialExpenses() throws {
		Log.debug("Fetch.loadMinisterialExpenses()")
		let snapshot = try MinisterialExpensesService().loadSnapshot()

		let existing = try modelContext.fetch(FetchDescriptor<MinisterialExpenseRecord>())
		for record in existing {
			modelContext.delete(record)
		}

		for record in snapshot.records {
			let startDate = MinisterialExpensesService.parseDate(record.startDate) ?? Date.distantPast
			let endDate = record.endDate.flatMap { MinisterialExpensesService.parseDate($0) }
			modelContext.insert(MinisterialExpenseRecord(
				recordID: record.recordID,
				ministerName: record.ministerName,
				department: record.department,
				eventPurpose: record.eventPurpose,
				destination: record.destination,
				startDate: startDate,
				endDate: endDate,
				travelCost: record.travelCost,
				hospitalityCost: record.hospitalityCost,
				totalCost: record.totalCost,
				fiscalYear: record.fiscalYear,
				quarter: record.quarter,
				sourceURL: record.sourceURL
			))
		}
		try modelContext.save()
	}

	// Best-effort seeding on first launch; backgroundRefresh re-seeds on
	// subsequent launches to absorb updated quarterly disclosures shipped with
	// new app versions.
	func ensureMinisterialExpensesSeeded() throws {
		let existing = try modelContext.fetch(FetchDescriptor<MinisterialExpenseRecord>())
		guard existing.isEmpty else { return }
		try loadMinisterialExpenses()
	}
}
