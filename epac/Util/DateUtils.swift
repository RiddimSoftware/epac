//
//  Date.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-04-04.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation

struct DateFormatterInstance {
	let formatter: DateFormatter

	init?(format: String?, style: DateFormatter.Style?, locale: Locale = Locale.current) {
		formatter = DateFormatter()
		formatter.locale = locale
		if let format = format {
			formatter.dateFormat = format
		} else if let style = style {
			formatter.dateStyle = style
		} else {
			return nil
		}
	}
}

class DateUtils {

	static let instance = DateUtils()
	private static var csvDateFormatter_en: DateFormatterInstance = DateFormatterInstance(format: "yyyy-MM-dd", style: nil, locale: Locale(identifier: "en_CA"))!
	private static var csvDateFormatter_fr: DateFormatterInstance = DateFormatterInstance(format: "yyyy-MM-dd", style: nil, locale: Locale(identifier: "fr_CA"))!
	private lazy var fullDateFormatter: DateFormatterInstance = DateFormatterInstance(format: nil, style: .full)!
	private lazy var htmlDateFormatter_en: DateFormatterInstance = DateFormatterInstance(format: "EEEE MMM dd, yyyy", style: nil, locale: Locale(identifier: "en_CA"))!
	private lazy var htmlDateFormatter_fr: DateFormatterInstance = DateFormatterInstance(format: "EEEE dd MMM yyyy", style: nil, locale: Locale(identifier: "fr_CA"))!
	private lazy var committeeDateFormatter_en: DateFormatterInstance = DateFormatterInstance(format: "EEEE, MMM dd, yyyy", style: nil, locale: Locale(identifier: "en_CA"))!
	private lazy var committeeDateFormatter_fr: DateFormatterInstance = DateFormatterInstance(format: "EEEE dd MMM yyyy", style: nil, locale: Locale(identifier: "fr_CA"))!
	private lazy var shortDateFormatter: DateFormatterInstance = DateFormatterInstance(format: nil, style: .short)!
	private lazy var calendar: Calendar = Calendar.current

	func getDate(forCommitteeMeetingDateString string: String) -> Date {
		if Locale.current.identifier == "fr_CA" {
			return committeeDateFormatter_fr.formatter.date(from: string)!
		}
		else {
			return committeeDateFormatter_en.formatter.date(from: string)!
		}
	}

	static func getDate(forCSVDateString string: String) -> Date {
		if Locale.current.identifier == "fr_CA" {
			return csvDateFormatter_fr.formatter.date(from: string)!
		}
		else {
			return csvDateFormatter_en.formatter.date(from: string)!
		}
	}

	static func getCSVStringFromDate(_ date: Date) -> String {
		if Locale.current.identifier == "fr_CA" {
			return csvDateFormatter_fr.formatter.string(from: date)
		}
		else {
			return csvDateFormatter_en.formatter.string(from: date)
		}
	}

	func getShortString(fromDate date: Date) -> String {
		return shortDateFormatter.formatter.string(from: date)
	}

	func getDate(forShortString string: String) -> Date {
		return shortDateFormatter.formatter.date(from: string)!
	}

	func getFullStringForDate(_ date: Date) -> String {
		return fullDateFormatter.formatter.string(from: date)
	}

	func getDate(forHTMLDateString string: String) -> Date {
		if Locale.current.identifier == "fr_CA" {
			return htmlDateFormatter_fr.formatter.date(from: string)!
		}
		else {
			return htmlDateFormatter_en.formatter.date(from: string)!
		}
	}

	func getComponents(from date: Date) -> DateComponents {
		return calendar.dateComponents([.year, .month, .day], from: date)
	}
}
