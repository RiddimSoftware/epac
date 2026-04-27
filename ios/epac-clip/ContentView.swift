//
//  ContentView.swift
//  epac-clip
//
//  "Who is my MP?" — lightweight App Clip experience.
//  Users enter their postal code to instantly find their federal representative.
//  No account required. Data from represent.opennorth.ca (Open North).
//

import SwiftUI

struct ContentView: View {
	@State private var postalCode = UserDefaults.standard.string(forKey: "clip.lastMP.postalCode") ?? ""
	@State private var result: ClipMPResult? = ContentView.loadSavedResult()
	@State private var isLoading = false
	@State private var errorMessage: String?
	@FocusState private var fieldFocused: Bool

	private static let savedNameKey    = "clip.lastMP.name"
	private static let savedPartyKey   = "clip.lastMP.party"
	private static let savedRidingKey  = "clip.lastMP.riding"
	private static let savedPostalKey  = "clip.lastMP.postalCode"

	private static func loadSavedResult() -> ClipMPResult? {
		let d = UserDefaults.standard
		guard let name = d.string(forKey: savedNameKey), !name.isEmpty else { return nil }
		return ClipMPResult(
			memberName: name,
			partyName:  d.string(forKey: savedPartyKey) ?? "",
			ridingName: d.string(forKey: savedRidingKey) ?? ""
		)
	}

	private func saveResult(_ r: ClipMPResult, postalCode: String) {
		let d = UserDefaults.standard
		d.set(r.memberName, forKey: ContentView.savedNameKey)
		d.set(r.partyName,  forKey: ContentView.savedPartyKey)
		d.set(r.ridingName, forKey: ContentView.savedRidingKey)
		d.set(postalCode,   forKey: ContentView.savedPostalKey)
	}

	var body: some View {
		VStack(spacing: 0) {
			VStack(spacing: 8) {
				Image(systemName: "building.columns.fill")
					.font(.system(size: 48))
					.foregroundStyle(.tint)
					.accessibilityHidden(true)
					.padding(.top, 32)
				Text("Who is my MP?")
					.font(.largeTitle.bold())
				Text("Enter your postal code to find your federal representative.")
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
			}

			Spacer()

			VStack(spacing: 12) {
				TextField("Postal code (e.g. M5V 3A8)", text: $postalCode)
					.textInputAutocapitalization(.characters)
					.autocorrectionDisabled()
					.padding()
					.background(Color(.secondarySystemGroupedBackground))
					.cornerRadius(12)
					.focused($fieldFocused)
					.onSubmit { Task { await lookup() } }

				Button {
					Task { await lookup() }
				} label: {
					Group {
						if isLoading {
							ProgressView().tint(.white)
						} else {
							Text("Find my MP").fontWeight(.semibold)
						}
					}
					.frame(maxWidth: .infinity)
					.padding()
					.background(postalCode.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.accentColor)
					.foregroundStyle(.white)
					.cornerRadius(12)
				}
				.disabled(postalCode.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
			}
			.padding(.vertical)

			if let r = result {
				VStack(spacing: 16) {
					VStack(spacing: 6) {
						Text(r.memberName).font(.title2.bold())
						Text(r.partyName).font(.subheadline).foregroundStyle(.secondary)
						Text(r.ridingName).font(.caption).foregroundStyle(.secondary)
					}
					.padding()
					.frame(maxWidth: .infinity)
					.background(Color(.secondarySystemGroupedBackground))
					.cornerRadius(16)

					if let url = URL(string: "https://apps.apple.com/app/id6479895893") {
						Link(destination: url) {
							Label("Open in epac for full details", systemImage: "arrow.up.right.square")
								.font(.subheadline)
						}
					}
				}
			} else if let error = errorMessage {
				HStack(spacing: 8) {
					Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
					Text(error).font(.subheadline).foregroundStyle(.secondary)
				}
				.padding()
				.background(Color(.secondarySystemGroupedBackground))
				.cornerRadius(12)
			}

			Spacer()

			Text("Data from represent.opennorth.ca")
				.font(.caption2).foregroundStyle(.tertiary).padding(.bottom, 8)
		}
		.padding()
		.background(Color(.systemGroupedBackground).ignoresSafeArea())
	}

	private func lookup() async {
		let trimmed = postalCode.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
		guard trimmed.count >= 3 else { return }
		fieldFocused = false
		isLoading = true; errorMessage = nil; result = nil
		defer { isLoading = false }
		do {
			let r = try await ClipRidingLookup.find(postalCode: trimmed)
			result = r
			saveResult(r, postalCode: trimmed)
		} catch {
			errorMessage = "Could not find your riding. Check your postal code and try again."
		}
	}
}

struct ClipMPResult { let memberName: String; let partyName: String; let ridingName: String }

enum ClipRidingLookup {
	static func find(postalCode: String) async throws -> ClipMPResult {
		let upper = postalCode.uppercased().replacingOccurrences(of: " ", with: "")
		guard let url = URL(string: "https://represent.opennorth.ca/postcodes/\(upper)/?sets=federal-electoral-districts") else { throw URLError(.badURL) }
		let (data, response) = try await URLSession.shared.data(from: url)
		guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
		guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let boundaries = json["boundaries_centroid"] as? [[String: Any]]
		else { throw URLError(.cannotParseResponse) }
		let federalBoundary = boundaries.first {
			let setName = ($0["boundary_set_name"] as? String) ?? ""
			let relatedURL = (($0["related"] as? [String: Any])?["boundary_set_url"] as? String) ?? ""
			return setName == "Federal electoral district"
				&& !relatedURL.contains("2003-representation-order")
		}
		guard let ridingName = federalBoundary?["name"] as? String, !ridingName.isEmpty
		else { throw URLError(.cannotParseResponse) }
		return ClipMPResult(
			memberName: ridingName,
			partyName:  "",
			ridingName: ridingName
		)
	}
}
