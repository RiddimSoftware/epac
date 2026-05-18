//
//  CalendarScrollsToTopDisabler.swift
//  epac
//

import SwiftUI
import UIKit

struct CalendarScrollsToTopDisabler: UIViewRepresentable {
	func makeUIView(context: Context) -> UIView {
		let view = UIView(frame: .zero)
		view.isUserInteractionEnabled = false
		view.isAccessibilityElement = false
		return view
	}

	func updateUIView(_ uiView: UIView, context: Context) {
		DispatchQueue.main.async {
			var ancestor = uiView.superview
			while let view = ancestor {
				if Self.disable(in: view) {
					break
				}
				ancestor = view.superview
			}
		}
	}

	@discardableResult
	static func disable(in root: UIView) -> Bool {
		var didDisableCalendarScrollView = false
		visit(root) { view in
			guard let scrollView = view as? UIScrollView,
			      isHorizonCalendarScrollView(scrollView) else {
				return
			}
			scrollView.scrollsToTop = false
			didDisableCalendarScrollView = true
		}
		return didDisableCalendarScrollView
	}

	private static func visit(_ view: UIView, body: (UIView) -> Void) {
		body(view)
		for subview in view.subviews {
			visit(subview, body: body)
		}
	}

	private static func isHorizonCalendarScrollView(_ scrollView: UIScrollView) -> Bool {
		// HorizonCalendar keeps CalendarScrollView internal, so match its runtime class name
		// instead of importing or blanket-disabling every scroll view in the hierarchy.
		String(describing: type(of: scrollView)) == "CalendarScrollView"
	}
}
