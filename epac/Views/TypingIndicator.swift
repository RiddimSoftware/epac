//
//  TypingIndicator.swift
//  epac
//
//  Created by Sunny on 2024-12-14.
//

import SwiftUI

struct TypingIndicator: View {
	@State private var loading = false
	var body: some View {
		HStack(spacing: 20) {
			Circle()
				.fill(Color.gray)
				.frame(width: 10, height: 10)
				.animation(nil, value: loading)
				.opacity(loading ? 1 : 0.5)
//				.scaleEffect(loading ? 1.5 : 0.5)
				.animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: loading)
			Circle()
				.fill(Color.gray)
				.frame(width: 10, height: 10)
				.animation(nil, value: loading)
				.opacity(loading ? 1 : 0.5)
//				.scaleEffect(loading ? 1.5 : 0.5)
				.animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(0.2), value: loading)
			Circle()
				.fill(Color.gray)
				.frame(width: 10, height: 10)
				.animation(nil, value: loading)
				.opacity(loading ? 1 : 0.5)
//				.scaleEffect(loading ? 1.5 : 0.5)
				.animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(0.4), value: loading)
		}
		.onAppear {
			loading = true
		}
	}
}

#Preview {
	TypingIndicator()
}
