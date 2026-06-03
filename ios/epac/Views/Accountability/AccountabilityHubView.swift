//
//  AccountabilityHubView.swift
//  epac
//
//  Created on 2026-04-27.
//

import SwiftUI

struct AccountabilityHubView: View {
	@State private var selectedExpenditure: SummaryExpenditure?
	@Environment(NavigationRouter.self) private var router

	var body: some View {
		@Bindable var router = router

		NavigationStack {
			List {
				Section {
					NavigationLink(destination: BillsTabRoot(selectedBill: $router.selectedBill)) {
						Label(NSLocalizedString("bills.navTitle", comment: ""), systemImage: "doc.text.fill")
					}
					.accessibilityHint("Opens federal bill tracker")
					NavigationLink(destination: PromiseTrackerView()) {
						Label("Promise Tracker", systemImage: "checklist.checked")
					}
					.accessibilityHint("Opens campaign promise tracker")
					NavigationLink(destination: ReconciliationCallsView()) {
						Label("TRC Calls to Action", systemImage: "figure.stand.line.dotted.figure.stand")
					}
					.accessibilityHint("Opens Truth and Reconciliation Commission Calls to Action tracker")
					NavigationLink(destination: ExpendituresView(selection: $selectedExpenditure)) {
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
					NavigationLink(destination: NHSTrackerView()) {
						Label("NHS Housing Tracker", systemImage: "house.lodge.fill")
					}
					.accessibilityHint("Opens National Housing Strategy targets vs. units delivered tracker")
					NavigationLink(destination: FederalFinancesView()) {
						Label("Federal Finances", systemImage: "chart.line.uptrend.xyaxis")
					}
					.accessibilityHint("Opens federal Fiscal Monitor revenue and spending view")
					NavigationLink(destination: GazetteView()) {
						Label(NSLocalizedString("gazette.navTitle", comment: ""), systemImage: "newspaper.fill")
					}
					.accessibilityHint("Opens Canada Gazette regulations and notices")
					NavigationLink(destination: ContractsView()) {
						Label(NSLocalizedString("contracts.navTitle", comment: ""), systemImage: "building.columns.fill")
					}
					.accessibilityHint("Opens federal government contracts from proactive disclosure")
					NavigationLink(destination: GrantsView()) {
						Label("Grants & Contributions", systemImage: "dollarsign.arrow.circlepath")
					}
					.accessibilityHint("Opens federal grants and contributions from proactive disclosure")
					NavigationLink(destination: GICAppointmentsView()) {
						Label("GIC Appointments", systemImage: "person.crop.circle.badge.checkmark")
					}
					.accessibilityHint("Opens Governor in Council appointment tracker")
					NavigationLink(destination: CabinetLobbyingOverviewView()) {
						Label("Cabinet Lobbying", systemImage: "person.2.wave.2.fill")
					}
					.accessibilityHint("Opens cabinet minister lobbying overview")
					NavigationLink(destination: LobbyistOrganizationDirectoryView()) {
						Label("Lobbyist Organizations", systemImage: "building.2.fill")
					}
					.accessibilityHint("Opens OCL lobbyist organization directory")
				}
			}
			.listStyle(.insetGrouped)
			.navigationTitle(NSLocalizedString("accountability.navTitle", comment: ""))
			.navigationBarTitleDisplayMode(.large)
		}
	}
}
