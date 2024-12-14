//
//  Model+Hansard.swift
//  epac
//
//  Created by Sunny on 2024-12-13.
//

import SwiftData
import Foundation

@Model
final class Hansard {
	var date: Date
	var hansardID: String?
	var parliamentNumber: Int?
	var sessionNumber: Int?
	var orders: [OrderOfBusiness]
	init(date: Date, hansardID: String?, parliamentNumber: Int?, sessionNumber: Int?, orders: [OrderOfBusiness] = []) {
		self.date = date
		self.hansardID = hansardID
		self.parliamentNumber = parliamentNumber
		self.sessionNumber = sessionNumber
		self.orders = orders
	}
	init(xml: String) {
		let hansard = XMLBro(xml: xml).parseXML().hansard()
		date = hansard.date
		hansardID = hansard.hansardID
		parliamentNumber = hansard.parliamentNumber
		sessionNumber = hansard.sessionNumber
		orders = hansard.orders
	}
}
