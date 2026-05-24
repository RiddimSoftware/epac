//
//  RidingStatisticsView.swift
//  epac
//

import Charts
import SwiftData
import SwiftUI

// Shows socioeconomic statistics for a federal electoral district.
// Primary data source: Statistics Canada 2021 Census Profile for
// Federal Electoral Districts (Table 98-401-X2021014).
//
// The app does not cache census data locally (large dataset, infrequent
// updates). Instead it deep-links to the authoritative sources so users
// always see current data.
struct RidingStatisticsView: View {
	let member: ParliamentMember
	@Environment(\.openURL) private var openURL

	private enum Layout {
		static let rowSpacing: CGFloat = 12
		static let inlineRowSpacing: CGFloat = 8
		static let iconColumnWidth: CGFloat = 28
		static let textSpacing: CGFloat = 2
		static let compactTextSpacing: CGFloat = 3
		static let groupSpacing: CGFloat = 6
		static let compactVerticalPadding: CGFloat = 4
		static let rowVerticalPadding: CGFloat = 2
		static let cpiTrendMonthCount = 12
		static let chartRuleLineWidth: CGFloat = 1
		static let chartRuleDashLongSegment: CGFloat = 4
		static let chartRuleDashShortSegment: CGFloat = 3
		static var chartRuleDashPattern: [CGFloat] {
			[chartRuleDashLongSegment, chartRuleDashShortSegment]
		}
		static let cpiChartHeight: CGFloat = 140
		static let standardChartHeight: CGFloat = 120
		static let ociHighlightLimit = 2
		static let topMineralsLimit = 3
		static let thousandsMultiplier = 1_000.0
		static let million = 1_000_000.0
		static let billion = 1_000_000_000.0
	}

	private static let statcanBaseURL = "https://www12.statcan.gc.ca/census-recensement/2021/dp-pd/prof"
	private static let cmhcBaseURL    = "https://www.cmhc-schl.gc.ca"
	// IRCC canonical pages (verified 2026-04-28). The previous Levels-Plan and
	// Annual-Report paths under /services/ and the singular /annual-report-…
	// slug both 404 on canada.ca; the corporate-initiatives and plural-form
	// pages are the live canonical destinations linked from canada.ca itself.
	private static let irccLevelsPlanURL = URL(string: "https://www.canada.ca/en/immigration-refugees-citizenship/corporate/mandate/corporate-initiatives/levels.html")!
	private static let irccAdmissionsDatasetURL = URL(string: "https://open.canada.ca/data/en/dataset/f7e5498e-0ad8-4417-85c9-9b8aff9b9eda")!
	private static let irccAnnualReportURL = URL(string: "https://www.canada.ca/en/immigration-refugees-citizenship/corporate/publications-manuals/annual-reports-parliament-immigration.html")!
	// Housing, Infrastructure and Communities Canada canonical URLs (verified 2026-04-28).
	// The department was renamed and old `infrastructure.gc.ca` paths redirect through to
	// `housing-infrastructure.canada.ca`; use the destination directly to avoid the redirect.
	private static let infrastructureProjectMapURL = URL(string: "https://housing-infrastructure.canada.ca/gmap-gcarte/index-eng.html")!
	private static let infrastructureDatasetURL = URL(string: "https://open.canada.ca/data/en/dataset/beee0771-dab9-4be8-9b80-f8e8b3fdfd9d")!
	private static let infrastructurePortfolioURL = URL(string: "https://housing-infrastructure.canada.ca/plan/about-invest-apropos-eng.html")!
	private static let nhsStrategyOverviewURL = URL(string: "https://www.cmhc-schl.gc.ca/nhs/guidepage-strategy")!
	private static let nhsLatestProgressReportURL = URL(string: "https://assets.cmhc-schl.gc.ca/sites/place-to-call-home/pdfs/progress/nhs-progress-quarterly-report-q1-2024-en.pdf")!

	private static let ecccNIROverviewURL = URL(string: "https://www.canada.ca/en/environment-climate-change/services/climate-change/greenhouse-gas-emissions/inventory.html")!
	private static let ecccNIRDatasetURL = URL(string: "https://open.canada.ca/data/en/dataset/779c7bcf-4982-47eb-af1b-a33618a05e5b")!
	private static let ecccProvincialURL = URL(string: "https://www.canada.ca/en/environment-climate-change/services/environmental-indicators/greenhouse-gas-emissions.html")!

	private let statCategories: [(label: String, icon: String, color: Color)] = [
		("Population & Age", "person.2.fill", .blue),
		("Income & Employment", "banknote.fill", .green),
		("Housing", "house.fill", .orange),
		("Education", "graduationcap.fill", .purple),
		("Immigration & Diversity", "globe", .teal)
	]

	var body: some View {
		List {
			Section {
				ridingContextCard
			}

			employmentInsuranceSection
			consumerPriceIndexSection
			studentFinanceSection
			correctionsSection

			Section("2021 Census Data") {
				statCanSearchRow
				ForEach(statCategories, id: \.label) { cat in
					Button {
						openURL(statCanURL(topic: cat.label))
					} label: {
						HStack(spacing: Layout.rowSpacing) {
							Image(systemName: cat.icon)
								.foregroundStyle(cat.color)
								.frame(width: Layout.iconColumnWidth)
								.accessibilityHidden(true)
							Text(cat.label)
								.font(.subheadline)
								.foregroundStyle(.primary)
							Spacer()
							Image(systemName: "arrow.up.right.square")
								.font(.caption)
								.foregroundStyle(.tertiary)
						}
					}
				}
			}

			Section {
				NavigationLink(destination: NHSTrackerView()) {
					HStack(spacing: Layout.rowSpacing) {
						Image(systemName: "house.lodge.fill")
							.foregroundStyle(.orange)
							.frame(width: Layout.iconColumnWidth)
							.accessibilityHidden(true)
						VStack(alignment: .leading, spacing: Layout.textSpacing) {
							Text("NHS Housing Tracker")
								.font(.subheadline)
								.foregroundStyle(.primary)
							Text("Federal targets vs. units delivered under the National Housing Strategy")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
					}
				}
				cmhcRow
				nhsStrategyOverviewRow
				nhsProgressReportRow
			} header: {
				Text("Housing Market")
			} footer: {
				Text("Source: CMHC. Market data is published quarterly; the National Housing Strategy progress report is published quarterly with annual cumulative totals against the 10-year, ~$115B federal commitment.")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}

			immigrationSection

			infrastructureSection

			transportationSafetySection

			emissionsSection

			naturalResourcesSection

			healthSection

			cppOasSection
			veteransAffairsSection

			Section {
				VStack(alignment: .leading, spacing: Layout.groupSpacing) {
					Text("About this data")
						.font(.caption.bold())
					Text("Statistics Canada releases riding-level census profiles after each census (most recent: 2021). Data covers population, age, household income, housing costs, education, and immigration. CMHC publishes housing market data by metropolitan area.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.padding(.vertical, Layout.compactVerticalPadding)
			}
		}
		.listStyle(.insetGrouped)
		.navigationTitle("Riding Statistics")
		.navigationBarTitleDisplayMode(.inline)
	}

	// MARK: - Sub-views

	private var ridingContextCard: some View {
		HStack(spacing: Layout.rowSpacing) {
			Circle()
				.fill(Color.party(member.party))
				.frame(width: Layout.rowSpacing, height: Layout.rowSpacing)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: Layout.compactTextSpacing) {
				Text(member.riding)
					.font(.headline)
				Text("\(member.province.rawValue) · \(member.party.fullName)")
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
		}
		.padding(.vertical, Layout.compactVerticalPadding)
	}

	private var statCanSearchRow: some View {
		Button {
			openURL(statCanSearchURL())
		} label: {
			HStack(spacing: Layout.rowSpacing) {
				Image(systemName: "magnifyingglass.circle.fill")
					.foregroundStyle(.blue)
					.frame(width: Layout.iconColumnWidth)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: Layout.textSpacing) {
					Text("Find \(member.riding) on Statistics Canada")
						.font(.subheadline)
						.foregroundStyle(.primary)
					Text("2021 Census Community Profiles · Federal Electoral Districts")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Image(systemName: "arrow.up.right.square")
					.font(.caption)
					.foregroundStyle(.tertiary)
			}
		}
	}

	@ViewBuilder
	private var employmentInsuranceSection: some View {
		if let ei = EmploymentInsuranceStatisticsDatabase.statistic(for: member.province.shortCode) {
			Section {
				LabeledContent("Regular beneficiaries") {
					Text(ei.beneficiaries.formatted())
						.monospacedDigit()
				}
				LabeledContent("Claims received") {
					Text(ei.claimsReceived.formatted())
						.monospacedDigit()
				}
				LabeledContent("Average weekly benefit") {
					Text(ei.averageWeeklyBenefit.formatted(.currency(code: "CAD").precision(.fractionLength(0))))
						.monospacedDigit()
				}
				if let change = ei.claimsYearOverYearChangePercent {
					LabeledContent("Claims vs. last year") {
						Text(yearOverYearLabel(change))
							.monospacedDigit()
					}
				}
				Link(EmploymentInsuranceStatisticsDatabase.snapshot()?.source.title
					?? EmploymentInsuranceStatisticsDatabase.fallbackSource.title,
				     destination: EmploymentInsuranceStatisticsDatabase.snapshot()?.source.url
					?? EmploymentInsuranceStatisticsDatabase.fallbackSource.url)
					.font(.caption2)
			} header: {
				Text("Employment Insurance")
			} footer: {
				Text("Reference month: \(EmploymentInsuranceStatisticsDatabase.monthLabel(ei.referenceMonth)). EI monthly data normally lags by about two months. Average weekly benefit is calculated from benefit payments divided by benefit weeks.")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
	}

	@ViewBuilder
	private var consumerPriceIndexSection: some View {
		if let cpi = ConsumerPriceIndexStatisticsDatabase.statistic(for: member.province.shortCode) {
			Section {
				LabeledContent("Inflation") {
					Text(yearOverYearLabel(cpi.allItemsYearOverYearPercent))
						.monospacedDigit()
				}
				LabeledContent("Food") {
					Text(yearOverYearLabel(cpi.foodYearOverYearPercent))
						.monospacedDigit()
				}
				LabeledContent("National") {
					Text(yearOverYearLabel(cpi.nationalAllItemsYearOverYearPercent))
						.monospacedDigit()
				}
				cpiTrendChart(cpi)
				Link(cpiSourceTitle(cpi), destination: ConsumerPriceIndexStatisticsDatabase.snapshot()?.source.url
					?? ConsumerPriceIndexStatisticsDatabase.fallbackSource.url)
					.font(.caption2)
			} header: {
				Text("Consumer Price Index")
			} footer: {
				Text("Reference month: \(ConsumerPriceIndexStatisticsDatabase.monthLabel(cpi.referenceMonth)). CPI is published monthly and normally lags the reference month by about three weeks.")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
	}

	private func cpiTrendChart(_ cpi: ConsumerPriceIndexStatistic) -> some View {
		Chart {
			ForEach(Array(cpi.months.suffix(Layout.cpiTrendMonthCount))) { month in
				if let date = ConsumerPriceIndexStatisticsDatabase.date(for: month.refDate) {
					LineMark(
						x: .value("Month", date),
						y: .value("Inflation", month.allItemsYearOverYearPercent)
					)
					.foregroundStyle(.blue)
					PointMark(
						x: .value("Month", date),
						y: .value("Inflation", month.allItemsYearOverYearPercent)
					)
					.foregroundStyle(.blue)
				}
			}
			RuleMark(y: .value("National", cpi.nationalAllItemsYearOverYearPercent))
				.foregroundStyle(.secondary)
				.lineStyle(StrokeStyle(lineWidth: Layout.chartRuleLineWidth, dash: Layout.chartRuleDashPattern))
		}
		.frame(height: Layout.cpiChartHeight)
		.chartYAxis {
			AxisMarks(position: .leading) { value in
				AxisGridLine()
				AxisTick()
				AxisValueLabel {
					if let percent = value.as(Double.self) {
						Text("\(percent.formatted(.number.precision(.fractionLength(1))))%")
					}
				}
			}
		}
		.accessibilityLabel("Twelve month all-items inflation trend")
	}

	@ViewBuilder
	private var studentFinanceSection: some View {
		if let finance = StudentFinancialAssistanceStatisticsDatabase.statistic(for: member.province.shortCode),
		   let tuition = finance.latestTuitionYear {
			let latestCSFA = finance.latestCSFAYear
			let cpi = ConsumerPriceIndexStatisticsDatabase.statistic(for: member.province.shortCode)
			Section {
				LabeledContent("Average undergraduate tuition") {
					Text(tuition.averageUndergraduateTuition.formatted(.currency(code: "CAD").precision(.fractionLength(0))))
						.monospacedDigit()
				}
				if let tuitionChange = tuition.yearOverYearChangePercent {
					LabeledContent("Tuition vs. last year") {
						Text(yearOverYearLabel(tuitionChange))
							.monospacedDigit()
					}
					if let inflation = cpi?.allItemsYearOverYearPercent {
						LabeledContent("Tuition vs. CPI") {
							Text(yearOverYearLabel(tuitionChange - inflation))
								.monospacedDigit()
						}
					}
				}
				if let latestCSFA {
					LabeledContent("CSL recipients") {
						Text(latestCSFA.loanRecipients.formatted())
							.monospacedDigit()
					}
					LabeledContent("Average federal loan") {
						Text(latestCSFA.averageLoanAmount.formatted(.currency(code: "CAD").precision(.fractionLength(0))))
							.monospacedDigit()
					}
					if let rapRecipients = latestCSFA.rapRecipients {
						LabeledContent("RAP recipients") {
							Text(rapRecipients.formatted())
								.monospacedDigit()
						}
					}
				} else if !finance.csfaParticipating {
					Text("This jurisdiction receives alternative CSFA payments instead of participating directly in federal loan delivery.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				studentTuitionChart(finance)
				DataSourceBadge(source: .studentFinance())
				ForEach(StudentFinancialAssistanceStatisticsDatabase.sources(), id: \.url) { source in
					Link(source.title, destination: source.url)
						.font(.caption2)
				}
			} header: {
				Text("Student Financial Assistance")
			} footer: {
				let tuitionYear = StudentFinancialAssistanceStatisticsDatabase.academicYearLabel(tuition.academicYear)
				let cpiMonth = cpi.map { ConsumerPriceIndexStatisticsDatabase.monthLabel($0.referenceMonth) } ?? "latest CPI"
				Text("Tuition is Statistics Canada table 37-10-0120-01 for \(tuitionYear). CPI comparison uses \(cpiMonth). CSFA loan and RAP counts are federal program statistics for participating provinces and Yukon.")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
	}

	private func studentTuitionChart(_ finance: StudentFinanceProvinceStatistic) -> some View {
		Chart {
			ForEach(finance.tuitionYears) { year in
				BarMark(
					x: .value("Academic year", StudentFinancialAssistanceStatisticsDatabase.academicYearLabel(year.academicYear)),
					y: .value("Tuition", year.averageUndergraduateTuition)
				)
				.foregroundStyle(.purple)
			}
		}
		.frame(height: Layout.standardChartHeight)
		.chartYAxis {
			AxisMarks(position: .leading) { value in
				AxisGridLine()
				AxisTick()
				AxisValueLabel {
					if let amount = value.as(Int.self) {
						Text(amount.formatted(.currency(code: "CAD").precision(.fractionLength(0))))
					}
				}
			}
		}
		.accessibilityLabel("Five year undergraduate tuition trend")
	}

	@ViewBuilder
	private var correctionsSection: some View {
		if let snapshot = CorrectionsStatisticsDatabase.snapshot(),
		   let latest = snapshot.latestAnnualStatistic {
			Section {
				LabeledContent("Federal custody") {
					Text(latest.totalInCustody.formatted())
						.monospacedDigit()
				}
				LabeledContent("Indigenous in custody") {
					Text(percentLabel(latest.indigenousInCustodyPercent))
						.monospacedDigit()
				}
				LabeledContent("Canada population share") {
					Text(percentLabel(snapshot.indigenousPopulationShare.percentOfCanada))
						.monospacedDigit()
				}
				LabeledContent("5-year recidivism rate") {
					Text(percentLabel(latest.recidivismRatePercent))
						.monospacedDigit()
				}
				LabeledContent("Care/custody cost per inmate") {
					Text(latest.costPerInmate.formatted(.currency(code: "CAD").precision(.fractionLength(0))))
						.monospacedDigit()
				}
				correctionsCostChart(snapshot)
				ForEach(snapshot.ociHighlights.prefix(Layout.ociHighlightLimit)) { highlight in
					VStack(alignment: .leading, spacing: Layout.compactTextSpacing) {
						Text(highlight.title)
							.font(.caption.bold())
						Text(highlight.summary)
							.font(.caption2)
							.foregroundStyle(.secondary)
					}
				}
				DataSourceBadge(source: .corrections())
				ForEach(CorrectionsStatisticsDatabase.sources(), id: \.url) { source in
					Link(source.title, destination: source.url)
						.font(.caption2)
				}
			} header: {
				Text("Federal Corrections")
			} footer: {
				Text("National federal corrections context for \(CorrectionsStatisticsDatabase.fiscalYearLabel(snapshot.referenceFiscalYear)). Cost per inmate is derived from CSC Care and Custody spending divided by the in-custody population. Indigenous population share uses the 2021 Census.")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
	}

	private func correctionsCostChart(_ snapshot: CorrectionsSnapshot) -> some View {
		Chart {
			ForEach(snapshot.annualStatistics) { year in
				LineMark(
					x: .value("Fiscal year", CorrectionsStatisticsDatabase.fiscalYearLabel(year.fiscalYear)),
					y: .value("Cost per inmate", year.costPerInmate)
				)
				.foregroundStyle(.red)
				PointMark(
					x: .value("Fiscal year", CorrectionsStatisticsDatabase.fiscalYearLabel(year.fiscalYear)),
					y: .value("Cost per inmate", year.costPerInmate)
				)
				.foregroundStyle(.red)
			}
		}
		.frame(height: Layout.standardChartHeight)
		.chartYAxis {
			AxisMarks(position: .leading) { value in
				AxisGridLine()
				AxisTick()
				AxisValueLabel {
					if let amount = value.as(Int.self) {
						Text(amount.formatted(.currency(code: "CAD").precision(.fractionLength(0))))
					}
				}
			}
		}
		.accessibilityLabel("Three year federal care and custody cost per inmate trend")
	}

	private var cmhcRow: some View {
		Button {
			openURL(cmhcURL())
		} label: {
			HStack(spacing: Layout.rowSpacing) {
				Image(systemName: "building.2.fill")
					.foregroundStyle(.orange)
					.frame(width: Layout.iconColumnWidth)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: Layout.textSpacing) {
					Text("CMHC Housing Data")
						.font(.subheadline)
						.foregroundStyle(.primary)
					Text("Rental vacancy rates, average rents, and starts for \(member.province.rawValue)")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Image(systemName: "arrow.up.right.square")
					.font(.caption)
					.foregroundStyle(.tertiary)
			}
		}
	}

	private var nhsStrategyOverviewRow: some View {
		Button {
			openURL(Self.nhsStrategyOverviewURL)
		} label: {
			HStack(spacing: Layout.rowSpacing) {
				Image(systemName: "house.lodge.fill")
					.foregroundStyle(.orange)
					.frame(width: Layout.iconColumnWidth)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: Layout.textSpacing) {
					Text("National Housing Strategy")
						.font(.subheadline)
						.foregroundStyle(.primary)
					Text("Federal 10-year housing commitment, programs, and targets")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Image(systemName: "arrow.up.right.square")
					.font(.caption)
					.foregroundStyle(.tertiary)
			}
		}
	}

	private var nhsProgressReportRow: some View {
		Button {
			openURL(Self.nhsLatestProgressReportURL)
		} label: {
			HStack(spacing: Layout.rowSpacing) {
				Image(systemName: "chart.bar.doc.horizontal.fill")
					.foregroundStyle(.orange)
					.frame(width: Layout.iconColumnWidth)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: Layout.textSpacing) {
					Text("NHS Progress Report")
						.font(.subheadline)
						.foregroundStyle(.primary)
					Text("Federal targets vs. units delivered (PDF)")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Image(systemName: "arrow.up.right.square")
					.font(.caption)
					.foregroundStyle(.tertiary)
			}
		}
	}

	// MARK: - Immigration section

	private var immigrationSection: some View {
		Section {
			immigrationLevelsPlanRow
			immigrationAdmissionsRow
			immigrationAnnualReportRow
		} header: {
			Text("Immigration")
		} footer: {
			Text("Source: Immigration, Refugees and Citizenship Canada (IRCC). Annual admissions data is published with a ~6-month lag after year-end; the Levels Plan is tabled in Parliament each fall for the following 3-year window.")
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
	}

	private var immigrationLevelsPlanRow: some View {
		Button {
			openURL(Self.irccLevelsPlanURL)
		} label: {
			HStack(spacing: Layout.rowSpacing) {
				Image(systemName: "target")
					.foregroundStyle(.indigo)
					.frame(width: Layout.iconColumnWidth)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: Layout.textSpacing) {
					Text("Immigration Levels Plan")
						.font(.subheadline)
						.foregroundStyle(.primary)
					Text("Federal admission targets by category, tabled annually in Parliament")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Image(systemName: "arrow.up.right.square")
					.font(.caption)
					.foregroundStyle(.tertiary)
			}
		}
	}

	private var immigrationAdmissionsRow: some View {
		Button {
			openURL(Self.irccAdmissionsDatasetURL)
		} label: {
			HStack(spacing: Layout.rowSpacing) {
				Image(systemName: "airplane.arrival")
					.foregroundStyle(.indigo)
					.frame(width: Layout.iconColumnWidth)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: Layout.textSpacing) {
					Text("Permanent Residents — Admissions")
						.font(.subheadline)
						.foregroundStyle(.primary)
					Text("Open data: monthly admissions by category and province")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Image(systemName: "arrow.up.right.square")
					.font(.caption)
					.foregroundStyle(.tertiary)
			}
		}
	}

	private var immigrationAnnualReportRow: some View {
		Button {
			openURL(Self.irccAnnualReportURL)
		} label: {
			HStack(spacing: Layout.rowSpacing) {
				Image(systemName: "doc.text.fill")
					.foregroundStyle(.indigo)
					.frame(width: Layout.iconColumnWidth)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: Layout.textSpacing) {
					Text("Annual Report to Parliament")
						.font(.subheadline)
						.foregroundStyle(.primary)
					Text("IRCC reports each year on admissions vs. Levels Plan targets")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Image(systemName: "arrow.up.right.square")
					.font(.caption)
					.foregroundStyle(.tertiary)
			}
		}
	}

	// MARK: - Emissions section (Phase 1: deep-links only)
	//
	// Phase 2 will ingest the NIR CSV and render a per-province sector chart
	// inline. Tracked under the EPAC-174 follow-up; for now the section
	// surfaces the three authoritative ECCC entry points so users browsing
	// climate-tagged debates can pull the underlying data themselves.

	private var emissionsSection: some View {
		Section {
			emissionsInventoryRow
			emissionsDatasetRow
			emissionsProvincialRow
		} header: {
			Text("Climate & Emissions")
		} footer: {
			Text("Source: Environment and Climate Change Canada, National Inventory Report. Annual greenhouse-gas emissions in megatonnes of CO₂ equivalent, by province and sector. The NIR is published each spring with a ~15-month lag after the reference year.")
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
	}

	private var emissionsInventoryRow: some View {
		Button {
			openURL(Self.ecccNIROverviewURL)
		} label: {
			HStack(spacing: Layout.rowSpacing) {
				Image(systemName: "leaf.fill")
					.foregroundStyle(.green)
					.frame(width: Layout.iconColumnWidth)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: Layout.textSpacing) {
					Text("National Inventory Report")
						.font(.subheadline)
						.foregroundStyle(.primary)
					Text("ECCC's annual greenhouse-gas inventory by province and sector")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Image(systemName: "arrow.up.right.square")
					.font(.caption)
					.foregroundStyle(.tertiary)
			}
		}
	}

	private var emissionsDatasetRow: some View {
		Button {
			openURL(Self.ecccNIRDatasetURL)
		} label: {
			HStack(spacing: Layout.rowSpacing) {
				Image(systemName: "tablecells")
					.foregroundStyle(.green)
					.frame(width: Layout.iconColumnWidth)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: Layout.textSpacing) {
					Text("NIR Dataset (Open Data)")
						.font(.subheadline)
						.foregroundStyle(.primary)
					Text("Open data: emissions back to 1990, by gas, sector, and province")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Image(systemName: "arrow.up.right.square")
					.font(.caption)
					.foregroundStyle(.tertiary)
			}
		}
	}

	private var emissionsProvincialRow: some View {
		Button {
			openURL(Self.ecccProvincialURL)
		} label: {
			HStack(spacing: Layout.rowSpacing) {
				Image(systemName: "chart.bar.xaxis")
					.foregroundStyle(.green)
					.frame(width: Layout.iconColumnWidth)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: Layout.textSpacing) {
					Text("Provincial Emissions Indicator")
						.font(.subheadline)
						.foregroundStyle(.primary)
					Text("Government of Canada visual summary by province")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Image(systemName: "arrow.up.right.square")
					.font(.caption)
					.foregroundStyle(.tertiary)
			}
		}
	}

	// MARK: - Natural resources section

	@ViewBuilder
	private var naturalResourcesSection: some View {
		if let resources = NaturalResourcesStatisticsDatabase.statistic(for: member.province.shortCode) {
			Section {
				if resources.showMining {
					if let latestMining = resources.latestMiningYear {
						LabeledContent("Mineral shipments (\(resourceYearLabel(latestMining.year, provisional: latestMining.isProvisional)))") {
							Text(mineralShipmentLabel(latestMining))
								.monospacedDigit()
						}
					}
					if !resources.topMinerals.isEmpty {
						VStack(alignment: .leading, spacing: Layout.groupSpacing) {
							Text("Top visible minerals")
								.font(.caption.bold())
							ForEach(Array(resources.topMinerals.prefix(Layout.topMineralsLimit))) { mineral in
								HStack(alignment: .firstTextBaseline, spacing: Layout.inlineRowSpacing) {
									Text(mineral.commodity)
										.font(.caption)
									Spacer()
									Text(mineralValueLabel(mineral))
										.font(.caption.monospacedDigit())
										.foregroundStyle(.secondary)
										.lineLimit(1)
								}
							}
						}
					}
					if let note = resources.resourceNote {
						Text(note)
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}

				if resources.showForestry, let latestForestry = resources.latestForestryYear {
					LabeledContent("Harvest volume (\(latestForestry.year))") {
						Text(volumeLabel(latestForestry.harvestVolumeCubicMetres))
							.monospacedDigit()
					}
					if let revenue = latestForestry.crownTimberRevenueDollars {
						LabeledContent("Crown timber revenue (\(latestForestry.year))") {
							Text(compactDollars(Double(revenue)))
								.monospacedDigit()
						}
					}
				}

				Link(NaturalResourcesStatisticsDatabase.snapshot()?.source.title
					?? NaturalResourcesStatisticsDatabase.fallbackSource.title,
				     destination: NaturalResourcesStatisticsDatabase.snapshot()?.source.url
					?? NaturalResourcesStatisticsDatabase.fallbackSource.url)
					.font(.caption2)
				DataSourceBadge(source: .naturalResources())
			} header: {
				Text("Natural Resources")
			} footer: {
				Text("Shown only for provinces where the source tables are materially relevant: forestry for BC, MB, ON, QC, and NB; mining for ON, QC, BC, SK, MB, and NL. Mineral shipment values are in current dollars and may be suppressed by NRCan as confidential; forestry value is Crown timber revenue, not total forest-sector output.")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
	}

	// MARK: - Infrastructure section

	private var infrastructureSection: some View {
		Section {
			infrastructureProjectMapRow
			infrastructureDatasetRow
			infrastructurePortfolioRow
		} header: {
			Text("Infrastructure")
		} footer: {
			Text("Source: Infrastructure Canada. The Project Map shows federally funded infrastructure projects by location with funding amount, program, and status. Project data is updated quarterly.")
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
	}

	private var infrastructureProjectMapRow: some View {
		Button {
			openURL(Self.infrastructureProjectMapURL)
		} label: {
			HStack(spacing: Layout.rowSpacing) {
				Image(systemName: "map.fill")
					.foregroundStyle(.brown)
					.frame(width: Layout.iconColumnWidth)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: Layout.textSpacing) {
					Text("Project Map")
						.font(.subheadline)
						.foregroundStyle(.primary)
					Text("Federally funded projects by location, with funding and status")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Image(systemName: "arrow.up.right.square")
					.font(.caption)
					.foregroundStyle(.tertiary)
			}
		}
	}

	private var infrastructureDatasetRow: some View {
		Button {
			openURL(Self.infrastructureDatasetURL)
		} label: {
			HStack(spacing: Layout.rowSpacing) {
				Image(systemName: "tablecells.fill")
					.foregroundStyle(.brown)
					.frame(width: Layout.iconColumnWidth)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: Layout.textSpacing) {
					Text("Investing in Canada Plan — Open Data")
						.font(.subheadline)
						.foregroundStyle(.primary)
					Text("Project-level CSV: name, program, federal amount, total cost, dates")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Image(systemName: "arrow.up.right.square")
					.font(.caption)
					.foregroundStyle(.tertiary)
			}
		}
	}

	private var infrastructurePortfolioRow: some View {
		Button {
			openURL(Self.infrastructurePortfolioURL)
		} label: {
			HStack(spacing: Layout.rowSpacing) {
				Image(systemName: "building.columns.fill")
					.foregroundStyle(.brown)
					.frame(width: Layout.iconColumnWidth)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: Layout.textSpacing) {
					Text("Federal Programs")
						.font(.subheadline)
						.foregroundStyle(.primary)
					Text("Housing Accelerator Fund, Canada Community-Building Fund, and other active programs")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Image(systemName: "arrow.up.right.square")
					.font(.caption)
					.foregroundStyle(.tertiary)
			}
		}
	}

	// MARK: - Transportation safety section

	@ViewBuilder
	private var transportationSafetySection: some View {
		if let road = TransportSafetyStatisticsDatabase.roadStatistic(for: member.province.shortCode) {
			Section {
				LabeledContent("Road fatalities") {
					Text(TransportSafetyStatisticsDatabase.rateLabel(road.fatalitiesPer100k, unit: "per 100k"))
						.monospacedDigit()
				}
				LabeledContent("Road injuries") {
					Text(TransportSafetyStatisticsDatabase.rateLabel(road.injuriesPer100k, unit: "per 100k"))
						.monospacedDigit()
				}
				LabeledContent("Fatalities by distance") {
					Text(TransportSafetyStatisticsDatabase.rateLabel(road.fatalitiesPerBillionVKT, unit: "per billion VKT"))
						.monospacedDigit()
				}
				NavigationLink(destination: TransportationSafetyView()) {
					Label("National transport safety", systemImage: "car.2.fill")
						.font(.subheadline)
				}
				DataSourceBadge(source: .transportSafety())
			} header: {
				Text("Transportation Safety")
			} footer: {
				Text("Reference year: \(road.referenceYear). Road casualty rates are provincial; air, rail, and marine occurrence counts are national TSB statistics.")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
	}

	// MARK: - Health section

	@ViewBuilder
	private var healthSection: some View {
		let waitTimes = CIHIWaitTimeDatabase.waitTimes(for: member.province.shortCode)
		if !waitTimes.isEmpty {
			Section {
				ForEach(waitTimes, id: \.procedure) { wt in
					HStack {
						Text(wt.procedure).font(.subheadline)
						Spacer()
						VStack(alignment: .trailing, spacing: Layout.textSpacing) {
							Text("\(Int(wt.medianWeeks))w median")
								.font(.caption.monospacedDigit())
							Text("\(Int(wt.p90Weeks))w (90th)")
								.font(.caption2).foregroundStyle(.secondary)
						}
					}
					.padding(.vertical, Layout.rowVerticalPadding)
				}
				Link(NSLocalizedString("cihi.viewSource", comment: ""), destination: CIHIWaitTimeDatabase.sourceURL)
					.font(.caption2)
			} header: {
				Text(String(format: NSLocalizedString("cihi.sectionTitle", comment: ""), CIHIWaitTimeDatabase.dataYear))
			} footer: {
				Text(CIHIWaitTimeDatabase.citation).font(.caption2).foregroundStyle(.secondary)
			}
		}
	}

	@ViewBuilder
	private var cppOasSection: some View {
		if let cpp = CPPOASStatisticsDatabase.statistic(for: member.province.shortCode),
		   let national = CPPOASStatisticsDatabase.national() {
			let cppShare = national.cppRetirementRecipients > 0
				? Double(cpp.cppRetirementRecipients ?? 0) / Double(national.cppRetirementRecipients)
				: 0.0
			let oasShare = national.oasPensionRecipients > 0
				? Double(cpp.oasPensionRecipients ?? 0) / Double(national.oasPensionRecipients)
				: 0.0
			Section {
				if let cppCount = cpp.cppRetirementRecipients {
					LabeledContent("CPP retirement recipients") {
						Text(cppCount.formatted())
							.monospacedDigit()
					}
					LabeledContent("Share of national CPP recipients") {
						Text(cppShare.formatted(.percent.precision(.fractionLength(1))))
							.monospacedDigit()
					}
				}
				if let oasCount = cpp.oasPensionRecipients {
					LabeledContent("OAS pension recipients") {
						Text(oasCount.formatted())
							.monospacedDigit()
					}
					LabeledContent("Share of national OAS recipients") {
						Text(oasShare.formatted(.percent.precision(.fractionLength(1))))
							.monospacedDigit()
					}
				}
				DataSourceBadge(source: .cppOas())
			} header: {
				Text("CPP & OAS Pensions")
			} footer: {
				let cppPeriod = cpp.cppReferencePeriod.map { CPPOASStatisticsDatabase.periodLabel($0) } ?? ""
				let oasPeriod = cpp.oasReferencePeriod.map { CPPOASStatisticsDatabase.periodLabel($0) } ?? ""
				Text("CPP data as of \(cppPeriod); OAS data as of \(oasPeriod). Recipient counts are from ESDC monthly Statistical Bulletins on open.canada.ca. Average benefit amounts are published nationally only.")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
	}

	@ViewBuilder
	private var veteransAffairsSection: some View {
		if let province = VeteransAffairsStatisticsDatabase.statistic(for: member.province.shortCode),
		   let national = VeteransAffairsStatisticsDatabase.nationalSummary(),
		   let latestAnnual = VeteransAffairsStatisticsDatabase.latestAnnual(),
		   let latestWait = latestAnnual.firstApplicationAverageWeeks {
			Section {
				LabeledContent("Veterans in province") {
					Text(province.censusVeterans.formatted())
						.monospacedDigit()
				}
				if let warService = province.estimatedWarServiceVeterans {
					LabeledContent("Estimated war-service Veterans") {
						Text(warService.formatted())
							.monospacedDigit()
					}
				}
				LabeledContent("National disability recipients") {
					Text(national.disabilityBenefitRecipients.formatted())
						.monospacedDigit()
				}
				LabeledContent("National applications backlog") {
					Text(national.backlogApplications.formatted())
						.monospacedDigit()
				}
				LabeledContent("Avg. first-app wait (\(latestAnnual.fiscalYear))") {
					Text("\(latestWait.formatted(.number.precision(.fractionLength(1)))) weeks")
						.monospacedDigit()
				}
				DataSourceBadge(source: .veteransAffairs())
			} header: {
				Text("Veterans Affairs")
			} footer: {
				Text("Provincial Veteran population is from the 2021 Census. Disability benefit recipients and backlog are national VAC figures as of \(VeteransAffairsStatisticsDatabase.dateLabel(national.referenceDate)); the first-application wait is the national \(latestAnnual.fiscalYear) result. VAC does not publish these processing results by province in the source tables.")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
	}

	// MARK: - URLs

	private func statCanSearchURL() -> URL {
		// Search by riding name in the FED community profiles
		var components = URLComponents(string: "\(Self.statcanBaseURL)/search-recherche/lst/page.cfm")!
		components.queryItems = [
			URLQueryItem(name: "Lang", value: "E"),
			URLQueryItem(name: "type", value: "0"),
			URLQueryItem(name: "SurveyID", value: "1178"),
			URLQueryItem(name: "keyword", value: member.riding)
		]
		return components.url ?? URL(string: Self.statcanBaseURL)!
	}

	private func statCanURL(topic: String) -> URL {
		// Topic-filtered view falls back to the search page since topic
		// codes are not stored locally — user can navigate from search.
		statCanSearchURL()
	}

	private func cmhcURL() -> URL {
		// CMHC housing market information centre, province-level
		return URL(string: "\(Self.cmhcBaseURL)/en/housing-observer-online")
		    ?? URL(string: Self.cmhcBaseURL)!
	}

	private func yearOverYearLabel(_ value: Double) -> String {
		if value > 0 {
			return "+\(value.formatted(.number.precision(.fractionLength(1))))%"
		}
		return "\(value.formatted(.number.precision(.fractionLength(1))))%"
	}

	private func percentLabel(_ value: Double) -> String {
		"\(value.formatted(.number.precision(.fractionLength(1))))%"
	}

	private func cpiSourceTitle(_ cpi: ConsumerPriceIndexStatistic) -> String {
		let title = ConsumerPriceIndexStatisticsDatabase.snapshot()?.source.title
			?? ConsumerPriceIndexStatisticsDatabase.fallbackSource.title
		return "\(title), \(ConsumerPriceIndexStatisticsDatabase.monthLabel(cpi.referenceMonth))"
	}

	private func resourceYearLabel(_ year: Int, provisional: Bool) -> String {
		provisional ? "\(year)p" : "\(year)"
	}

	private func mineralShipmentLabel(_ statistic: MineralYearStatistic) -> String {
		guard let value = statistic.shipmentValueThousands else {
			return statistic.isConfidential ? "Confidential" : "Not reported"
		}
		return compactDollars(Double(value) * Layout.thousandsMultiplier)
	}

	private func mineralValueLabel(_ mineral: MineralCommodityValue) -> String {
		guard let value = mineral.shipmentValueThousands else {
			return mineral.isConfidential ? "confidential" : "not reported"
		}
		return compactDollars(Double(value) * Layout.thousandsMultiplier)
	}

	private func volumeLabel(_ cubicMetres: Int) -> String {
		let value = Double(cubicMetres)
		if value >= Layout.million {
			return "\(formattedDecimal(value / Layout.million))M m³"
		}
		return "\(cubicMetres.formatted()) m³"
	}

	private func compactDollars(_ dollars: Double) -> String {
		let absValue = abs(dollars)
		if absValue >= Layout.billion {
			return "$\(formattedDecimal(dollars / Layout.billion))B"
		}
		if absValue >= Layout.million {
			return "$\(formattedDecimal(dollars / Layout.million))M"
		}
		return dollars.formatted(.currency(code: "CAD").precision(.fractionLength(0)))
	}

	private func formattedDecimal(_ value: Double) -> String {
		value.formatted(.number.precision(.fractionLength(1)))
	}
}
