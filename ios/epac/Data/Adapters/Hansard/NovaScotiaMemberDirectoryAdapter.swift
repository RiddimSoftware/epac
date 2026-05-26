//
//  NovaScotiaMemberDirectoryAdapter.swift
//  epac
//

import Foundation
import Kanna

struct NovaScotiaMemberDirectoryAdapter {
	typealias FetchData = @Sendable (URL) async throws -> Data
	typealias Sleep = @Sendable (UInt64) async throws -> Void

	private let fetchData: FetchData
	private let sleep: Sleep
	private let profileRequestDelayNanoseconds: UInt64

	init(
		fetchData: @escaping FetchData = NovaScotiaMemberDirectoryHTTPClient.fetchData,
		sleep: @escaping Sleep = Task.sleep(nanoseconds:),
		profileRequestDelayNanoseconds: UInt64 = Constants.profileRequestDelayNanoseconds
	) {
		self.fetchData = fetchData
		self.sleep = sleep
		self.profileRequestDelayNanoseconds = profileRequestDelayNanoseconds
	}

	func fetchMembers() async throws -> [ParliamentMemberDTO] {
		let data = try await fetchData(Constants.rosterURL)
		guard let html = String(data: data, encoding: .utf8) else {
			throw NovaScotiaMemberDirectoryAdapterError.invalidRosterHTML
		}
		let members = try parse(html: html)
		return try await enrichContactDetails(for: members)
	}

	func parse(html: String) throws -> [ParliamentMemberDTO] {
		guard let document = try? HTML(html: html, url: Constants.rosterURL.absoluteString, encoding: .utf8) else {
			throw NovaScotiaMemberDirectoryAdapterError.invalidRosterHTML
		}
		let tileMembers = document.css(".view-mla-profile-listing .views-row").compactMap(parseTileMember)
		if !tileMembers.isEmpty {
			return tileMembers
		}
		return document.css("table.views-table.cols-3 tbody tr").compactMap(parseTableMember)
	}

	func parseContactDetails(html: String) throws -> NovaScotiaMemberContact {
		guard let document = try? HTML(html: html, url: Constants.rosterURL.absoluteString, encoding: .utf8) else {
			throw NovaScotiaMemberDirectoryAdapterError.invalidProfileHTML
		}
		guard let contactNode = document.at_css(".mla-current-profile-contact") else {
			return NovaScotiaMemberContact.empty
		}
		let telLinks = contactNode.css("a[href^='tel:']").compactMap { $0.text?.trimmed.nonEmpty }
		return NovaScotiaMemberContact(
			email: email(in: contactNode),
			constituencyPhone: telLinks.first,
			hillPhone: telLinks.dropFirst().first,
			constituencyAddress: constituencyAddress(in: contactNode)
		)
	}

	private func enrichContactDetails(for members: [ParliamentMemberDTO]) async throws -> [ParliamentMemberDTO] {
		var enriched: [ParliamentMemberDTO] = []
		for (index, member) in members.enumerated() {
			enriched.append(await enrichedMember(member))
			if index < members.index(before: members.endIndex) {
				try await sleep(profileRequestDelayNanoseconds)
			}
		}
		return enriched
	}

	private func enrichedMember(_ member: ParliamentMemberDTO) async -> ParliamentMemberDTO {
		guard let websiteURL = member.websiteURL else { return member }
		guard let data = try? await fetchData(websiteURL) else { return member }
		guard let html = String(data: data, encoding: .utf8) else { return member }
		let contact = (try? parseContactDetails(html: html)) ?? .empty
		return member.applying(contact: contact)
	}

	private func parseTileMember(row: Kanna.XMLElement) -> ParliamentMemberDTO? {
		guard let nameElement = row.at_css(".views-field-field-last-name"),
		      let partyText = row.at_css(".views-field-field-party")?.text?.trimmed,
		      let riding = row.at_css(".views-field-field-constituency-name")?.text?.trimmed.nonEmpty,
		      let name = memberName(from: nameElement.text ?? "") else {
			return nil
		}
		return makeMember(
			name: name,
			partyText: partyText,
			riding: riding,
			photoURL: photoURL(in: row),
			websiteURL: profileURL(in: nameElement)
		)
	}

	private func parseTableMember(row: Kanna.XMLElement) -> ParliamentMemberDTO? {
		let cells = row.css("td")
		guard cells.count >= Constants.tableColumnCount,
		      let name = memberName(from: cells[Constants.nameColumnIndex].text ?? ""),
		      let partyText = cells[Constants.partyColumnIndex].text?.trimmed.nonEmpty,
		      let riding = cells[Constants.ridingColumnIndex].text?.trimmed.nonEmpty else {
			return nil
		}
		return makeMember(
			name: name,
			partyText: partyText,
			riding: riding,
			photoURL: Constants.placeholderPhotoURL,
			websiteURL: profileURL(in: cells[Constants.nameColumnIndex])
		)
	}

	private func makeMember(
		name: NovaScotiaMemberName,
		partyText: String,
		riding: String,
		photoURL: URL,
		websiteURL: URL?
	) -> ParliamentMemberDTO {
		ParliamentMemberDTO(
			name: "\(name.firstName) \(name.lastName)",
			memberID: 0,
			lastName: name.lastName,
			firstName: name.firstName,
			photoURL: photoURL,
			riding: riding,
			province: .NS,
			party: party(from: partyText),
			websiteURL: websiteURL,
			imageData: nil,
			fromDateTime: nil,
			toDateTime: nil,
			email: nil,
			hillPhone: nil,
			constituencyPhone: nil,
			constituencyAddress: nil,
			contactFetched: false,
			jurisdiction: .novaScotia
		)
	}

	private func memberName(from rawText: String) -> NovaScotiaMemberName? {
		let cleaned = rawText
			.replacingOccurrences(of: "Hon.", with: "")
			.collapsingWhitespace
			.trimmed
		let parts = cleaned.components(separatedBy: ",").map(\.trimmed).filter(\.isMeaningful)
		if parts.count >= Constants.namePartCount {
			return NovaScotiaMemberName(firstName: parts[1], lastName: parts[0])
		}
		let words = cleaned.split(separator: " ").map(String.init)
		guard let first = words.first, let last = words.last, words.count >= Constants.namePartCount else { return nil }
		return NovaScotiaMemberName(firstName: first, lastName: last)
	}

	private func profileURL(in element: Kanna.XMLElement) -> URL? {
		guard let href = element.at_css("a")?["href"] else { return nil }
		let currentHref = href.replacingOccurrences(of: "/history", with: "")
		return URL(string: currentHref, relativeTo: Constants.siteURL)?.absoluteURL
	}

	private func photoURL(in row: Kanna.XMLElement) -> URL {
		guard let src = row.at_css(".views-field-field-thumbnail img")?["src"],
		      let url = URL(string: src, relativeTo: Constants.siteURL)?.absoluteURL else {
			return Constants.placeholderPhotoURL
		}
		return url
	}

	private func party(from text: String) -> Party {
		let normalized = text.lowercased()
		if normalized.contains("pc") || normalized.contains("progressive conservative") {
			return .conservative
		}
		if normalized.contains("ndp") || normalized.contains("new democratic") {
			return .newdemocratic
		}
		return Party.partyWithAbbreviation(text.trimmed)
	}

	private func email(in element: Kanna.XMLElement) -> String? {
		element.css("a[href^='mailto:']")
			.compactMap { link in
				link["href"]?
					.replacingOccurrences(of: "mailto:", with: "")
					.trimmed
					.nonEmpty
			}
			.first(where: { $0.caseInsensitiveCompare(Constants.footerEmail) != .orderedSame })
	}

	private func constituencyAddress(in element: Kanna.XMLElement) -> String? {
		guard let paragraph = element.css("p").first else { return nil }
		let lines = textLines(in: paragraph).filter { $0 != Constants.civicAddressLabel }
		return lines.isEmpty ? nil : lines.joined(separator: ", ")
	}

	private func textLines(in element: Kanna.XMLElement) -> [String] {
		(element.text ?? "")
			.components(separatedBy: .newlines)
			.map(\.trimmed)
			.filter(\.isMeaningful)
	}
}

struct NovaScotiaMemberContact: Equatable {
	let email: String?
	let constituencyPhone: String?
	let hillPhone: String?
	let constituencyAddress: String?

	static let empty = NovaScotiaMemberContact(
		email: nil,
		constituencyPhone: nil,
		hillPhone: nil,
		constituencyAddress: nil
	)
}

enum NovaScotiaMemberDirectoryAdapterError: Error, Equatable {
	case invalidRosterHTML
	case invalidProfileHTML
}

private struct NovaScotiaMemberName {
	let firstName: String
	let lastName: String
}

private enum Constants {
	static let siteURL = URL(string: "https://nslegislature.ca")!
	static let rosterURL = URL(string: "https://nslegislature.ca/members/profiles/65")!
	static let placeholderPhotoURL = URL(string: "https://nslegislature.ca/sites/all/themes/ns_leg/logo.png")!
	static let footerEmail = "info@nslegislature.ca"
	static let civicAddressLabel = "Civic address:"
	static let tableColumnCount = 3
	static let nameColumnIndex = 0
	static let partyColumnIndex = 1
	static let ridingColumnIndex = 2
	static let namePartCount = 2
	static let requestTimeout: TimeInterval = 20
	static let profileRequestDelayNanoseconds: UInt64 = 1_000_000_000
	static let successStatusLowerBound = 200
	static let successStatusUpperBound = 300

	static var successStatusCodes: Range<Int> {
		successStatusLowerBound..<successStatusUpperBound
	}
}

private enum NovaScotiaMemberDirectoryHTTPClient {
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

private extension ParliamentMemberDTO {
	func applying(contact: NovaScotiaMemberContact) -> ParliamentMemberDTO {
		ParliamentMemberDTO(
			name: name,
			memberID: memberID,
			lastName: lastName,
			firstName: firstName,
			photoURL: photoURL,
			riding: riding,
			province: province,
			party: party,
			websiteURL: websiteURL,
			imageData: imageData,
			fromDateTime: fromDateTime,
			toDateTime: toDateTime,
			email: contact.email,
			hillPhone: contact.hillPhone,
			constituencyPhone: contact.constituencyPhone,
			constituencyAddress: contact.constituencyAddress,
			contactFetched: true,
			jurisdiction: jurisdiction
		)
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

	var collapsingWhitespace: String {
		components(separatedBy: .whitespacesAndNewlines)
			.filter { !$0.isEmpty }
			.joined(separator: " ")
	}
}
