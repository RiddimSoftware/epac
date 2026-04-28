//
//  TransportationSafetyView.swift
//  epac
//

import SwiftUI

struct TransportationSafetyView: View {
    private var snapshot: TransportSafetySnapshot? {
        TransportSafetyStatisticsDatabase.snapshot()
    }

    var body: some View {
        List {
            if let snapshot {
                nationalSummary(snapshot)
                modeSection(title: "Air", systemImage: "airplane", mode: "air")
                modeSection(title: "Rail", systemImage: "tram.fill", mode: "rail")
                modeSection(title: "Marine", systemImage: "ferry.fill", mode: "marine")
                roadSection(snapshot)
                Section {
                    DataSourceBadge(source: .transportSafety())
                } footer: {
                    Text(snapshot.source.note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView(
                    "Transport safety data unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The bundled Transport Canada and TSB snapshot could not be loaded.")
                )
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Transport Safety")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func nationalSummary(_ snapshot: TransportSafetySnapshot) -> some View {
        Section {
            if let air = TransportSafetyStatisticsDatabase.latestModeYear("air"),
               let rail = TransportSafetyStatisticsDatabase.latestModeYear("rail"),
               let marine = TransportSafetyStatisticsDatabase.latestModeYear("marine") {
                LabeledContent("TSB occurrences \(air.year)") {
                    Text((air.occurrences + rail.occurrences + marine.occurrences).formatted())
                        .monospacedDigit()
                }
                LabeledContent("TSB fatalities \(air.year)") {
                    Text((air.fatalities + rail.fatalities + marine.fatalities).formatted())
                        .monospacedDigit()
                }
            }
            if let road = TransportSafetyStatisticsDatabase.latestRoadNational() {
                LabeledContent("Road fatalities \(road.year)") {
                    Text(road.fatalities.formatted())
                        .monospacedDigit()
                }
                LabeledContent("Serious road injuries") {
                    Text(road.seriousInjuries.formatted())
                        .monospacedDigit()
                }
            }
        } header: {
            Text("National Snapshot")
        }
    }

    @ViewBuilder
    private func modeSection(title: String, systemImage: String, mode: String) -> some View {
        if let record = TransportSafetyStatisticsDatabase.latestModeYear(mode) {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .foregroundStyle(.blue)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(record.year) \(title.lowercased()) occurrences")
                            .font(.subheadline.weight(.semibold))
                        Text("\(record.accidents.formatted()) accidents · \(record.incidents.formatted()) incidents")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(record.fatalities.formatted())
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .accessibilityLabel("\(record.fatalities) fatalities")
                }
                Link("Open TSB annual summary", destination: record.sourceURL)
                    .font(.caption2)
            } header: {
                Text(title)
            }
        }
    }

    private func roadSection(_ snapshot: TransportSafetySnapshot) -> some View {
        Section {
            ForEach(snapshot.road.provinces.sorted { $0.province < $1.province }) { province in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(province.province)
                            .font(.subheadline)
                        Text("Fatalities per 100k population")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(province.fatalitiesPer100k.formatted(.number.precision(.fractionLength(1))))
                        .font(.subheadline.monospacedDigit())
                }
            }
        } header: {
            Text("Road Safety by Province")
        } footer: {
            if let road = TransportSafetyStatisticsDatabase.latestRoadNational() {
                Text("Reference year: \(road.year). Rates use Transport Canada National Collision Database casualty tables.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
