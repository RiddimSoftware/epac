//
//  OntarioMemberDirectoryAdapter.swift
//  epac
//

import Foundation
import Kanna

struct OntarioMemberDirectoryAdapter {
	typealias FetchData = @Sendable (URL) async throws -> Data
	typealias Delay = @Sendable () async throws -> Void

	private let fetchData: FetchData
	private let delayBetweenRequests: Delay

	init(
		fetchData: @escaping FetchData = OntarioMemberDirectoryHTTPClient.fetchData,
		delayBetweenRequests: @escaping Delay = OntarioMemberDirectoryHTTPClient.delayBetweenRequests
	) {
		self.fetchData = fetchData
		self.delayBetweenRequests = delayBetweenRequests
	}

	func fetchMembers() async throws -> [ParliamentMemberDTO] {
		let rosterData = try await fetchData(Constants.rosterURL)
		try await delayBetweenRequests()
		let contactData = try await fetchData(Constants.constituencyContactURL)
		guard let rosterHTML = String(data: rosterData, encoding: .utf8),
		      let contactHTML = String(data: contactData, encoding: .utf8) else {
			throw OntarioMemberDirectoryAdapterError.invalidRosterHTML
		}
		return try parse(rosterHTML: rosterHTML, contactHTML: contactHTML)
	}

	func parse(rosterHTML: String, contactHTML: String) throws -> [ParliamentMemberDTO] {
		guard let document = htmlDocument(rosterHTML, url: Constants.rosterURL) else {
			throw OntarioMemberDirectoryAdapterError.invalidRosterHTML
		}
		let contacts = try parseContacts(html: contactHTML)
		return document.css(".member-list-row").compactMap { row in
			parseMember(row: row, contacts: contacts)
		}
	}

	private func parseContacts(html: String) throws -> [String: OntarioMemberContact] {
		guard let document = htmlDocument(html, url: Constants.constituencyContactURL) else {
			throw OntarioMemberDirectoryAdapterError.invalidRosterHTML
		}

		var contacts: [String: OntarioMemberContact] = [:]
		for row in document.css(".member-contact-bucket .views-row") {
			guard let contact = parseContact(row: row), contacts[contact.detailKey] == nil else {
				continue
			}
			contacts[contact.detailKey] = contact
		}
		return contacts
	}

	private func parseMember(
		row: Kanna.XMLElement,
		contacts: [String: OntarioMemberContact]
	) -> ParliamentMemberDTO? {
		guard let detailURL = detailURL(from: row),
		      let name = text(in: row, selector: ".memberGridView h3"),
		      let riding = text(in: row, selector: ".memberGridView .current-members-riding"),
		      let partyText = text(in: row, selector: ".memberGridView .current-members-party") else {
			return nil
		}

		let contact = contacts[detailKey(for: detailURL)]
		let nameParts = splitName(name)
		return ParliamentMemberDTO(
			name: name,
			memberID: Constants.emptyMemberID,
			lastName: nameParts.lastName,
			firstName: nameParts.firstName,
			photoURL: photoURL(from: row) ?? Constants.placeholderPhotoURL,
			riding: riding,
			province: .Ontario,
			party: party(from: partyText),
			websiteURL: detailURL,
			imageData: nil,
			fromDateTime: nil,
			toDateTime: nil,
			email: contact?.email,
			hillPhone: nil,
			constituencyPhone: contact?.phone,
			constituencyAddress: contact?.address,
			contactFetched: true,
			jurisdiction: .ontario
		)
	}

	private func parseContact(row: Kanna.XMLElement) -> OntarioMemberContact? {
		guard let detailURL = detailURL(from: row) else { return nil }
		let addressParts = textLines(in: row, selector: ".views-field-field-address .field-content")
		let postalCode = text(in: row, selector: ".views-field-field-postal-code .field-content")
		let fullAddress = joinedAddress(addressParts: addressParts, postalCode: postalCode)
		return OntarioMemberContact(
			detailKey: detailKey(for: detailURL),
			email: email(in: row),
			phone: phone(in: row),
			address: fullAddress
		)
	}

	private func htmlDocument(_ html: String, url: URL) -> HTMLDocument? {
		try? HTML(html: html, url: url.absoluteString, encoding: .utf8)
	}

	private func detailURL(from element: Kanna.XMLElement) -> URL? {
		guard let href = element.at_css("a[href*='/members/all/']")?["href"] else { return nil }
		return URL(string: href, relativeTo: Constants.rosterURL)?.absoluteURL
	}

	private func detailKey(for url: URL) -> String {
		URLComponents(url: url, resolvingAgainstBaseURL: true)?.path ?? url.absoluteString
	}

	private func photoURL(from row: Kanna.XMLElement) -> URL? {
		guard let src = row.at_css("img.headshot")?["src"] else { return nil }
		return URL(string: src, relativeTo: Constants.rosterURL)?.absoluteURL
	}

	private func splitName(_ name: String) -> (firstName: String, lastName: String) {
		let cleaned = name
			.replacingOccurrences(of: "Hon. ", with: "")
			.replacingOccurrences(of: "Hon ", with: "")
			.trimmed
		let parts = cleaned.components(separatedBy: .whitespaces).filter(\.isMeaningful)
		guard let lastName = parts.last else { return (cleaned, cleaned) }
		let firstName = parts.dropLast().joined(separator: " ").nonEmpty ?? lastName
		return (firstName, lastName)
	}

	private func party(from text: String) -> Party {
		let normalized = text.lowercased()
		let mapping: [(needle: String, party: Party)] = [
			("progressive conservative", .conservative),
			("new democratic", .newdemocratic),
			("liberal", .liberal),
			("green", .green),
			("independent", .independent)
		]
		return mapping.first { normalized.contains($0.needle) }?.party ?? Party.partyWithAbbreviation(text)
	}

	private func email(in row: Kanna.XMLElement) -> String? {
		row.at_css(".views-field-field-email-address a[href^='mailto:']")?["href"]?
			.replacingOccurrences(of: "mailto:", with: "")
			.trimmed
			.nonEmpty
	}

	private func phone(in row: Kanna.XMLElement) -> String? {
		text(in: row, selector: ".views-field-field-number .field-content")?
			.replacingOccurrences(of: "Tel.:", with: "")
			.trimmed
			.nonEmpty
	}

	private func joinedAddress(addressParts: [String], postalCode: String?) -> String? {
		let parts = addressParts + [postalCode].compactMap { $0 }
		return parts.isEmpty ? nil : parts.joined(separator: ", ")
	}

	private func text(in element: Kanna.XMLElement, selector: String) -> String? {
		element.at_css(selector)?.text?.normalizedWhitespace.nonEmpty
	}

	private func textLines(in element: Kanna.XMLElement, selector: String) -> [String] {
		(element.at_css(selector)?.text ?? "")
			.replacingOccurrences(of: "\u{00a0}", with: " ")
			.components(separatedBy: .newlines)
			.map(\.trimmed)
			.filter(\.isMeaningful)
	}
}

enum OntarioMemberDirectoryAdapterError: Error, Equatable {
	case invalidRosterHTML
}

private struct OntarioMemberContact {
	let detailKey: String
	let email: String?
	let phone: String?
	let address: String?
}

private enum Constants {
	static let rosterURL = URL(string: "https://www.ola.org/en/members/current")!
	static let constituencyContactURL = URL(
		string: "https://www.ola.org/en/members/current/contact-information/constituency"
	)!
	static let placeholderPhotoURL = URL(string: "https://www.ola.org/themes/custom/de_theme/favicon.ico")!
	static let emptyMemberID = 0
	static let requestTimeout: TimeInterval = 20
	static let requestDelayNanoseconds: UInt64 = 1_000_000_000
	static let successStatusLowerBound = 200
	static let successStatusUpperBound = 300

	static var successStatusCodes: Range<Int> {
		successStatusLowerBound..<successStatusUpperBound
	}
}

private enum OntarioMemberDirectoryHTTPClient {
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

	static func delayBetweenRequests() async throws {
		try await Task.sleep(nanoseconds: Constants.requestDelayNanoseconds)
	}
}

private extension String {
	var trimmed: String {
		trimmingCharacters(in: .whitespacesAndNewlines)
	}

	var normalizedWhitespace: String {
		replacingOccurrences(of: "\u{00a0}", with: " ")
			.components(separatedBy: .whitespacesAndNewlines)
			.filter { !$0.isEmpty }
			.joined(separator: " ")
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
