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
	var ordersOfBusiness: [OrderOfBusiness] = []
	var date: Date!
	var hansardID: String?
	var parliamentNumber: Int?
	var sessionNumber: Int?

	init(xml: String) {
		self.xml = XMLHash.parse(xml)
	}

	func hansard() -> Hansard {
		return Hansard(date: date, hansardID: hansardID, parliamentNumber: parliamentNumber, sessionNumber: sessionNumber, orders: ordersOfBusiness)
	}

	func parseXML() -> Self {
		let info = xml["Hansard"]["ExtractedInformation"]["ExtractedItem"].all
		let day = Int(info.first(where: { $0.element?.attribute(by: "Name")?.trimmedText().caseInsensitiveCompare("MetaDateNumDay") == .orderedSame })?.element?.text ?? "")
		let month = Int(info.first(where: { $0.element?.attribute(by: "Name")?.trimmedText().caseInsensitiveCompare("MetaDateNumMonth") == .orderedSame })?.element?.text ?? "")
		let year = Int(info.first(where: { $0.element?.attribute(by: "Name")?.trimmedText().caseInsensitiveCompare("MetaDateNumYear") == .orderedSame })?.element?.text ?? "")
		if let day, let month, let year, let date = Calendar.current.date(from: .init(year: year, month: month, day: day)) {
			self.date = date
		}

		parliamentNumber = Int(info.first(where: { $0.element?.attribute(by: "Name")?.trimmedText().caseInsensitiveCompare("ParliamentNumber") == .orderedSame })?.element?.text ?? "")
		sessionNumber = Int(info.first(where: { $0.element?.attribute(by: "Name")?.trimmedText().caseInsensitiveCompare("SessionNumber") == .orderedSame })?.element?.text ?? "")

		for oob in xml["Hansard"]["HansardBody"]["OrderOfBusiness"].all {
			guard let catchline = oob["CatchLine"].element?.trimmedText() else {
				continue
			}
			if catchline.lowercased() == NSLocalizedString("routine proceedings", comment:"") ||
					catchline.lowercased() == NSLocalizedString("adjournment proceedings", comment:"") {
				continue
			}
			let id: String? = oob.element?.attribute(by: "id")?.trimmedText()
			let order = OrderOfBusiness(hansardID: id, catchline: catchline)
			for sob in oob["SubjectOfBusiness"].all {
				let title = sob["SubjectOfBusinessTitle"].element?.trimmedText()
				guard let title else {
					continue
				}
				let sobID = sob.element?.attribute(by: "id")?.trimmedText()
				let content = sob["SubjectOfBusinessContent"]
				let subject = SubjectOfBusiness(title: title, hansardID: sobID)
				for intervention in content["Intervention"].all {
					var personspeaking: String? = intervention["PersonSpeaking"]["Affiliation"].element?.trimmedText()
					if personspeaking == nil {
						for affiliation in intervention["PersonSpeaking"]["Affiliation"].all {
							if let namefragment = affiliation.element?.trimmedText() {
								if personspeaking == nil {
									personspeaking = ""
								}
								personspeaking!.append(namefragment)
							}
						}
					}
					guard personspeaking != nil,
								let interventionID = intervention.element?.attribute(by: "id")?.trimmedText() else {
						continue
					}
					var speakername: String = ""
					var partyname: String = ""
					var ridingname: String = ""
					var startspeaker: Bool?
					var startparty: Bool?
					var startriding: Bool?
					personspeaking = personspeaking!.replacingOccurrences(of: "Mme ", with: "Mme. ")
					let startindex = personspeaking!.startIndex
					let endindex = personspeaking!.endIndex
					for i in 0..<personspeaking!.count {
						let index = personspeaking!.index(startindex, offsetBy: i)
						let backindex = personspeaking!.index(endindex, offsetBy: -(i+1))
						if let start = startspeaker, start {
							if personspeaking![index] == "(" {
								startspeaker = false
							}
							else {
								speakername.append(personspeaking![index])
							}
						}
						else {
							if personspeaking![index] == "." && startspeaker == nil {
								startspeaker = true
							}
						}
						if let start = startparty, start {
							if personspeaking![backindex] == "," {
								startparty = false
							}
							else {
								partyname.append(personspeaking![backindex])
							}
						}
						else {
							if personspeaking![backindex] == ")" && startparty == nil {
								startparty = true
							}
						}
						if let start = startriding, start {
							if personspeaking![backindex] == "(" {
								startriding = false
							}
							else {
								ridingname.append(personspeaking![backindex])
							}
						}
						else {
							if personspeaking![backindex] == "," && startriding == nil {
								startriding = true
							}
						}
					}
					partyname = String(partyname.trimmingCharacters(in: CharacterSet.letters.inverted).reversed())
					speakername = speakername.trimmingCharacters(in: CharacterSet.whitespaces)
					ridingname = String(ridingname.trimmingCharacters(in: CharacterSet.whitespaces).reversed())
					let speaker = ParliamentMember(name: speakername, riding: ridingname, party: Party.partyWithAbbreviation(partyname))
					let content = paragraphArray(fromXML: intervention["Content"]["ParaText"])
					/// TODO: Use actual timestamp and dates
					let messages = content.map { SpeechMessage(speaker: speaker, hansardID: $0.id, content: $0.content, timestamp: .now) }
					let speech = Speech(messages: messages, hansardID: interventionID, date: .now, length: messages.count, title: title)
					//					let speech = Speech(id: id, speaker: speaker, content: content, date: Date())
					subject.speeches.append(speech)
				}
				if subject.speeches.count > 0 {
					order.subjects.append(subject)
				}
			}
			if order.subjects.count > 0 {
				ordersOfBusiness.append(order)
			}
		}
		return self
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
		var childcount = 0
		for elchild in indexer.element!.children {
			if elchild.description.contains("</") && indexer.element != nil {
				text.append(self.text(fromXMLIndexer: indexer.children[childcount]))
				childcount += 1
			}
			else {
				text.append(elchild.description)
			}
		}
		return text
	}

	func text(fromXMLElement element: XMLElement) -> String {
		var text = String()
		if element.children.count > 0 {
			for child in element.children {
				if child.description.contains("</") {
					//                    text.append(self.text(fromXMLElement: ))
				}
				else {
					text.append(child.description)
				}
			}
		}
		else {
			text.append(element.text)
		}
		return text
	}
}

extension XMLAttribute {
	func trimmedText() -> String {
		return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
	}
}

extension XMLElement {
	func trimmedText() -> String {
		return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
	}
}
