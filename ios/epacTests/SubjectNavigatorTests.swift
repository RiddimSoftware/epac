//
//  SubjectNavigatorTests.swift
//  epac
//
//  Created by Sunny on 2025-05-23.
//

import Foundation
import Testing

@testable import epac

struct SubjectNavigatorTests {
	@Test func messagesHaveUniqueIDs() throws {
		let fixtureURL = Bundle(for: ForThisOnly.self).url(
			forResource: "test-20241217",
			withExtension: "xml"
		)!
		let xmlstring = try String(contentsOf: fixtureURL, encoding: .utf8)
		let bro = XMLBro(xml: xmlstring).parseXML()
		var idCount = [String: Int]()

		bro.ordersOfBusiness.forEach { order in
			order.subjects.forEach { subject in
				let nav = SubjectNavigator(subject)
				while let msg = nav.next() {
					if idCount[msg.hansardID] == nil {
						idCount[msg.hansardID] = 0
					}
					idCount[msg.hansardID]! += 1
				}
				idCount.keys.forEach { key in
					#expect(idCount[key] == 1)
				}
			}
		}
	}
}
