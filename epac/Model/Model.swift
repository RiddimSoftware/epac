//
//  Model.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-04-02.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation
import UIKit

class Model: ObservableObject {
	enum CSVHeaders: String {
		case party          = "speakerparty"
		case riding         = "speakerriding"
		case name           = "speakername"
		case website        = "speakerurl"
		case content        = "speechtext"
		case speechdate     = "speechdate"
		case maintopic      = "maintopic"
		case subtopic       = "subtopic"
		case subsubtopic    = "subsubtopic"
		case basepk         = "basepk"
	}
	private let minYear = 2016
	private let maxYear = 2018
	private let minMonth = 1
	private let maxMonth = 13
	private let calendar = Calendar(identifier: .gregorian)

	private let downloader: Downloader = Downloader()
	static let instance = Model()

	var calendardates:          [Date]?
	var dateSpeakerSpeeches:    [Date:[Speaker:[Speech]]] = [:]
	var dateSpeakers:           [Date:[Speaker]] = [:]
	var dateorders:             [Date:[OrderOfBusiness]] = [:]
	var dateordersubjets:       [Date:[OrderOfBusiness:[SubjectOfBusiness]]] = [:]
	var dateSubTopics:          [Date:[Topic]] = [:]
	var dateSubTopicSpeeches:   [Date:[Topic:[Speech]]] = [:]
	var dateMainTopics:         [Date:[Topic]] = [:]
	var dateMainTopicSpeeches:  [Date:[Topic:[Speech]]] = [:]
	var debateIndex:            [String:Int]
	var debateProgress:         [String:Double]
	var speakerImages:          [Speaker:UIImage] = [:]

	private var files: [Date:URL] = [:]

	init() {
		if let savedIndexes = UserDefaults.standard.value(forKey: "debateindex") as? [String:Int],
			 let savedProgress = UserDefaults.standard.value(forKey: "debateprogress") as? [String:Double] {
			debateIndex = savedIndexes
			debateProgress = savedProgress
		}
		else {
			debateIndex = [:]
			debateProgress = [:]
		}
		NotificationCenter.default.addObserver(self, selector: #selector(onDebateSpeak(_:)), name: Debate.speaknotification, object: nil)
	}

	func getCalendar() async throws -> [Date] {
		let dates = try await downloader.downloadCalendar()
		self.calendardates = dates
		return dates
	}

	func getOrdersOfBusiness(forDate date: Date) async throws -> [OrderOfBusiness] {
		let xmlstring = try await downloader.downloadXML(forDate: date)
		let bro = XMLBro(xml: xmlstring)
		bro.parseXML()
		dateorders[date] = bro.ordersOfBusiness
		return bro.ordersOfBusiness
	}
}

extension Model {
	@objc func onDebateSpeak(_ notification:  Notification) {
		guard let debate = notification.object as? Debate else {
			return
		}
		if var index = debateIndex.removeValue(forKey: debate.subject.id) {
			index += 1
			debateIndex[debate.subject.id] = index
			debateProgress[debate.subject.id] = Double(index+1) / Double(debate.length)
		}
		else {
			debateIndex[debate.subject.id] = 0
			debateProgress[debate.subject.id] = Double(1) / Double(debate.length)
		}
		UserDefaults.standard.set(debateIndex, forKey: "debateindex")
		UserDefaults.standard.set(debateProgress, forKey: "debateprogress")
	}
}
