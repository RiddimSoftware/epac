//
//  ShimmerModifier.swift
//  epac
//
//  Left-to-right gradient sweep applied over redacted placeholder content.
//  Usage: anyView.shimmer(when: isLoading)
//

import SwiftUI

struct ShimmerModifier: ViewModifier {
    let isActive: Bool
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .redacted(reason: isActive ? .placeholder : [])
            .overlay(
                isActive && !reduceMotion ? shimmerOverlay : nil
            )
            .animation(
                isActive && !reduceMotion ? .linear(duration: 1.2).repeatForever(autoreverses: false) : .default,
                value: phase
            )
            .onAppear {
                if isActive && !reduceMotion { phase = 1 }
            }
    }

    private var shimmerOverlay: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [
                    .clear,
                    Color(UIColor.systemBackground).opacity(0.6),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 2)
            .offset(x: phase * geo.size.width * 2 - geo.size.width)
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

extension View {
    func shimmer(when isActive: Bool) -> some View {
        modifier(ShimmerModifier(isActive: isActive))
    }
}
