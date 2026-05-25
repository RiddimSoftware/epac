//
//  XMLBro.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-04-13.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation
import SWXMLHash

class XMLBro {
	private var xml: XMLIndexer
	var ordersOfBusiness: [OrderOfBusinessDTO] = []
	var date: Date = Date()
	var hansardID: String = ""
	var parliamentNumber: Int = 0
	var sessionNumber: Int = 0

	init(xml: String) {
		self.xml = XMLHash.parse(xml)
	}

	func hansard() -> HansardDTO {
		return HansardDTO(date: date, hansardID: hansardID, parliamentNumber: parliamentNumber, sessionNumber: sessionNumber, orders: ordersOfBusiness)
	}

	func parseXML() -> Self {
		hansardID = xml["Hansard"].element?.attribute(by: "id")?.trimmedText() ?? ""

		let info = xml["Hansard"]["ExtractedInformation"]["ExtractedItem"].all
		if let date = extractDate(from: info) {
			self.date = date
		}
		parliamentNumber = extractParliamentNumber(from: info)
		sessionNumber = extractSessionNumber(from: info)
		ordersOfBusiness = xml["Hansard"]["HansardBody"]["OrderOfBusiness"].all.compactMap(parseOrderOfBusiness)
		return self
	}

	private func extractDate(from info: [XMLIndexer]) -> Date? {
		let day = Int(extractedInfoText(named: "MetaDateNumDay", from: info))
		let month = Int(extractedInfoText(named: "MetaDateNumMonth", from: info))
		let year = Int(extractedInfoText(named: "MetaDateNumYear", from: info))
		guard let day, let month, let year else {
			return nil
		}
		return Calendar.current.date(from: .init(year: year, month: month, day: day))
	}

	private func extractParliamentNumber(from info: [XMLIndexer]) -> Int {
		Int(extractedInfoText(named: "ParliamentNumber", from: info)) ?? 0
	}

	private func extractSessionNumber(from info: [XMLIndexer]) -> Int {
		Int(extractedInfoText(named: "SessionNumber", from: info)) ?? 0
	}

	private func extractedInfoText(named name: String, from info: [XMLIndexer]) -> String {
		info.first {
			$0.element?.attribute(by: "Name")?.trimmedText().caseInsensitiveCompare(name) == .orderedSame
		}?.element?.text ?? ""
	}

	private func parseOrderOfBusiness(_ oob: XMLIndexer) -> OrderOfBusinessDTO? {
		guard
			let catchline = oob["CatchLine"].element?.trimmedText(),
			!shouldSkipOrderOfBusiness(catchline),
			let oobID = oob.element?.attribute(by: "id")?.trimmedText()
		else {
			return nil
		}
		let subjects = oob["SubjectOfBusiness"].all.compactMap(parseSubjectOfBusiness)
		guard !subjects.isEmpty else {
			return nil
		}
		return OrderOfBusinessDTO(hansardID: oobID, catchline: catchline, subjects: subjects)
	}

	private func shouldSkipOrderOfBusiness(_ catchline: String) -> Bool {
		let normalized = catchline.lowercased()
		return normalized == "routine proceedings" || normalized == "adjournment proceedings"
	}

	private func parseSubjectOfBusiness(_ sob: XMLIndexer) -> SubjectOfBusinessDTO? {
		guard
			let title = sob["SubjectOfBusinessTitle"].element?.trimmedText(),
			let sobID = sob.element?.attribute(by: "id")?.trimmedText()
		else {
			return nil
		}
		let speeches = sob["SubjectOfBusinessContent"]["Intervention"].all.compactMap { intervention in
			parseSpeech(intervention, title: title)
		}
		guard !speeches.isEmpty else {
			return nil
		}
		return SubjectOfBusinessDTO(title: title, hansardID: sobID, speeches: speeches, currentSpeechID: nil)
	}

	private func parseSpeech(_ intervention: XMLIndexer, title: String) -> SpeechDTO? {
		let personspeaking = speakerText(from: intervention)
		guard
			!personspeaking.isEmpty,
			let interventionID = intervention.element?.attribute(by: "id")?.trimmedText()
		else {
			return nil
		}
		let parsed = HansardSpeakerParser.parse(personspeaking)
		guard let lastName = parsed.lastName else {
			return nil
		}
		let messages = speechMessages(
			from: intervention["Content"]["ParaText"],
			firstName: parsed.firstName,
			lastName: String(lastName),
			partyAbbreviation: parsed.partyAbbreviation,
			ridingName: parsed.ridingName
		)
		return SpeechDTO(
			messages: messages,
			hansardID: interventionID,
			currentMessageID: nil,
			date: date,
			length: messages.count,
			title: title
		)
	}

	private func speakerText(from intervention: XMLIndexer) -> String {
		intervention["PersonSpeaking"]["Affiliation"].all
			.map(text(fromXMLIndexer:))
			.joined()
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private func speechMessages(
		from paraText: XMLIndexer,
		firstName: String,
		lastName: String,
		partyAbbreviation: String,
		ridingName: String
	) -> [SpeechMessageDTO] {
		paragraphArray(fromXML: paraText).map { paragraph in
			SpeechMessageDTO(
				firstName: firstName,
				lastName: lastName,
				partyAbbreviation: partyAbbreviation,
				ridingName: ridingName,
				hansardID: paragraph.id,
				content: paragraph.content,
				timestamp: date
			)
		}
	}

	private static let defaultParliamentNumberForMemberPhotos = 45

	struct Paragraph {
		var content: String
		var id: String
	}

	                        func paragraphArray(fromXML xml: XMLIndexer) -> [Paragraph] {

	                                var paras = [Paragraph]()

	                                for p in xml.all {

	                                        let text = text(fromXMLIndexer: p)

	                                        if let id = p.element?.attribute(by: "id")?.text {

	                                                paras.append(Paragraph(content: text, id: id))

	                                        }

	                                }

	                                return paras

	                        }

	                        func text(fromXMLIndexer indexer: XMLIndexer) -> String {

	                                var text = String()

	                                if let element = indexer.element {

	                                        for node in element.children {

	                                                if let elem = node as? SWXMLHash.XMLElement {

	                                                        // Recursively get text from sub-elements

	                                                        text.append(self.text(fromXMLElement: elem))

	                                                } else {

	                                                        // This should handle text nodes and others

	                                                        text.append(node.description)

	                                                }

	                                        }

	                                }

	                                return text

	                        }

	func text(fromXMLElement element: SWXMLHash.XMLElement) -> String {
		var text = String()
		if !element.children.isEmpty {
			for node in element.children {
				if let elem = node as? SWXMLHash.XMLElement {
					text.append(self.text(fromXMLElement: elem))
				} else {
					text.append(node.description)
				}
			}
		} else {
			text.append(element.text)
		}
		return text
	}
}

extension XMLBro {
	static func parseMembers(_ xml: String) -> [ParliamentMemberDTO] {
		let xml = XMLHash.parse(xml)
		let membersXML = xml["ArrayOfMemberOfParliament"]["MemberOfParliament"].all
		Log.debug("Parsing \(membersXML.count) members from XML")
		var members = [ParliamentMemberDTO]()
		let dateFormatter = ISO8601DateFormatter()
		dateFormatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
		for member in membersXML {
			let personID = Int(member["PersonId"].element?.trimmedText() ?? "0")
			let firstName = member["PersonOfficialFirstName"].element?.trimmedText()
			let lastName = member["PersonOfficialLastName"].element?.trimmedText()
			let constituencyName = member["ConstituencyName"].element?.trimmedText()
			let provinceName = member["ConstituencyProvinceTerritoryName"].element?.trimmedText()
			let caucus = member["CaucusShortName"].element?.trimmedText()
			let fromDateTimeString = member["FromDateTime"].element?.trimmedText()
			let toDateTimeString = member["ToDateTime"].element?.trimmedText()

			guard let personID, let firstName, let lastName, let constituencyName, let provinceName, let caucus else {
				Log.debug("Member XML missing fields")
				continue
			}
			let fromDateTime = fromDateTimeString.flatMap { dateFormatter.date(from: $0 + "Z") ?? dateFormatter.date(from: $0) }
			let toDateTime = toDateTimeString.flatMap { dateFormatter.date(from: $0 + "Z") ?? dateFormatter.date(from: $0) }

			let party = Party.partyWithAbbreviation(caucus)
			let province = Province(rawValue: provinceName) ?? Province(rawValue: provinceName.replacingOccurrences(of: "é", with: "e")) ?? .Ontario
			let provider = PhotoProvider(parliamentNumber: defaultParliamentNumberForMemberPhotos)
			let mp = ParliamentMemberDTO(
				name: "\(firstName) \(lastName)",
				memberID: personID,
				lastName: lastName,
				firstName: firstName,
				photoURL: provider.getPhotoURL(lastName: lastName, firstName: firstName, party: party),
				riding: constituencyName,
				province: province,
				party: party,
				websiteURL: nil,
				imageData: nil,
				fromDateTime: fromDateTime,
				toDateTime: toDateTime,
				email: nil,
				hillPhone: nil,
				constituencyPhone: nil,
				constituencyAddress: nil,
				contactFetched: false,
				jurisdiction: .federal
			)
			members.append(mp)
		}
		return members
	}

	static func parseConstituencies(_ xml: String) -> [ConstituencyDTO] {
		let xml = XMLHash.parse(xml)
		let constituenciesXML = xml["ArrayOfConstituency"]["Constituency"].all
		var constituencies = [ConstituencyDTO]()
		for constituency in constituenciesXML {
			let firstName = constituency["CurrentPersonOfficialFirstName"].element?.trimmedText()
			let lastName = constituency["CurrentPersonOfficialLastName"].element?.trimmedText()
			let name = constituency["Name"].element?.trimmedText()
			let provinceName = constituency["ProvinceTerritoryName"].element?.trimmedText()
			let partyName = constituency["CurrentCaucusShortName"].element?.trimmedText()
			guard let firstName, let lastName, let name, let provinceName, let partyName else {
				Log.debug("Member XML missing fields")
				continue
			}
			guard let party = Party.allCases.first(where: { $0.shortName == partyName }) else {
				Log.debug("Member XML invalid caucus")
				continue
			}
			guard let province = Province(rawValue: provinceName) else {
				Log.debug("Member XML invalid province")
				continue
			}
			let c = ConstituencyDTO(name: name, province: province, currentMemberFirstName: firstName, currentMemberLastName: lastName, currentMemberParty: party)
			constituencies.append(c)
		}
		return constituencies
	}
}

extension XMLAttribute {
	func trimmedText() -> String {
		return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
	}
}

struct MemberContactInfo {
	var email: String?
	var hillPhone: String?
	var constituencyPhone: String?
	var constituencyAddress: String?
}

extension XMLBro {
	static func parseMemberContact(_ xmlString: String) -> MemberContactInfo {
		let xml = XMLHash.parse(xmlString)
		let root = xml["MemberOfParliament"]
		let email = root["Email"].element?.trimmedText().nonEmpty
		let hillPhone = root["HillOffice"]["MainVoiceNumber"].element?.trimmedText().nonEmpty
		let firstOffice = root["ConstituencyOfficeList"]["ConstituencyOffice"].all.first
		let constituencyPhone = firstOffice?["MainVoiceNumber"].element?.trimmedText().nonEmpty
		let addr = firstOffice?["Address"]
		let parts = [
			addr?["AddressLine1"].element?.trimmedText(),
			addr?["AddressLine2"].element?.trimmedText(),
			addr?["City"].element?.trimmedText(),
			addr?["Province"].element?.trimmedText(),
			addr?["PostalCode"].element?.trimmedText()
		].compactMap { $0?.nonEmpty }
		let constituencyAddress = parts.isEmpty ? nil : parts.joined(separator: ", ")
		return MemberContactInfo(email: email, hillPhone: hillPhone,
								 constituencyPhone: constituencyPhone,
								 constituencyAddress: constituencyAddress)
	}
}

private extension String {
	var nonEmpty: String? { isEmpty ? nil : self }
}

extension SWXMLHash.XMLElement {
	func trimmedText() -> String {
		return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
	}
}
