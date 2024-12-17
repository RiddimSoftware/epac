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
	let hansard: Hansard
	@Binding var selectedSubject: SubjectOfBusiness?

	private func getMember(_ firstName: String, _ lastName: String) -> ParliamentMember? {
		return try? modelContext.fetch(FetchDescriptor<ParliamentMember>(predicate: #Predicate {
			$0.firstName == firstName && $0.lastName == lastName
		})).first
	}

	var body: some View {
		List {
			ForEach(hansard.orders.sorted(by: { $0.hansardID < $1.hansardID }).filter { !$0.subjects.isEmpty }) { order in
				Section {
					ForEach(order.subjects.sorted(by: { $0.hansardID < $1.hansardID }).filter { !$0.speeches.isEmpty }) { subject in
						HStack {
							Text(subject.title)
							Spacer()
							if let member = getMember(subject.speeches.first!.messages.first!.firstName, subject.speeches.first!.messages.first!.lastName) {
								if subject.speeches.count == 1 {
									SittingSpeakerView(member: member)
								} else {
									VStack(spacing: 5) {
										ForEach(Array(Set(subject.speeches.compactMap { getMember($0.messages.first!.firstName, $0.messages.first!.lastName) }))) { member in
											SittingSpeakerView(member: member)
										}
									}
								}
							}
						}
						.onTapGesture {
						 selectedSubject = subject
					 }
					}
				} header: {
					VStack {
						Text(order.catchline)
							.font(.system(size: 25, weight: .bold))
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
	let member: ParliamentMember
	var body: some View {
		HStack {
			Text(verbatim: member.name)
				.font(.system(size: 12, weight: .light, design: .rounded))
			if let image = member.party.image {
				Image(uiImage: image)
					.resizable()
					.frame(width: 12, height: 12)
			}
		}
		.padding(0)
	}
}
