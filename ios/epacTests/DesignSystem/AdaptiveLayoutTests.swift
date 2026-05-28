@testable import epac
import SwiftUI
import XCTest

// These tests use a manual GeometryReader probe instead of ViewInspector.
// The repo does not vendor ViewInspector, and measuring a rendered SwiftUI host exercises the
// actual frame modifiers that call sites will receive.

final class AdaptiveLayoutTests: XCTestCase {
    private enum Metrics {
        static let regularParentWidth: CGFloat = 900
        static let compactParentWidth: CGFloat = 600
    }

    @MainActor
    func testAdaptiveReadingWidthBoundsRegularSizeClassToReadingWidth() async {
        let measuredWidth = await renderMeasuredWidth(
            parentWidth: Metrics.regularParentWidth,
            horizontalSizeClass: .regular
        )

        XCTAssertEqual(measuredWidth, AdaptiveLayout.readingWidth, accuracy: 1)
    }

    @MainActor
    func testAdaptiveReadingWidthLeavesCompactSizeClassAtParentWidth() async {
        let measuredWidth = await renderMeasuredWidth(
            parentWidth: Metrics.compactParentWidth,
            horizontalSizeClass: .compact
        )

        XCTAssertEqual(measuredWidth, Metrics.compactParentWidth, accuracy: 1)
    }

    @MainActor
    private func renderMeasuredWidth(
        parentWidth: CGFloat,
        horizontalSizeClass: UserInterfaceSizeClass
    ) async -> CGFloat {
        let expectation = expectation(description: "SwiftUI reports the adaptive layout width")
        var measuredWidth = CGFloat.zero
        var didFulfill = false
        let host = UIHostingController(
            rootView: AdaptiveReadingWidthProbe { width in
                guard !didFulfill else { return }
                didFulfill = true
                measuredWidth = width
                expectation.fulfill()
            }
            .adaptiveReadingWidth()
            .environment(\.horizontalSizeClass, horizontalSizeClass)
            .frame(width: parentWidth, height: 1)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: parentWidth, height: 1))

        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        await fulfillment(of: [expectation], timeout: 1)
        window.isHidden = true

        return measuredWidth
    }
}

private struct AdaptiveReadingWidthProbe: View {
    let onWidthChange: (CGFloat) -> Void

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: WidthPreferenceKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(WidthPreferenceKey.self, perform: onWidthChange)
    }
}

private struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
