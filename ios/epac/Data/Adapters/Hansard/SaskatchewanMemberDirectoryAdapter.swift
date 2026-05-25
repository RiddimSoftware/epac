//
//  SaskatchewanMemberDirectoryAdapter.swift
//  epac
//

import Foundation
import Kanna

struct SaskatchewanMemberDirectoryAdapter {
	typealias FetchData = @Sendable (URL) async throws -> Data

	private let fetchData: FetchData

	init(fetchData: @escaping FetchData = SaskatchewanMemberDirectoryHTTPClient.fetchData) {
		self.fetchData = fetchData
	}

	func fetchMembers() async throws -> [ParliamentMemberDTO] {
		let data = try await fetchData(Constants.rosterURL)
		guard let html = String(data: data, encoding: .utf8) else {
			throw SaskatchewanMemberDirectoryAdapterError.invalidRosterHTML
		}
		return try parse(html: html)
	}

	func parse(html: String) throws -> [ParliamentMemberDTO] {
		guard let document = try? HTML(html: html, url: Constants.rosterURL.absoluteString, encoding: .utf8) else {
			throw SaskatchewanMemberDirectoryAdapterError.invalidRosterHTML
		}

		return document.css("#mla-data-shown tr").compactMap { row in
			parseMember(row: row)
		}
	}

	private func parseMember(row: Kanna.XMLElement) -> ParliamentMemberDTO? {
		let cells = row.css("td")
		guard cells.count >= Constants.memberRowColumnCount else { return nil }
		guard let detailURL = detailURL(from: cells[Constants.nameColumnIndex]),
		      let name = memberName(from: detailURL) else { return nil }

		let nameLines = textLines(in: cells[Constants.nameColumnIndex])
		guard nameLines.count >= Constants.minimumNameLineCount else { return nil }

		let standing = nameLines[Constants.standingLineIndex]
		let riding = nameLines[Constants.ridingLineIndex]
		let hillPhone = phone(in: cells[Constants.legislativeContactColumnIndex])
		let constituencyAddress = joinedAddress(in: cells[Constants.constituencyAddressColumnIndex])
		let constituencyPhone = phone(in: cells[Constants.constituencyContactColumnIndex])
		let email = email(in: cells[Constants.constituencyContactColumnIndex])

		return ParliamentMemberDTO(
			name: "\(name.firstName) \(name.lastName)",
			memberID: 0,
			lastName: name.lastName,
			firstName: name.firstName,
			// The roster page does not publish headshot URLs; seed an official
			// Assembly image until a detail-page photo enrichment path is added.
			photoURL: Constants.placeholderPhotoURL,
			riding: riding,
			province: .Saskatchewan,
			party: party(from: standing),
			websiteURL: detailURL,
			imageData: nil,
			fromDateTime: nil,
			toDateTime: nil,
			email: email,
			hillPhone: hillPhone,
			constituencyPhone: constituencyPhone,
			constituencyAddress: constituencyAddress,
			contactFetched: true,
			jurisdiction: .saskatchewan
		)
	}

	private func detailURL(from element: Kanna.XMLElement) -> URL? {
		guard let href = element.at_css("a")?["href"] else { return nil }
		return URL(string: href, relativeTo: Constants.rosterURL)?.absoluteURL
	}

	private func memberName(from detailURL: URL) -> (firstName: String, lastName: String)? {
		guard let components = URLComponents(url: detailURL, resolvingAgainstBaseURL: true) else { return nil }
		let firstName = components.queryItems?.first(where: { $0.name == "first" })?.value?.trimmed.nonEmpty
		let lastName = components.queryItems?.first(where: { $0.name == "last" })?.value?.trimmed.nonEmpty
		guard let firstName, let lastName else { return nil }
		return (firstName, lastName)
	}

	private func party(from standing: String) -> Party {
		let normalized = standing.lowercased()
		if normalized.contains("independent") {
			return .independent
		}
		if normalized.contains("government") || normalized.contains("saskatchewan party") || normalized.contains("sk party") {
			return .saskatchewanParty
		}
		if normalized.contains("opposition") || normalized.contains("ndp") {
			return .newdemocratic
		}
		return Party.partyWithAbbreviation(standing)
	}

	private func phone(in element: Kanna.XMLElement) -> String? {
		textLines(in: element)
			.first(where: { $0.hasPrefix("Ph:") })?
			.replacingOccurrences(of: "Ph:", with: "")
			.trimmed
			.nonEmpty
	}

	private func email(in element: Kanna.XMLElement) -> String? {
		if let mailto = element.at_css("a[href^='mailto:']")?["href"] {
			return mailto
				.replacingOccurrences(of: "mailto:", with: "")
				.trimmed
				.nonEmpty
		}
		return textLines(in: element)
			.first(where: { $0.contains("@") })?
			.trimmed
			.nonEmpty
	}

	private func joinedAddress(in element: Kanna.XMLElement) -> String? {
		let parts = textLines(in: element)
		return parts.isEmpty ? nil : parts.joined(separator: ", ")
	}

	private func textLines(in element: Kanna.XMLElement) -> [String] {
		(element.text ?? "")
			.components(separatedBy: .newlines)
			.map(\.trimmed)
			.filter(\.isMeaningful)
	}
}

enum SaskatchewanMemberDirectoryAdapterError: Error, Equatable {
	case invalidRosterHTML
}

private enum Constants {
	static let rosterURL = URL(string: "https://www.legassembly.sk.ca/mlas/mla-contact-information/")!
	static let placeholderPhotoURL = URL(string: "https://www.legassembly.sk.ca/img/logo.png")!
	static let memberRowColumnCount = 5
	static let minimumNameLineCount = 3
	static let nameColumnIndex = 0
	static let legislativeContactColumnIndex = 2
	static let constituencyAddressColumnIndex = 3
	static let constituencyContactColumnIndex = 4
	static let standingLineIndex = 1
	static let ridingLineIndex = 2
	static let requestTimeout: TimeInterval = 20
	static let successStatusLowerBound = 200
	static let successStatusUpperBound = 300

	static var successStatusCodes: Range<Int> {
		successStatusLowerBound..<successStatusUpperBound
	}
}

private enum SaskatchewanMemberDirectoryHTTPClient {
	static func fetchData(from url: URL) async throws -> Data {
		var request = URLRequest(url: url, timeoutInterval: Constants.requestTimeout)
		request.setValue("text/html, application/xhtml+xml", forHTTPHeaderField: "Accept")
		let (data, response) = try await NetworkService.shared.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse,
		      Constants.successStatusCodes.contains(httpResponse.statusCode) else {
			throw URLError(.badServerResponse)
		}
		return data
	}
}

private extension String {
	var trimmed: String {
		trimmingCharacters(in: .whitespacesAndNewlines)
	}

	var nonEmpty: String? {
		let value = trimmed
		return value.isEmpty ? nil : value
	}

	var isMeaningful: Bool {
		let value = trimmed
		return !value.isEmpty && value != "-"
	}
}
