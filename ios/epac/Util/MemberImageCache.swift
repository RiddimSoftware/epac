//
//  MemberImageCache.swift
//  epac
//

import UIKit

// In-memory image cache using NSCache for member photos.
//
// Sits above the two persistent layers already in place:
//   L1 (this file): NSCache<NSString, UIImage> — in-session, memory-only
//   L2: ParliamentMember.imageData — SwiftData, survives app restarts
//   L3: Network — SpeakerImageViewModel fallback chain (6 URLs)
//
// NSCache evicts automatically under memory pressure, so this is
// safe to leave running indefinitely.
final class MemberImageCache: @unchecked Sendable {
	static let shared = MemberImageCache()
	private init() {
		cache.name = "net.dinglebox.cabinetdoor.memberImages"
		cache.countLimit = 500        // up to 500 photos in memory
		cache.totalCostLimit = 50 * 1024 * 1024  // 50 MB cap
	}

	private let cache = NSCache<NSString, UIImage>()

	func image(for url: URL) -> UIImage? {
		cache.object(forKey: url.absoluteString as NSString)
	}

	func store(_ image: UIImage, for url: URL) {
		// Cost approximation: width × height × 4 bytes (RGBA)
		let cost = Int(image.size.width * image.size.height * 4)
		cache.setObject(image, forKey: url.absoluteString as NSString, cost: cost)
	}

	func store(data: Data, for url: URL) {
		guard let image = UIImage(data: data) else { return }
		store(image, for: url)
	}
}
