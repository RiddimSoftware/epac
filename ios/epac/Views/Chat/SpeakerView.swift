//
//  SpeakerView.swift
//  epac
//
//  Created by Sunny on 2024-12-17.
//

import SwiftData
import SwiftUI

private enum SpeakerLayout {
	static let portraitWidth: CGFloat = 46
	static let portraitHeight: CGFloat = 77
	static let portraitCornerRadius = EpacCornerRadius.s
	static let placeholderSize: CGFloat = 46
	static let partyImageSize = EpacIconSize.xl
	static let partyImagePadding: CGFloat = 5
	static let compactPartyImageSize = EpacIconSize.m
}

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
							.frame(width: SpeakerLayout.portraitWidth, height: SpeakerLayout.portraitHeight)
							.cornerRadius(SpeakerLayout.portraitCornerRadius)
					} else {
						ZStack {
							Circle()
								.fill(Color.party(speaker.party))
								.frame(width: SpeakerLayout.placeholderSize, height: SpeakerLayout.placeholderSize)
							Text(speaker.initials)
								.font(.system(.headline, design: .rounded))
								.foregroundColor(.white)
						}
						.frame(width: SpeakerLayout.portraitWidth, height: SpeakerLayout.portraitHeight)
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
					.frame(width: SpeakerLayout.partyImageSize, height: SpeakerLayout.partyImageSize)
					.padding(SpeakerLayout.partyImagePadding)
					.background(.white)
					.accessibilityHidden(true)
			}
		}
		.font(.system(.footnote, design: .default, weight: .regular))
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(speaker.name), \(speaker.party.fullName), \(speaker.riding), \(speaker.province.rawValue)")
		.task {
			// L1: NSCache fast path — already decoded in memory, zero cost.
			if let cached = MemberImageCache.shared.image(for: speaker.photoURL) {
				photo = cached
				return
			}
			if let data = speaker.imageData {
				// L2: SwiftData blob — decode off the main thread.
				let decoded = await Task.detached(priority: .userInitiated) { UIImage(data: data) }.value
				if let decoded {
					MemberImageCache.shared.store(decoded, for: speaker.photoURL)
					photo = decoded
				}
			} else {
				// L3: Network download then decode off the main thread.
				guard let (data, _) = try? await NetworkService.shared.data(from: speaker.photoURL),
					  !data.isEmpty else { return }
				let decoded = await Task.detached(priority: .userInitiated) { UIImage(data: data) }.value
				guard let decoded else { return }
				MemberImageCache.shared.store(decoded, for: speaker.photoURL)
				photo = decoded
				speaker.imageData = data
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
				.frame(width: SpeakerLayout.compactPartyImageSize, height: SpeakerLayout.compactPartyImageSize)
				.padding(SpeakerLayout.partyImagePadding)
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
					.frame(width: SpeakerLayout.portraitWidth, height: SpeakerLayout.portraitHeight)
					.cornerRadius(SpeakerLayout.portraitCornerRadius)
			} else {
				ZStack {
					Circle()
						.fill(Color.party(speaker.party))
						.frame(width: SpeakerLayout.placeholderSize, height: SpeakerLayout.placeholderSize)
					Text(speaker.initials)
						.font(.system(.headline, design: .rounded))
						.foregroundColor(.white)
				}
				.frame(width: SpeakerLayout.portraitWidth, height: SpeakerLayout.portraitHeight)
			}
			PartyImageView(party: speaker.party)
		}
		.padding(0)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("\(speaker.name), \(speaker.party.fullName)")
		.task(id: speaker.photoURL) {
			await loadPhoto()
		}
	}

	private func loadPhoto() async {
		guard photo == nil else { return }
		if let cached = MemberImageCache.shared.image(for: speaker.photoURL) {
			photo = cached
			return
		}
		if let image = await decodeStoredPhotoData() {
			photo = image
			return
		}
		await viewModel.loadImage(speaker: speaker, parliamentNumber: parliamentNumber, modelContext: modelContext)
		if let cached = MemberImageCache.shared.image(for: speaker.photoURL) {
			photo = cached
		} else if let image = await decodeStoredPhotoData() {
			photo = image
		}
	}

	private func decodeStoredPhotoData() async -> UIImage? {
		guard let data = viewModel.imageData ?? speaker.imageData else { return nil }
		let image = await Task.detached(priority: .userInitiated) { UIImage(data: data) }.value
		if let image {
			MemberImageCache.shared.store(image, for: speaker.photoURL)
		}
		return image
	}
}

#Preview {
	SpeakerView(
		speaker: ParliamentMember(name: "Justin Trudeau", lastName: "Trudeau", firstName: "Justin", photoURL: URL(string: "https://www.ourcommons.ca/Content/Parliamentarians/Images/OfficialMPPhotos/44/TrudeauJustin_LIB.jpg")!, riding: "Papineau", province: .Quebec, party: .liberal),
		message: .init(firstName: "Justin", lastName: "Trudeau", partyAbbreviation: "Lib", ridingName: "Yukon", hansardID: "10158", content: "This is the message", timestamp: .now)
	)
}
