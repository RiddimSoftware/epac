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
					NavigationLink(destination: ExpendituresView()) {
						Label(NSLocalizedString("Expenditures", comment: ""), systemImage: "dollarsign.circle.fill")
					}
					NavigationLink(destination: PetitionsView()) {
						Label(NSLocalizedString("petitions.navTitle", comment: ""), systemImage: "person.wave.2.fill")
					}
					NavigationLink(destination: TopicsView()) {
						Label(NSLocalizedString("topics.navTitle", comment: ""), systemImage: "tag.fill")
					}
				}
			}
			.listStyle(.insetGrouped)
			.navigationTitle(NSLocalizedString("accountability.navTitle", comment: ""))
			.navigationBarTitleDisplayMode(.large)
		}
	}
}
