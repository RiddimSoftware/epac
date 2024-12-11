//
//  Speaker.swift
//  cabinetdoor
//
//  Created by Sunny on 2017-04-02.
//  Copyright © 2017 Sunny. All rights reserved.
//

import Foundation

class Speaker: CustomDebugStringConvertible, Hashable, Equatable, NSCoding {
	var name:           String
	var lastName:       String?
	var firstName:      String?
	var photoURL:       URL?
	var websiteURL:     URL?
	var riding:         String
	var party:          Party
	var speechcount:    Int = 0

	func encode(with aCoder: NSCoder) {
		aCoder.encode(name, forKey: "name")
		aCoder.encode(lastName, forKey: "lastName")
		aCoder.encode(firstName, forKey: "firstName")
		aCoder.encode(photoURL, forKey: "photoURL")
		aCoder.encode(websiteURL, forKey: "websiteURL")
		aCoder.encode(riding, forKey: "riding")
		aCoder.encode(party, forKey: "party")
		aCoder.encode(speechcount, forKey: "speechcount")
	}

	required init?(coder aDecoder: NSCoder) {
		self.name = aDecoder.decodeObject(forKey: "name") as! String
		self.lastName = aDecoder.decodeObject(forKey: "lastName") as? String
		self.firstName = aDecoder.decodeObject(forKey: "firstName") as? String
		self.photoURL = aDecoder.decodeObject(forKey: "photoURL") as? URL
		self.websiteURL = aDecoder.decodeObject(forKey: "websiteURL") as? URL
		self.riding = aDecoder.decodeObject(forKey: "riding") as! String
		self.party = aDecoder.decodeObject(forKey: "party") as! Party
		self.speechcount = aDecoder.decodeInteger(forKey: "speechcount")
	}

	init(name: String, riding: String, party: String) {
		self.name = name
		let names = name.components(separatedBy: " ")
		if let first = names.first,
			 first.count > 0 {
			firstName = first.components(separatedBy: CharacterSet.letters.inverted).joined()
		}
		lastName = String()
		for i in 1..<names.count {
			lastName!.append(names[i].components(separatedBy: CharacterSet.letters.inverted).joined())
		}
		//        if let last = names.last,
		//            last.characters.count > 0 {
		//            lastName = last.components(separatedBy: CharacterSet.letters.inverted).joined()
		//        }
		self.party = Party.partyWithAbbreviation(party)
		let partyAbbreviation = self.party.abbreviation
		self.riding = riding
		if let firstName = firstName, let lastName = lastName {
			self.photoURL = URL(string: PhotoProvider.instance.getPhotoURL(lastName: lastName, firstName: firstName, partyAbbreviation: partyAbbreviation))
		}
	}


	func hash(into hasher: inout Hasher) {
		hasher.combine(name)
	}

	public static func ==(lhs: Speaker, rhs: Speaker) -> Bool {
		return lhs.name == rhs.name
	}

	var debugDescription: String {
		return "\(name)\nRiding:\(riding)\nParty:\(party)\n"
	}
}
