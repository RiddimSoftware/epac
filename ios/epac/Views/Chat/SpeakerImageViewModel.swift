//
//  SpeakerImageViewModel.swift
//  epac
//

import Observation
import SwiftData
import UIKit

@Observable
class SpeakerImageViewModel {
	var imageData: Data?

	func loadImage(speaker: ParliamentMember, parliamentNumber: Int, modelContext: ModelContext) async {
		guard speaker.imageData == nil else {
			imageData = speaker.imageData
			return
		}

		let provider = PhotoProvider(parliamentNumber: parliamentNumber)
		var fns: [(String, String, Party) -> URL] = [
			provider.getPhotoURL2,
			provider.getPhotoURL3,
			provider.getPhotoURL4,
			provider.getPhotoURL5,
			provider.getPhotoURL6,
			provider.getPhotoURL7
		]

		do {
			try await updateImageData(speaker, modelContext: modelContext)
		} catch {
			Log.debug("\(error.localizedDescription)")
			while !fns.isEmpty {
				let fn = fns.removeFirst()
				speaker.photoURL = fn(speaker.lastName, speaker.firstName, speaker.party)
				do {
					try await updateImageData(speaker, modelContext: modelContext)
					fns.removeAll()
				} catch {
					Log.debug("\(error.localizedDescription)")
					if fns.isEmpty {
						Log.debug("Failed to download speaker image \(speaker.name)")
					}
				}
			}
		}
	}

	private func updateImageData(_ speaker: ParliamentMember, modelContext: ModelContext) async throws {
		Log.debug("Fetching \(speaker.photoURL.absoluteString)")
		let (data, _) = try await URLSession.shared.data(from: speaker.photoURL)
		if !data.isEmpty, UIKit.UIImage(data: data) != nil {
			speaker.imageData = data
			imageData = data
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
