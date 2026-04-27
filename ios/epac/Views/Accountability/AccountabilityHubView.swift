//
//  AccountabilityHubView.swift
//  epac
//
//  Created on 2026-04-27.
//

import SwiftUI

struct AccountabilityHubView: View {
	var body: some View {
		NavigationStack {
			List {
				Section {
					NavigationLink(destination: BillsView()) {
						Label(NSLocalizedString("bills.navTitle", comment: ""), systemImage: "doc.text.fill")
					}
					.accessibilityHint("Opens federal bill tracker")
					NavigationLink(destination: ExpendituresView()) {
						Label(NSLocalizedString("Expenditures", comment: ""), systemImage: "dollarsign.circle.fill")
					}
					.accessibilityHint("Opens MP quarterly expenditures")
					NavigationLink(destination: PetitionsView()) {
						Label(NSLocalizedString("petitions.navTitle", comment: ""), systemImage: "person.wave.2.fill")
					}
					.accessibilityHint("Opens House of Commons e-petitions")
					NavigationLink(destination: TopicsView()) {
						Label(NSLocalizedString("topics.navTitle", comment: ""), systemImage: "tag.fill")
					}
					.accessibilityHint("Opens parliamentary topic following")
					NavigationLink(destination: CommitteesView()) {
						Label(NSLocalizedString("committees.navTitle", comment: ""), systemImage: "person.3.fill")
					}
					.accessibilityHint("Opens standing committee transcripts")
					NavigationLink(destination: PoliticalDonationsView()) {
						Label(NSLocalizedString("accountability.donations", comment: ""), systemImage: "banknote.fill")
					}
					.accessibilityHint("Opens party and candidate donation information")
					NavigationLink(destination: FederalProjectCostView()) {
						Label(NSLocalizedString("accountability.projectCosts", comment: ""), systemImage: "chart.bar.doc.horizontal.fill")
					}
					.accessibilityHint("Opens federal project cost lifecycle view")
					NavigationLink(destination: GazetteView()) {
						Label(NSLocalizedString("gazette.navTitle", comment: ""), systemImage: "newspaper.fill")
					}
					.accessibilityHint("Opens Canada Gazette regulations and notices")
				}
			}
			.listStyle(.insetGrouped)
			.navigationTitle(NSLocalizedString("accountability.navTitle", comment: ""))
			.navigationBarTitleDisplayMode(.large)
		}
	}
}
