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
	@State private var imageData: Data?
	init(speaker: ParliamentMember, message: SpeechMessage) {
		self.speaker = speaker
		self.message = message
		imageData = speaker.imageData
	}
	var body: some View {
		HStack {
			VStack {
				HStack {
					if let data = speaker.imageData, let image = UIImage(data: data) {
						Image(uiImage: image)
							.resizable()
							.scaledToFit()
						//							.frame(width: 142, height: 230)
							.frame(width: 46, height: 77)
							.cornerRadius(8)
					} else {
						ZStack {
							Circle()
								.fill(Color(uiColor: speaker.party.colour))
								.frame(width: 46, height: 46)
							Text(speaker.initials)
								.font(.system(size: 18, weight: .bold, design: .rounded))
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
			}
		}
		.font(.system(.footnote, design: .default, weight: .regular))
		.task {
			if speaker.imageData == nil {
				do {
					let (data, _) = try await URLSession.shared.data(from: speaker.photoURL)
					if !data.isEmpty, UIImage(data: data) != nil {
						speaker.imageData = data
						withAnimation {
							self.imageData = data
						}
					}
				} catch {
					Log.debug("Failed to download member image \(error.localizedDescription)")
				}
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
		}
	}
}

struct SpeakerImageView: View {
	let speaker: ParliamentMember
	let parliamentNumber: Int
	@Environment(\.modelContext) var modelContext
	@State private var imageData: Data?
	init(speaker: ParliamentMember, parliamentNumber: Int) {
		self.speaker = speaker
		self.parliamentNumber = parliamentNumber
		imageData = speaker.imageData
	}
	var body: some View {
		VStack {
			if let data = speaker.imageData, let image = UIImage(data: data) {
				Image(uiImage: image)
					.resizable()
					.scaledToFit()
					.frame(width: 46, height: 77)
					.cornerRadius(8)
			} else {
				ZStack {
					Circle()
						.fill(Color(uiColor: speaker.party.colour))
						.frame(width: 46, height: 46)
					Text(speaker.initials)
						.font(.system(size: 18, weight: .bold, design: .rounded))
						.foregroundColor(.white)
				}
				.frame(width: 46, height: 77)
			}
			PartyImageView(party: speaker.party)
		}
		.padding(0)
		.task {
			let provider = PhotoProvider(parliamentNumber: parliamentNumber)
			var fns: [(String, String, Party) -> URL] = [
				provider.getPhotoURL2,
				provider.getPhotoURL3,
				provider.getPhotoURL4,
				provider.getPhotoURL5,
				provider.getPhotoURL6,
				provider.getPhotoURL7
			]
			if speaker.imageData == nil {
				do {
					try await updateImageData(speaker)
				} catch {
					Log.debug("\(error.localizedDescription)")
					while !fns.isEmpty {
						let fn = fns.removeFirst()
						speaker.photoURL = fn(speaker.lastName, speaker.firstName, speaker.party)
						do {
							try await updateImageData(speaker)
							fns.removeAll()
						} catch {
							Log.debug("\(error.localizedDescription)")
							if fns.isEmpty {
								Log.debug("Failed to download speaker image \(speaker.name)")
							} else {
								continue
							}
						}
					}
				}
			}
		}
	}

	private func updateImageData(_ speaker: ParliamentMember) async throws {
		Log.debug("Fetching \(speaker.photoURL.absoluteString)")
		let (data, _) = try await URLSession.shared.data(from: speaker.photoURL)
		if !data.isEmpty, UIImage(data: data) != nil {
			speaker.imageData = data
			withAnimation {
				self.imageData = data
			}
			do {
				let id = speaker.id
				if let fetched = modelContext.model(for: id) as? ParliamentMember {
					fetched.imageData = data
					try modelContext.save()
				}
			} catch {
				Log.debug("Failed to updateImageData \(speaker.name)")
			}
		} else {
			throw NSError(domain: "", code: 100)
		}
	}
}

#Preview {
	SpeakerView(
		speaker: ParliamentMember(name: "Justin Trudeau", lastName: "Trudeau", firstName: "Justin", photoURL: URL(string: "https://www.ourcommons.ca/Content/Parliamentarians/Images/OfficialMPPhotos/44/TrudeauJustin_LIB.jpg")!, riding: "Papineau", province: .Quebec, party: .liberal),
		message: .init(firstName: "Justin", lastName: "Trudeau", partyAbbreviation: "Lib", ridingName: "Yukon", hansardID: "10158", content: "This is the message", timestamp: .now)
	)
}
