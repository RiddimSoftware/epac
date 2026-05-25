//
//  GICAppointmentsView.swift
//  epac
//

import SwiftUI

private enum GICAppointmentsLayout {
	static let summarySpacing: CGFloat = 10
	static let compactTextSpacing = EpacSpacing.xxs
	static let summaryMetricSpacing: CGFloat = 12
	static let compactVerticalPadding = EpacSpacing.xs
	static let rowSpacing: CGFloat = 5
	static let rowHeaderSpacing: CGFloat = 6
	static let primaryLineLimit = 1
	static let secondaryLineLimit = 2
	static let detailSpacing = EpacSpacing.s
}

struct GICAppointmentsView: View {
	@Environment(\.openURL) private var openURL
	@State private var searchText = ""
	@State private var selectedOrganization: String?
	@State private var statusFilter: GICAppointmentStatusFilter = .current

	private let snapshot = GICAppointmentsDatabase.snapshot()

	private var organizations: [String] {
		GICAppointmentsDatabase.organizations()
	}

	private var appointments: [GICAppointment] {
		GICAppointmentsDatabase.filteredAppointments(
			searchText: searchText,
			organization: selectedOrganization,
			status: statusFilter
		)
	}

	var body: some View {
		ZStack(alignment: .bottomTrailing) {
			content
			DataSourceBadge(source: .gicAppointments())
				.padding()
		}
		.navigationTitle("GIC Appointments")
		.navigationBarTitleDisplayMode(.large)
		.searchable(
			text: $searchText,
			placement: .navigationBarDrawer(displayMode: .automatic),
			prompt: "Search appointees or organizations"
		)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				filterMenu
			}
		}
	}

	@ViewBuilder
	private var content: some View {
		if snapshot == nil {
			ContentUnavailableView {
				Label("Appointments Unavailable", systemImage: "exclamationmark.triangle")
			} description: {
				Text("The bundled appointments snapshot could not be loaded.")
			}
		} else if appointments.isEmpty {
			ContentUnavailableView {
				Label("No Appointments", systemImage: "person.crop.circle.badge.questionmark")
			} description: {
				Text("Try a different search or filter.")
			}
		} else {
			List {
				Section {
					summaryCard
				}

				Section {
					ForEach(appointments) { appointment in
						NavigationLink(destination: GICAppointmentDetailView(appointment: appointment)) {
							GICAppointmentRow(appointment: appointment)
						}
					}
				} header: {
					Text("\(appointments.count) Appointments")
				} footer: {
					Text("Snapshot includes the newest current appointments plus selected Crown corporation records for organization search coverage.")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}

				if let snapshot {
					Section("Sources") {
						Link(destination: snapshot.source.url) {
							Label("Federal Organizations registry", systemImage: "building.columns.fill")
						}
						Link(destination: snapshot.source.ordersInCouncilURL) {
							Label("Orders in Council database", systemImage: "doc.text.magnifyingglass")
						}
					}
				}
			}
			.listStyle(.insetGrouped)
		}
	}

	private var summaryCard: some View {
		VStack(alignment: .leading, spacing: GICAppointmentsLayout.summarySpacing) {
			HStack(alignment: .firstTextBaseline) {
				VStack(alignment: .leading, spacing: GICAppointmentsLayout.compactTextSpacing) {
					Text("Governor in Council appointments")
						.font(.headline)
					if let retrievedAt = snapshot?.retrievedAt {
						Text("Retrieved \(retrievedAt)")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
				Spacer()
				Text(statusFilter.title)
					.font(.caption.weight(.semibold))
					.foregroundStyle(.tint)
			}

			if let coverage = snapshot?.coverage {
				HStack(spacing: GICAppointmentsLayout.summaryMetricSpacing) {
					metricTile(value: "\(coverage.recordsBundled)", label: "bundled")
					metricTile(value: "\(coverage.profilesScraped)", label: "profiles")
					metricTile(value: "\(appointments.filter { $0.orderInCouncil != nil }.count)", label: "P.C. refs")
				}
			}
		}
		.padding(.vertical, GICAppointmentsLayout.compactVerticalPadding)
	}

	private func metricTile(value: String, label: String) -> some View {
		VStack(alignment: .leading, spacing: GICAppointmentsLayout.compactTextSpacing) {
			Text(value)
				.font(.subheadline.monospacedDigit().weight(.semibold))
			Text(label)
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private var filterMenu: some View {
		Menu {
			Picker("Status", selection: $statusFilter) {
				ForEach(GICAppointmentStatusFilter.allCases) { status in
					Text(status.title).tag(status)
				}
			}

			Divider()

			Button {
				selectedOrganization = nil
			} label: {
				Label("All Organizations", systemImage: selectedOrganization == nil ? "checkmark" : "")
			}

			ForEach(organizations, id: \.self) { organization in
				Button {
					selectedOrganization = organization
				} label: {
					Label(organization, systemImage: selectedOrganization == organization ? "checkmark" : "")
				}
			}
		} label: {
			Image(systemName: "line.3.horizontal.decrease.circle\(hasActiveFilter ? ".fill" : "")")
				.accessibilityLabel("Filter appointments")
		}
	}

	private var hasActiveFilter: Bool {
		selectedOrganization != nil || statusFilter != .current
	}
}

private struct GICAppointmentRow: View {
	let appointment: GICAppointment

	var body: some View {
		VStack(alignment: .leading, spacing: GICAppointmentsLayout.rowSpacing) {
			HStack(spacing: GICAppointmentsLayout.rowHeaderSpacing) {
				Text(appointment.currentAppointmentDate)
					.font(.caption.monospacedDigit().weight(.semibold))
					.foregroundStyle(.tint)
				if let pcNumber = appointment.orderInCouncil?.pcNumber {
					Text(pcNumber)
						.font(.caption2.monospacedDigit())
						.foregroundStyle(.secondary)
				}
				Spacer()
				Text(appointment.isCurrent() ? "Current" : "Past")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(appointment.isCurrent() ? .green : .secondary)
			}

			Text(appointment.displayName)
				.font(.subheadline.weight(.semibold))
				.lineLimit(GICAppointmentsLayout.primaryLineLimit)
			Text(appointment.position)
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(GICAppointmentsLayout.secondaryLineLimit)
			Text(appointment.organization)
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(GICAppointmentsLayout.primaryLineLimit)

			if let compensation = appointment.compensation {
				Text(compensation.displayValue)
					.font(.caption2.monospacedDigit())
					.foregroundStyle(.tertiary)
			}
		}
		.padding(.vertical, GICAppointmentsLayout.compactVerticalPadding)
		.accessibilityElement(children: .combine)
	}
}

struct GICAppointmentDetailView: View {
	@Environment(\.openURL) private var openURL
	let appointment: GICAppointment

	var body: some View {
		List {
			Section {
				VStack(alignment: .leading, spacing: GICAppointmentsLayout.detailSpacing) {
					Text(appointment.displayName)
						.font(.title3.weight(.semibold))
					Text(appointment.position)
						.font(.subheadline)
					Text(appointment.organization)
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
				.padding(.vertical, GICAppointmentsLayout.compactVerticalPadding)
			}

			Section("Appointment") {
				LabeledContent("Current appointment", value: appointment.currentAppointmentDate)
				if let expiryDate = appointment.expiryDate {
					LabeledContent("Expiry", value: expiryDate)
				}
				if let appointmentType = appointment.appointmentType {
					LabeledContent("Type", value: appointmentType)
				}
				if let tenure = appointment.tenure {
					LabeledContent("Tenure", value: tenure)
				}
				if let level = appointment.classificationLevel {
					LabeledContent("Level", value: level)
				}
				if !appointment.responsibleMinister.isEmpty {
					LabeledContent("Minister", value: appointment.responsibleMinister)
				}
			}

			if let compensation = appointment.compensation {
				Section("Compensation") {
					LabeledContent(compensation.label, value: compensation.displayValue)
					if let award = compensation.maximumPerformanceAward {
						LabeledContent("Max performance award", value: award)
					}
					Text("Salary and per-diem ranges are 2025-26 Privy Council Office ranges for Governor in Council appointees.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}

			if let order = appointment.orderInCouncil {
				Section {
					LabeledContent("P.C. number", value: order.pcNumber)
					LabeledContent("Date made", value: order.dateMade)
					if !order.department.isEmpty {
						LabeledContent("Department", value: order.department)
					}
					if !order.act.isEmpty {
						LabeledContent("Act", value: order.act)
					}
					if !order.registration.isEmpty {
						LabeledContent("Registration", value: order.registration)
					}
					Text(order.precis)
						.font(.body)
					Button {
						openURL(order.attachmentURL)
					} label: {
						Label("Open P.C. attachment", systemImage: "arrow.up.right.square")
					}
				} header: {
					Text("Order in Council")
				} footer: {
					Text("Orders in Council are the appointment reference used here. Registration shows N/A when the source database has no statutory registration number.")
						.font(.caption2)
				}
			}

			Section("Official Source") {
				Button {
					openURL(appointment.profileURL)
				} label: {
					Label("Federal Organizations profile", systemImage: "building.columns.fill")
				}
				if let salaryURL = GICAppointmentsDatabase.snapshot()?.source.salaryRangesURL {
					Button {
						openURL(salaryURL)
					} label: {
						Label("Salary ranges and performance pay", systemImage: "dollarsign.circle")
					}
				}
			}
		}
		.listStyle(.insetGrouped)
		.navigationTitle("Appointment")
		.navigationBarTitleDisplayMode(.inline)
	}
}
