import SwiftUI
import StoreKit

// MARK: — Data models (clip-local, no SwiftData)

struct ClipMP {
    let name: String
    let riding: String
    let party: String
}

struct ClipBill {
    let number: String
    let title: String
    let status: String
}

// MARK: — Lookup service (inline, no shared framework needed)

private func lookupMP(postalCode: String) async throws -> ClipMP {
    let normalized = postalCode.uppercased().filter { !$0.isWhitespace }
    guard normalized.range(of: "^[A-Z]\\d[A-Z]\\d[A-Z]\\d$", options: .regularExpression) != nil else {
        throw URLError(.badURL)
    }
    let url = URL(string: "https://represent.opennorth.ca/postcodes/\(normalized)/?sets=federal-electoral-districts")!
    let (data, _) = try await URLSession.shared.data(from: url)
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let reps = json["representatives_centroid"] as? [[String: Any]],
          let mp = reps.first(where: { ($0["elected_office"] as? String) == "MP" }),
          let name = mp["name"] as? String, !name.isEmpty,
          let riding = mp["district_name"] as? String else {
        throw URLError(.cannotParseResponse)
    }
    let party = mp["party_name"] as? String ?? ""
    return ClipMP(name: name, riding: riding, party: party)
}

private func fetchRecentBills() async -> [ClipBill] {
    guard let url = URL(string: "https://www.parl.ca/legisinfo/en/bills/json?parlsession=45-1&load=yes") else { return [] }
    guard let (data, _) = try? await URLSession.shared.data(from: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
    return json.prefix(3).compactMap { item -> ClipBill? in
        guard let number = item["BillNumberFormatted"] as? String,
              let title = (item["ShortTitleEn"] as? String) ?? (item["LongTitleEn"] as? String) else { return nil }
        let status = item["CurrentStatusEn"] as? String ?? ""
        return ClipBill(number: number, title: title, status: status)
    }
}

// MARK: — Main Clip View

struct ClipRootView: View {
    @State private var postalCode = ""
    @State private var mp: ClipMP?
    @State private var bills: [ClipBill] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showOverlay = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Find Your MP")
                        .font(.largeTitle.bold())
                    Text("Enter your postal code")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 32)

                // Postal code input
                VStack(spacing: 12) {
                    TextField("Postal code (e.g. K1A 0A6)", text: $postalCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                        .onSubmit { Task { await lookup() } }

                    Button {
                        Task { await lookup() }
                    } label: {
                        Group {
                            if isLoading { ProgressView().tint(.white) }
                            else { Text("Look Up") }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isLoading || postalCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if let error = errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }

                // MP result
                if let mp {
                    mpCard(mp)
                }

                // Recent bills
                if !bills.isEmpty {
                    recentBillsSection
                }

                // Install prompt
                if mp != nil {
                    Button {
                        showOverlay = true
                    } label: {
                        Label("See everything in epac", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(UIColor.systemBackground))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 1.5))
                            .cornerRadius(12)
                    }
                    .foregroundStyle(.tint)
                    .appStoreOverlay(isPresented: $showOverlay) {
                        SKOverlay.AppClipConfiguration(position: .bottom)
                    }
                }

                Spacer(minLength: 32)
            }
            .padding()
        }
        .task {
            bills = await fetchRecentBills()
        }
    }

    @ViewBuilder
    private func mpCard(_ mp: ClipMP) -> some View {
        VStack(spacing: 8) {
            Text(mp.name)
                .font(.title2.weight(.semibold))
            Text(mp.riding)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !mp.party.isEmpty {
                Text(mp.party)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }

    private var recentBillsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Legislation")
                .font(.headline)
            ForEach(bills, id: \.number) { bill in
                HStack(alignment: .top, spacing: 8) {
                    Text(bill.number)
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.tint)
                        .frame(width: 44, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bill.title)
                            .font(.caption)
                            .lineLimit(2)
                        Text(bill.status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("Source: Parliament of Canada — LEGISinfo")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func lookup() async {
        let code = postalCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        mp = nil
        defer { isLoading = false }
        do {
            mp = try await lookupMP(postalCode: code)
        } catch {
            errorMessage = "No MP found for \(code). Check your postal code."
        }
    }
}
