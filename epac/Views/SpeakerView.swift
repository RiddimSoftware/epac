//
//  SpeakerView.swift
//  epac
//
//  Created by Sunny on 2024-12-17.
//

import SwiftUI

struct SpeakerView: View {
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
					} else {
						Image(systemName: "person.circle")
							.resizable()
							.scaledToFit()
							.frame(width: 46, height: 77)
					}
				}
			}
			VStack {
				Text(verbatim: speaker.name)
				Text(verbatim: speaker.riding)
				Text(verbatim: speaker.province.rawValue)
			}

			if let image = speaker.party.image {
				Image(uiImage: image)
					.resizable()
					.frame(width: 40, height: 40)
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
					print("Failed to download member image \(error.localizedDescription)")
				}
			}
		}
	}
}

struct SpeakerNameView: View {
	let speaker: ParliamentMember
	let alignment: HorizontalAlignment
	init(speaker: ParliamentMember, alignment: HorizontalAlignment) {
		self.speaker = speaker
		self.alignment = alignment
	}
	var body: some View {
		HStack(spacing: 0) {
			VStack(alignment: alignment, spacing: 1) {
				Text(verbatim: speaker.name)
				Text(verbatim: speaker.riding)
				Text(verbatim: speaker.province.rawValue)
			}
		}
		.fontDesign(.rounded)
		.font(.system(.footnote, weight: .regular))
	}
}

struct PartyImageView: View {
	let party: Party
	var body: some View {
		Image(uiImage: party.image!)
			.resizable()
			.frame(width: 16, height: 16)
			.padding(5)
			.background(.white)
	}
}

struct SpeakerImageView: View {
	let speaker: ParliamentMember
	@State private var imageData: Data?
	init(speaker: ParliamentMember) {
		self.speaker = speaker
		imageData = speaker.imageData
	}
	var body: some View {
		VStack {
			if let data = speaker.imageData, let image = UIImage(data: data) {
				Image(uiImage: image)
					.resizable()
					.scaledToFit()
					.frame(width: 46, height: 77)
			} else {
				Image(systemName: "person.circle")
					.resizable()
					.scaledToFit()
					.frame(width: 46, height: 77)
			}
			PartyImageView(party: speaker.party)
		}
		.padding(0)
		.task {
			var fns: [(String, String, Party) -> URL] = [
				PhotoProvider.getPhotoURL2,
				PhotoProvider.getPhotoURL3,
				PhotoProvider.getPhotoURL4,
				PhotoProvider.getPhotoURL5,
				PhotoProvider.getPhotoURL6
			]
			if speaker.imageData == nil {
				do {
					try await updateImageData(speaker)
				} catch {
					print(error.localizedDescription)
					while !fns.isEmpty {
						let fn = fns.removeFirst()
						speaker.photoURL = fn(speaker.lastName, speaker.firstName, speaker.party)
						do {
							try await updateImageData(speaker)
							fns.removeAll()
						} catch {
							print(error.localizedDescription)
							if fns.isEmpty {
								print("Failed to download speaker image \(speaker.name)")
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
		print("Fetching \(speaker.photoURL.absoluteString)")
		let (data, _) = try await URLSession.shared.data(from: speaker.photoURL)
		if !data.isEmpty, UIImage(data: data) != nil {
			speaker.imageData = data
			withAnimation {
				self.imageData = data
			}
		} else {
			throw NSError(domain: "", code: 100)
		}
	}
}

#Preview {
	SpeakerView(
		speaker: ParliamentMember(name: "Justin Trudeau", lastName: "Trudeau", firstName: "Justin", photoURL: URL(string: "https://www.ourcommons.ca/Content/Parliamentarians/Images/OfficialMPPhotos/44/TrudeauJustin_LIB.jpg")!, riding: "Papineau", province: .Quebec, party: .liberal),
		message: .init(firstName: "Justin", lastName: "Trudeau", hansardID: "10158", content: "This is the message", timestamp: .now)
	)
}
