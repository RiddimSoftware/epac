//
//  SpeakerView.swift
//  epac
//
//  Created by Sunny on 2024-12-17.
//

import SwiftUI
import SwiftData

struct SpeakerView: View {
	@Environment(\.modelContext) var modelContext
	let speaker: ParliamentMember
	let message: SpeechMessage
	@State private var photo: UIImage?

	var body: some View {
		HStack {
			VStack {
				HStack {
					if let photo {
						Image(uiImage: photo)
							.resizable()
							.scaledToFit()
							.frame(width: 46, height: 77)
							.cornerRadius(8)
					} else {
						ZStack {
							Circle()
								.fill(Color.party(speaker.party))
								.frame(width: 46, height: 46)
							Text(speaker.initials)
								.font(.system(.headline, design: .rounded))
								.foregroundColor(.white)
						}
						.frame(width: 46, height: 77)
					}
				}
			}
			VStack {
				Text(verbatim: speaker.riding)
				Text(verbatim: speaker.province.rawValue)
			}

			if let image = speaker.party.image {
				Image(uiImage: image)
					.resizable()
					.frame(width: 48, height: 48)
					.padding(5)
					.background(.white)
					.accessibilityHidden(true)
			}
		}
		.font(.system(.footnote, design: .default, weight: .regular))
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(speaker.name), \(speaker.party.fullName), \(speaker.riding), \(speaker.province.rawValue)")
		.task {
			if let data = speaker.imageData {
				// Decode stored image data off the main thread.
				photo = await Task.detached(priority: .userInitiated) { UIImage(data: data) }.value
			} else {
				// Download then decode off the main thread.
				guard let (data, _) = try? await URLSession.shared.data(from: speaker.photoURL),
					  !data.isEmpty else { return }
				let decoded = await Task.detached(priority: .userInitiated) { UIImage(data: data) }.value
				guard let decoded else { return }
				photo = decoded
				speaker.imageData = data
				MemberImageCache.shared.store(decoded, for: speaker.photoURL)
			}
		}
	}
}

struct PartyImageView: View {
	let party: Party
	var body: some View {
		if let image = party.image {
			Image(uiImage: image)
				.resizable()
				.frame(width: 24, height: 24)
				.padding(5)
				.background(.white)
				.accessibilityHidden(true)
		}
	}
}

struct SpeakerImageView: View {
	let speaker: ParliamentMember
	let parliamentNumber: Int
	@Environment(\.modelContext) var modelContext
	@State private var viewModel = SpeakerImageViewModel()
	@State private var photo: UIImage?

	var body: some View {
		VStack {
			if let photo {
				Image(uiImage: photo)
					.resizable()
					.scaledToFit()
					.frame(width: 46, height: 77)
					.cornerRadius(8)
			} else {
				ZStack {
					Circle()
						.fill(Color.party(speaker.party))
						.frame(width: 46, height: 46)
					Text(speaker.initials)
						.font(.system(.headline, design: .rounded))
						.foregroundColor(.white)
				}
				.frame(width: 46, height: 77)
			}
			PartyImageView(party: speaker.party)
		}
		.padding(0)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("\(speaker.name), \(speaker.party.fullName)")
		.task {
			await viewModel.loadImage(speaker: speaker, parliamentNumber: parliamentNumber, modelContext: modelContext)
			if let data = viewModel.imageData ?? speaker.imageData {
				photo = await Task.detached(priority: .userInitiated) { UIImage(data: data) }.value
			}
		}
	}
}

#Preview {
	SpeakerView(
		speaker: ParliamentMember(name: "Justin Trudeau", lastName: "Trudeau", firstName: "Justin", photoURL: URL(string: "https://www.ourcommons.ca/Content/Parliamentarians/Images/OfficialMPPhotos/44/TrudeauJustin_LIB.jpg")!, riding: "Papineau", province: .Quebec, party: .liberal),
		message: .init(firstName: "Justin", lastName: "Trudeau", partyAbbreviation: "Lib", ridingName: "Yukon", hansardID: "10158", content: "This is the message", timestamp: .now)
	)
}
