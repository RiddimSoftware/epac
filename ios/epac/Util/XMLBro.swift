//
//  XMLBro.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-04-13.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation
import SwiftData
import SWXMLHash

class XMLBro {
	private var xml: XMLIndexer
	var ordersOfBusiness: [OrderOfBusiness] = []
	var date: Date = Date()
	var hansardID: String = ""
	var parliamentNumber: Int = 0
	var sessionNumber: Int = 0

	init(xml: String) {
		self.xml = XMLHash.parse(xml)
	}

	func hansard() -> Hansard {
		return Hansard(date: date, hansardID: hansardID, parliamentNumber: parliamentNumber, sessionNumber: sessionNumber, orders: ordersOfBusiness)
	}

	func parseXML() -> Self {
		hansardID = xml["Hansard"].element?.attribute(by: "id")?.trimmedText() ?? ""
		
		let info = xml["Hansard"]["ExtractedInformation"]["ExtractedItem"].all
		let day = Int(info.first(where: { $0.element?.attribute(by: "Name")?.trimmedText().caseInsensitiveCompare("MetaDateNumDay") == .orderedSame })?.element?.text ?? "")
		let month = Int(info.first(where: { $0.element?.attribute(by: "Name")?.trimmedText().caseInsensitiveCompare("MetaDateNumMonth") == .orderedSame })?.element?.text ?? "")
		let year = Int(info.first(where: { $0.element?.attribute(by: "Name")?.trimmedText().caseInsensitiveCompare("MetaDateNumYear") == .orderedSame })?.element?.text ?? "")
		if let day, let month, let year, let date = Calendar.current.date(from: .init(year: year, month: month, day: day)) {
			self.date = date
		}

		parliamentNumber = Int(info.first(where: { $0.element?.attribute(by: "Name")?.trimmedText().caseInsensitiveCompare("ParliamentNumber") == .orderedSame })?.element?.text ?? "") ?? 0
		sessionNumber = Int(info.first(where: { $0.element?.attribute(by: "Name")?.trimmedText().caseInsensitiveCompare("SessionNumber") == .orderedSame })?.element?.text ?? "") ?? 0

		for oob in xml["Hansard"]["HansardBody"]["OrderOfBusiness"].all {
			guard let catchline = oob["CatchLine"].element?.trimmedText() else {
				continue
			}
			if catchline.lowercased() == NSLocalizedString("routine proceedings", comment: "") ||
					catchline.lowercased() == NSLocalizedString("adjournment proceedings", comment: "") {
				continue
			}
			guard let oobID = oob.element?.attribute(by: "id")?.trimmedText() else {
				continue
			}
			let order = OrderOfBusiness(hansardID: oobID, catchline: catchline)
			for sob in oob["SubjectOfBusiness"].all {
				let title = sob["SubjectOfBusinessTitle"].element?.trimmedText()
				guard let title else {
					continue
				}
				guard let sobID = sob.element?.attribute(by: "id")?.trimmedText() else {
					continue
				}
				let content = sob["SubjectOfBusinessContent"]
				let subject = SubjectOfBusiness(title: title, hansardID: sobID)
				for intervention in content["Intervention"].all {
					var personspeaking: String = ""
					for affiliation in intervention["PersonSpeaking"]["Affiliation"].all {
						personspeaking.append(text(fromXMLIndexer: affiliation))
					}
					personspeaking = personspeaking.trimmingCharacters(in: .whitespacesAndNewlines)

					guard !personspeaking.isEmpty,
								let interventionID = intervention.element?.attribute(by: "id")?.trimmedText() else {
						continue
					}
                    
                    let contentParas = paragraphArray(fromXML: intervention["Content"]["ParaText"])
                    
                    let parsed = parseAffiliationString(personspeaking)
					
					let cleanNames = parsed.speakerName.split(separator: " ").filter { !["Hon.", "Rt.", "Mr.", "Ms.", "Mrs.", "Mme.", "Dr.", "The", "Hon", "Rt", "Right"].contains(String($0)) }
					
					let firstName = cleanNames.dropLast().joined(separator: " ")
					let lastName = cleanNames.last
					
					if let lastName {
						let messages = contentParas.map { p in
							SpeechMessage(
								firstName: String(firstName),
								lastName: String(lastName),
								partyAbbreviation: parsed.partyAbbreviation,
								ridingName: parsed.ridingName,
								hansardID: p.id,
								content: p.content,
								timestamp: date
							)
						}
						let speech = Speech(messages: messages, hansardID: interventionID, date: date, title: title)
						subject.speeches.append(speech)
					}
				}
				if !subject.speeches.isEmpty {
					order.subjects.append(subject)
				}
			}
			if !order.subjects.isEmpty {
				ordersOfBusiness.append(order)
			}
		}
		return self
	}

	func parseAffiliationString(_ affiliationString: String) -> (speakerName: String, partyAbbreviation: String, ridingName: String) {
		let trimmedString = affiliationString.replacingOccurrences(of: "Mme ", with: "Mme. ").trimmingCharacters(in: .whitespacesAndNewlines)
		var speakerName = ""
		var partyAbbreviation = ""
		var ridingName = ""

		if let firstParenIndex = trimmedString.firstIndex(of: "(") {
			speakerName = String(trimmedString[..<firstParenIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
			
			let detailsStartIndex = trimmedString.index(after: firstParenIndex)
			if let lastParenIndex = trimmedString.lastIndex(of: ")") {
				let detailsSubstring = trimmedString[detailsStartIndex..<lastParenIndex]
				let details = String(detailsSubstring).trimmingCharacters(in: .whitespacesAndNewlines)

				if let lastCommaIndex = details.lastIndex(of: ",") {
					partyAbbreviation = String(details[details.index(after: lastCommaIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
					if partyAbbreviation.hasSuffix(".") {
						partyAbbreviation.removeLast()
					}
					
					let potentialRidingAndRole = String(details[..<lastCommaIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
					
					// Heuristic to extract riding name if present, otherwise assume it's part of the role.
					// Look for another comma to separate riding from role, or if it's a simple string.
					if let secondLastCommaIndex = potentialRidingAndRole.lastIndex(of: ",") {
						// This case might be "Role, Riding"
						let ridingPart = String(potentialRidingAndRole[potentialRidingAndRole.index(after: secondLastCommaIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
						if !ridingPart.isEmpty {
							ridingName = ridingPart
						}
					} else if !potentialRidingAndRole.isEmpty && !potentialRidingAndRole.contains("(") {
						// If no second comma and no inner parentheses, it might be just the riding name.
						ridingName = potentialRidingAndRole
					}
                    // For now, we are not trying to extract a specific 'role' beyond the speakerName
				} else {
					// No comma in details, this could be a simple riding or just a complex role.
					ridingName = details // Assign the whole detail string as ridingName for now, for simplicity.
				}
			}
		} else {
			// No parentheses, the whole string is the speaker name.
			speakerName = trimmedString
		}

		return (speakerName: speakerName, partyAbbreviation: partyAbbreviation, ridingName: ridingName)
	}

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

	                                                if let elem = node as? XMLElement {

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

	func text(fromXMLElement element: XMLElement) -> String {
		var text = String()
		if !element.children.isEmpty {
			for node in element.children {
				if let elem = node as? XMLElement {
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
	static func parseMembers(_ xml: String) -> [ParliamentMember] {
		let xml = XMLHash.parse(xml)
		let membersXML = xml["ArrayOfMemberOfParliament"]["MemberOfParliament"].all
		Log.debug("Parsing \(membersXML.count) members from XML")
		var members = [ParliamentMember]()
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
			let provider = PhotoProvider(parliamentNumber: 45)
			let mp = ParliamentMember(
				name: "\(firstName) \(lastName)",
				lastName: lastName,
				firstName: firstName,
				photoURL: provider.getPhotoURL(lastName: lastName, firstName: firstName, party: party),
				riding: constituencyName,
				province: province,
				party: party,
				memberID: personID,
				fromDateTime: fromDateTime,
				toDateTime: toDateTime
			)
			members.append(mp)
		}
		return members
	}

	static func parseConstituencies(_ xml: String) -> [Constituency] {
		let xml = XMLHash.parse(xml)
		let constituenciesXML = xml["ArrayOfConstituency"]["Constituency"].all
		var constituencies = [Constituency]()
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
			let c = Constituency(name: name, province: province, currentMemberFirstName: firstName, currentMemberLastName: lastName, currentMemberParty: party)
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

extension XMLElement {
	func trimmedText() -> String {
		return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
	}
}
