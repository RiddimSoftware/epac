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

	var body: some View {
		HStack(spacing: 20) {
			dot(delay: 0)
			dot(delay: 0.2)
			dot(delay: 0.4)
		}
		.accessibilityHidden(true)
		.onAppear {
			if !reduceMotion { loading = true }
		}
	}

	private func dot(delay: Double) -> some View {
		Circle()
			.fill(Color.gray)
			.frame(width: 10, height: 10)
			.opacity(reduceMotion ? 0.7 : (loading ? 1 : 0.5))
			.animation(
				reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(delay),
				value: loading
			)
	}
}

#Preview {
	TypingIndicator()
}
