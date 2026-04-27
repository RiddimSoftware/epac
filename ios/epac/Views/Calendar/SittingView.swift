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

	@State private var coordinator = MemberDownloadCoordinator()
	@State private var viewModel = SittingViewModel()

	var body: some View {
		let pairs = viewModel.visibleOrderSubjects(from: hansard)
		Group {
			if pairs.isEmpty && !viewModel.searchText.isEmpty {
				ContentUnavailableView.search(text: viewModel.searchText)
			} else {
				List {
					ForEach(pairs, id: \.order.hansardID) { (order, subjects) in
						Section {
							ForEach(subjects) { subject in
								VStack(alignment: .leading, spacing: 8) {
									Text(subject.title)
										.font(.headline)
										.foregroundColor(.primary)

									HStack {
										Spacer()
										VStack(alignment: .trailing, spacing: 4) {
											ForEach(coordinator.speakers(for: subject, from: members, fetch: fetch)) { member in
												SittingSpeakerView(member: member)
											}
										}
									}
								}
								.padding(.vertical, 4)
								.contentShape(Rectangle())
								.accessibilityElement(children: .ignore)
								.accessibilityLabel(subject.title)
								.accessibilityHint("Open debate")
								.accessibilityAddTraits(.isButton)
								.onTapGesture {
									selectedSubject = subject
								}
							}
						} header: {
							Text(order.catchline)
								.font(.title2)
								.fontWeight(.black)
								.textCase(.uppercase)
								.foregroundColor(.secondary)
								.padding(.top, 20)
								.padding(.bottom, 8)
						}
					}
				}
				.listStyle(.plain)
			}
		}
		.searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search debates")
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

		HStack(spacing: 6) {

			Text(verbatim: name)

				.font(.system(.footnote, design: .rounded).weight(.medium))

				.foregroundColor(.secondary)

			if let image = party.image {

				Image(uiImage: image)

					.resizable()

					.scaledToFit()

					.frame(width: 16, height: 16)

					.padding(2)

					.background(Circle().fill(Color.white).shadow(radius: 1))

			}

		}

	}

}


