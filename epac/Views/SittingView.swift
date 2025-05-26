//
//  SittingView.swift
//  epac
//
//  Created by Sunny on 2024-12-13.
//

import SwiftUI
import SwiftData

struct SittingView: View {
	@Environment(\.modelContext) var modelContext
	@EnvironmentObject var fetch: Fetch
	let hansard: Hansard
	@Binding var selectedSubject: SubjectOfBusiness?
	@Query var members: [ParliamentMember]

	private func getMember(_ firstName: String, _ lastName: String) -> ParliamentMember? {
		if let member = members.first(where: { $0.firstName == firstName && $0.lastName == lastName }) {
			return member
		}

		Task {
			try? await fetch.downloadMember(firstName, lastName)
		}
		
//		if let constituency = try? modelContext.fetch(FetchDescriptor<Constituency>(predicate: #Predicate {
//			$0.name == riding || $0.name.starts(with: riding)
//		})).first {
//			let party = Party.partyWithAbbreviation(partyAbbreviation)
//			return ParliamentMember(
//			 name: "\(firstName) \(lastName)",
//			 lastName: lastName,
//			 firstName: firstName,
//			 photoURL: PhotoProvider(parliamentNumber: hansard.parliamentNumber).getPhotoURL(lastName: lastName, firstName: firstName, party: party),
//			 riding: riding,
//			 province: constituency.province,
//			 party: party
//		 )
//		}

		return nil
	}

	var body: some View {
		List {
			ForEach(hansard.orders.sorted(by: { $0.hansardID < $1.hansardID }).filter { !$0.subjects.isEmpty }) { order in
				Section {
					ForEach(order.subjects.sorted(by: { $0.hansardID < $1.hansardID }).filter { !$0.speeches.isEmpty }) { subject in
						HStack {
							Text(subject.title)
							Spacer()
							VStack(alignment: .trailing, spacing: 5) {
								ForEach(Array(Set(subject.speeches.compactMap { getMember($0.messages.first!.firstName, $0.messages.first!.lastName) })).sorted(by: { $0.lastName < $1.lastName })) { member in
									SittingSpeakerView(member: member)
								}
							}
						}
						.contentShape(Rectangle())
						.onTapGesture {
							selectedSubject = subject
					 }
					}
				} header: {
					VStack {
						Text(order.catchline)
							.font(.system(size: 30, weight: .bold))
					}
				}
			}
		}
		.listStyle(.plain)
		.listSectionSpacing(20)
//		List(hansard.orders.filter { !$0.subjects.isEmpty }) { order in
//			ForEach(hansard.orders) { order in

//			}
//		}
	}
}

struct SittingSpeakerView: View {
	let name: String
	let party: Party
	init(member: ParliamentMember) {
		self.name = member.name
		self.party = member.party
	}
	init(name: String, party: Party) {
		self.name = name
		self.party = party
	}
	var body: some View {
		HStack {
			Text(verbatim: name)
				.font(.system(size: 12, weight: .light, design: .rounded))
			if let image = party.image {
				Image(uiImage: image)
					.resizable()
					.frame(width: 12, height: 12)
					.padding(2)
					.background(.white)
			}
		}
		.padding(0)
	}
}
