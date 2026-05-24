//
//  TypingIndicator.swift
//  epac
//
//  Created by Sunny on 2024-12-14.
//

import SwiftUI

struct TypingIndicator: View {
	@State private var loading = false
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private enum Layout {
		static let dotSpacing: CGFloat = 20
		static let secondDotDelay: Double = 0.2
		static let thirdDotDelay: Double = 0.4
		static let dotSize: CGFloat = 10
		static let reduceMotionOpacity = 0.7
		static let inactiveOpacity = 0.5
		static let animationDuration = 0.8
	}

	var body: some View {
		HStack(spacing: Layout.dotSpacing) {
			dot(delay: 0)
			dot(delay: Layout.secondDotDelay)
			dot(delay: Layout.thirdDotDelay)
		}
		.accessibilityHidden(true)
		.onAppear {
			if !reduceMotion { loading = true }
		}
	}

	private func dot(delay: Double) -> some View {
		Circle()
			.fill(Color.gray)
			.frame(width: Layout.dotSize, height: Layout.dotSize)
			.opacity(reduceMotion ? Layout.reduceMotionOpacity : (loading ? 1 : Layout.inactiveOpacity))
			.animation(
				reduceMotion ? nil : .easeInOut(duration: Layout.animationDuration).repeatForever(autoreverses: true).delay(delay),
				value: loading
			)
	}
}

#Preview {
	TypingIndicator()
}
