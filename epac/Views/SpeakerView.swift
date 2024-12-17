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

#Preview {
	SpeakerView(
		speaker: ParliamentMember(name: "Justin Trudeau", lastName: "Trudeau", firstName: "Justin", photoURL: URL(string: "https://www.ourcommons.ca/Content/Parliamentarians/Images/OfficialMPPhotos/44/TrudeauJustin_LIB.jpg")!, riding: "Papineau", province: .Quebec, party: .liberal),
		message: .init(firstName: "Justin", lastName: "Trudeau", hansardID: "10158", content: "This is the message", timestamp: .now)
	)
}
