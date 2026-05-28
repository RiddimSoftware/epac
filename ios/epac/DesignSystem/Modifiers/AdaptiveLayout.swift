import SwiftUI

enum AdaptiveLayout {
    /// Stage-2 long-form reading width used for regular horizontal size classes.
    static let readingWidth: CGFloat = 720
}

private struct AdaptiveReadingWidthModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ViewBuilder
    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content
                .frame(maxWidth: AdaptiveLayout.readingWidth)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            content
        }
    }
}

private struct RegularSizeClassFormSheetModifier<SheetContent: View>: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var isPresented: Bool

    let onDismiss: (() -> Void)?
    let sheetContent: () -> SheetContent

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
            sheetContent()
                .regularSizeClassSheetChrome(isEnabled: horizontalSizeClass == .regular)
        }
    }
}

private struct RegularSizeClassItemFormSheetModifier<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var item: Item?

    let onDismiss: (() -> Void)?
    let sheetContent: (Item) -> SheetContent

    func body(content: Content) -> some View {
        content.sheet(item: $item, onDismiss: onDismiss) { item in
            sheetContent(item)
                .regularSizeClassSheetChrome(isEnabled: horizontalSizeClass == .regular)
        }
    }
}

extension View {
    /// Constrains long-form reading surfaces to `AdaptiveLayout.readingWidth` in a regular
    /// horizontal size class while leaving compact layouts unchanged.
    ///
    /// Use this for Stage-2 per-view polish where lists or reading-heavy containers should not
    /// stretch edge-to-edge on iPad, Mac Catalyst, or other regular-size-class presentations.
    /// Apply it to the container around a `List`, not individual rows, because `List` can swallow
    /// row-level frame constraints in unexpected ways. Do not use it on compact-first controls or
    /// intentionally full-width surfaces that need all available space.
    func adaptiveReadingWidth() -> some View {
        modifier(AdaptiveReadingWidthModifier())
    }

    /// Presents a sheet normally in compact width and with medium/large detents plus a visible
    /// drag indicator in a regular horizontal size class.
    ///
    /// Use this as the Stage-2 drop-in replacement for `.sheet(isPresented:content:)` when a
    /// modal should adapt to iPad and Mac Catalyst form-sheet ergonomics. Do not use it for flows
    /// that must remain full-screen on iPad for ergonomic or product reasons, such as onboarding.
    func regularSizeClassFormSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        regularSizeClassFormSheet(isPresented: isPresented, onDismiss: nil, content: content)
    }

    /// Presents a sheet normally in compact width and with medium/large detents plus a visible
    /// drag indicator in a regular horizontal size class.
    ///
    /// Use this as the Stage-2 drop-in replacement for `.sheet(isPresented:onDismiss:content:)`
    /// when a modal should adapt to iPad and Mac Catalyst form-sheet ergonomics. Do not use it for
    /// flows that must remain full-screen on iPad for ergonomic or product reasons, such as onboarding.
    func regularSizeClassFormSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)?,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(
            RegularSizeClassFormSheetModifier(
                isPresented: isPresented,
                onDismiss: onDismiss,
                sheetContent: content
            )
        )
    }

    /// Presents an item-driven sheet normally in compact width and with medium/large detents plus
    /// a visible drag indicator in a regular horizontal size class.
    ///
    /// Use this as the Stage-2 drop-in replacement for `.sheet(item:onDismiss:content:)` when a
    /// modal should adapt to iPad and Mac Catalyst form-sheet ergonomics. Do not use it for flows
    /// that must remain full-screen on iPad for ergonomic or product reasons, such as onboarding.
    func regularSizeClassFormSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        modifier(
            RegularSizeClassItemFormSheetModifier(
                item: item,
                onDismiss: onDismiss,
                sheetContent: content
            )
        )
    }
}

private extension View {
    @ViewBuilder
    func regularSizeClassSheetChrome(isEnabled: Bool) -> some View {
        if isEnabled {
            presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
    }
}

private struct AdaptiveLayoutPreview: View {
    @State private var showsDetails = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: EpacSpacing.m) {
                Text("Adaptive reading width")
                    .font(.epacTitle)
                    .foregroundStyle(Color.epacText.primary)

                Text("A regular-size-class container is capped and centered; compact layouts keep the parent width.")
                    .font(.epacBody)
                    .foregroundStyle(Color.epacText.secondary)

                Button("Show adaptive sheet") {
                    showsDetails = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(EpacSpacing.l)
            .adaptiveReadingWidth()
            .regularSizeClassFormSheet(isPresented: $showsDetails) {
                VStack(alignment: .leading, spacing: EpacSpacing.m) {
                    Text("Regular form sheet")
                        .font(.epacTitle)
                    Text("Compact presentations keep SwiftUI's default sheet behavior.")
                        .font(.epacBody)
                }
                .padding(EpacSpacing.l)
            }
        }
    }
}

private enum AdaptiveLayoutPreviewMetrics {
    static let compactWidth: CGFloat = 390
    static let regularWidth: CGFloat = 900
}

#Preview("Adaptive layout primitives") {
    HStack(alignment: .top, spacing: EpacSpacing.l) {
        AdaptiveLayoutPreview()
            .environment(\.horizontalSizeClass, .compact)
            .frame(width: AdaptiveLayoutPreviewMetrics.compactWidth)

        AdaptiveLayoutPreview()
            .environment(\.horizontalSizeClass, .regular)
            .frame(width: AdaptiveLayoutPreviewMetrics.regularWidth)
    }
}
