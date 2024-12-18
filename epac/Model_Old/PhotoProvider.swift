//
//  PhotoProvider.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-04-05.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation

class PhotoProvider {

	private static let hostURL: URL = URL(string: "https://www.ourcommons.ca/Content/Parliamentarians/Images/OfficialMPPhotos/44")!

	static func getPhotoURL(lastName: String, firstName: String, party: Party) -> URL {

		let url = hostURL.appending(
			path: "\(lastName.replacing(/\P{L}/, with: ""))\(firstName.replacing(/\P{L}/, with: ""))_\(party.abbreviation).jpg"
		)
		return url
	}

	static func getPhotoURL2(lastName: String, firstName: String, party: Party) -> URL {
		let url = hostURL.appending(
			path: "\(lastName.replacingOccurrences(of: "-", with: ""))\(firstName)_\(party.abbreviation)"
				.replacingOccurrences(of: "'", with: "")
				.replacingOccurrences(of: " ", with: "")
				.replacingOccurrences(of: ".", with: "")
				.appending(".jpg")
		)
		return url
	}

	static func getPhotoURL3(lastName: String, firstName: String, party: Party) -> URL {
		let url = hostURL.appending(
			path: "\(lastName.replacingOccurrences(of: "-", with: ""))\(firstName.replacingOccurrences(of: "-", with: ""))_\(party.abbreviation)"
				.replacingOccurrences(of: "'", with: "")
				.replacingOccurrences(of: " ", with: "")
				.replacingOccurrences(of: ".", with: "")
				.appending(".jpg")
		)
		return url
	}
}
