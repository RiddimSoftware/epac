//
//  PhotoProvider.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-04-05.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation

class PhotoProvider {

	private let hostURL: URL
	init(parliamentNumber: Int) {
		hostURL = URL(string: "https://www.ourcommons.ca/Content/Parliamentarians/Images/OfficialMPPhotos/\(parliamentNumber)")!
	}

	func getPhotoURL(lastName: String, firstName: String, party: Party) -> URL {

		let url = hostURL.appending(
			path: "\(lastName.replacing(/\P{L}/, with: ""))\(firstName.replacing(/\P{L}/, with: ""))_\(party.abbreviation).jpg"
		)
		return url
	}

	func getPhotoURL2(lastName: String, firstName: String, party: Party) -> URL {
		let url = hostURL.appending(
			path: "\(lastName.replacingOccurrences(of: "-", with: ""))\(firstName)_\(party.abbreviation)"
				.replacingOccurrences(of: "'", with: "")
				.replacingOccurrences(of: " ", with: "")
				.replacingOccurrences(of: ".", with: "")
				.appending(".jpg")
		)
		return url
	}

	func getPhotoURL3(lastName: String, firstName: String, party: Party) -> URL {
		let url = hostURL.appending(
			path: "\(lastName.replacingOccurrences(of: "-", with: ""))\(firstName.replacingOccurrences(of: "-", with: ""))_\(party.abbreviation)"
				.replacingOccurrences(of: "'", with: "")
				.replacingOccurrences(of: " ", with: "")
				.replacingOccurrences(of: ".", with: "")
				.appending(".jpg")
		)
		return url
	}

	func getPhotoURL4(lastName: String, firstName: String, party: Party) -> URL {
		let url = hostURL.appending(
			path: "\(lastName.replacingOccurrences(of: "-", with: ""))\(firstName.replacingOccurrences(of: "-", with: ""))_\(party.abbreviation)"
				.replacingOccurrences(of: "ç", with: "c")
				.replacingOccurrences(of: "'", with: "")
				.replacingOccurrences(of: " ", with: "")
				.replacingOccurrences(of: ".", with: "")
				.appending(".jpg")
		)
		return url
	}

	func getPhotoURL5(lastName: String, firstName: String, party: Party) -> URL {
		let url = hostURL.appending(
			path: "\(lastName.replacingOccurrences(of: "-", with: ""))\(firstName)_\(party.abbreviation)"
				.replacingOccurrences(of: "ç", with: "c")
				.replacingOccurrences(of: "'", with: "")
				.replacingOccurrences(of: " ", with: "")
				.replacingOccurrences(of: ".", with: "")
				.appending(".jpg")
		)
		return url
	}

	func getPhotoURL6(lastName: String, firstName: String, party: Party) -> URL {
		let url = hostURL.appending(
			path: "\(lastName.replacing(/\P{L}/, with: ""))\(firstName.replacing(/\P{L}/, with: ""))_\(party.abbreviation).jpg"
				.replacingOccurrences(of: "ç", with: "c")
		)
		return url
	}

	func getPhotoURL7(lastName: String, firstName: String, party: Party) -> URL {
		let url = hostURL.appending(
			path: "\(lastName)\(firstName.replacingOccurrences(of: "-", with: ""))_\(party.abbreviation)"
				.replacingOccurrences(of: "'", with: "")
				.replacingOccurrences(of: " ", with: "")
				.replacingOccurrences(of: ".", with: "")
				.appending(".jpg")
		)
		return url
	}
}
