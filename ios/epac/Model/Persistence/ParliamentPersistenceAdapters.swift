//
//  ParliamentPersistenceAdapters.swift
//  epac
//
//  Explicit mapping between plain parliamentary domain DTOs and SwiftData
//  persistence models.
//

import Foundation

extension ParliamentMember {
	convenience init(domain: ParliamentMemberDTO) {
		self.init(
			name: domain.name,
			lastName: domain.lastName,
			firstName: domain.firstName,
			photoURL: domain.photoURL,
			riding: domain.riding,
			province: domain.province,
			party: domain.party,
			websiteURL: domain.websiteURL,
			memberID: domain.memberID,
			fromDateTime: domain.fromDateTime,
			toDateTime: domain.toDateTime
		)
		imageData = domain.imageData
		email = domain.email
		hillPhone = domain.hillPhone
		constituencyPhone = domain.constituencyPhone
		constituencyAddress = domain.constituencyAddress
		contactFetched = domain.contactFetched
	}

	var domainDTO: ParliamentMemberDTO {
		ParliamentMemberDTO(
			name: name,
			memberID: memberID,
			lastName: lastName,
			firstName: firstName,
			photoURL: photoURL,
			riding: riding,
			province: province,
			party: party,
			websiteURL: websiteURL,
			imageData: imageData,
			fromDateTime: fromDateTime,
			toDateTime: toDateTime,
			email: email,
			hillPhone: hillPhone,
			constituencyPhone: constituencyPhone,
			constituencyAddress: constituencyAddress,
			contactFetched: contactFetched
		)
	}
}

extension Constituency {
	convenience init(domain: ConstituencyDTO) {
		self.init(
			name: domain.name,
			province: domain.province,
			currentMemberFirstName: domain.currentMemberFirstName,
			currentMemberLastName: domain.currentMemberLastName,
			currentMemberParty: domain.currentMemberParty
		)
	}

	var domainDTO: ConstituencyDTO {
		ConstituencyDTO(
			name: name,
			province: province,
			currentMemberFirstName: currentMemberFirstName,
			currentMemberLastName: currentMemberLastName,
			currentMemberParty: currentMemberParty
		)
	}
}

extension SpeechMessage {
	convenience init(domain: SpeechMessageDTO) {
		self.init(
			firstName: domain.firstName,
			lastName: domain.lastName,
			partyAbbreviation: domain.partyAbbreviation,
			ridingName: domain.ridingName,
			hansardID: domain.hansardID,
			content: domain.content,
			timestamp: domain.timestamp
		)
	}

	var domainDTO: SpeechMessageDTO {
		SpeechMessageDTO(
			firstName: firstName,
			lastName: lastName,
			partyAbbreviation: partyAbbreviation,
			ridingName: ridingName,
			hansardID: hansardID,
			content: content,
			timestamp: timestamp
		)
	}
}

extension Speech {
	convenience init(domain: SpeechDTO) {
		let messages = domain.messages.map(SpeechMessage.init(domain:))
		self.init(messages: messages, hansardID: domain.hansardID, date: domain.date, title: domain.title)
		currentMessageID = domain.currentMessageID
		currentMessage = messages.first(where: { $0.hansardID == domain.currentMessageID })
		length = domain.length
	}

	var domainDTO: SpeechDTO {
		SpeechDTO(
			messages: messages.map(\.domainDTO),
			hansardID: hansardID,
			currentMessageID: currentMessageID ?? currentMessage?.hansardID,
			date: date,
			length: length,
			title: title
		)
	}
}

extension SubjectOfBusiness {
	convenience init(domain: SubjectOfBusinessDTO) {
		let speeches = domain.speeches.map(Speech.init(domain:))
		self.init(title: domain.title, hansardID: domain.hansardID, speeches: speeches)
		currentSpeechID = domain.currentSpeechID
		currentSpeech = speeches.first(where: { $0.hansardID == domain.currentSpeechID })
	}

	var domainDTO: SubjectOfBusinessDTO {
		SubjectOfBusinessDTO(
			title: title,
			hansardID: hansardID,
			speeches: speeches.map(\.domainDTO),
			currentSpeechID: currentSpeechID ?? currentSpeech?.hansardID
		)
	}
}

extension OrderOfBusiness {
	convenience init(domain: OrderOfBusinessDTO) {
		self.init(
			hansardID: domain.hansardID,
			catchline: domain.catchline,
			subjects: domain.subjects.map(SubjectOfBusiness.init(domain:))
		)
	}

	var domainDTO: OrderOfBusinessDTO {
		OrderOfBusinessDTO(
			hansardID: hansardID,
			catchline: catchline,
			subjects: subjects.map(\.domainDTO)
		)
	}
}

extension Hansard {
	convenience init(domain: HansardDTO) {
		self.init(
			date: domain.date,
			hansardID: domain.hansardID,
			parliamentNumber: domain.parliamentNumber,
			sessionNumber: domain.sessionNumber,
			orders: domain.orders.map(OrderOfBusiness.init(domain:))
		)
	}

	var domainDTO: HansardDTO {
		HansardDTO(
			date: date,
			hansardID: hansardID,
			parliamentNumber: parliamentNumber,
			sessionNumber: sessionNumber,
			orders: orders.map(\.domainDTO)
		)
	}
}
