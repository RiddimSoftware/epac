import Foundation

@MainActor
final class MacCommandCenter {
	static let shared = MacCommandCenter()

	var selectTab: ((AppTab) -> Void)?
	var refresh: (() -> Void)?
	var share: (() -> Void)?

	private init() {}

	func select(_ tab: AppTab) {
		selectTab?(tab)
	}

	func find() {
		selectTab?(.search)
	}

	func refreshContent() {
		refresh?()
	}

	func shareCurrentContext() {
		share?()
	}
}
