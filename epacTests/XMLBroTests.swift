//
//  epacTests.swift
//  epacTests
//
//  Created by Sunny on 2024-12-08.
//

import Testing
import Foundation
@testable import epac

class ForThisOnly {

}

struct XMLBroTests {

	@Test func speechMessagesHaveUniqueHansardID() async throws {
		let fixtureURL = Bundle(for: ForThisOnly.self).url(forResource: "test-20241217", withExtension: "xml")!
		let xmlstring = try String(contentsOf: fixtureURL, encoding: .utf8)
		let bro = XMLBro(xml: xmlstring).parseXML()
		#expect(bro.ordersOfBusiness.count == 2)
		var idCount = [String: Int]()
		bro.ordersOfBusiness.forEach { order in
			order.subjects.forEach { subject in
				subject.speeches.forEach { speech in
					if idCount[speech.hansardID] == nil {
						idCount[speech.hansardID] = 0
					}
					idCount[speech.hansardID]! += 1
				}
			}
		}
		#expect(idCount.isEmpty == false)
		idCount.keys.forEach { key in
			#expect(idCount[key] == 1)
		}
	}

}
