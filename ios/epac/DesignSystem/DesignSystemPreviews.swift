import SwiftUI

// Lightweight preview views used by DesignSystemSnapshotTests.
// Not shipped to users — these are @testable-accessed by the test target.

struct DesignSystemColorTokensPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: EpacSpacing.s) {
            colorRow("epacText.primary", Color.epacText.primary)
            colorRow("epacText.secondary", Color.epacText.secondary)
            colorRow("epacText.tertiary", Color.epacText.tertiary)
            colorRow("epacText.accent", Color.epacText.accent)
            Divider()
            colorRow("epacSurface.primary", Color.epacSurface.primary)
            colorRow("epacSurface.elevated", Color.epacSurface.elevated)
            colorRow("epacSurface.grouped", Color.epacSurface.grouped)
            Divider()
            colorRow("epacBrand.accent", Color.epacBrand.accent)
            colorRow("epacBrand.accentMuted", Color.epacBrand.accentMuted)
            colorRow("epacBrand.positive", Color.epacBrand.positive)
            colorRow("epacBrand.negative", Color.epacBrand.negative)
            colorRow("epacBrand.neutral", Color.epacBrand.neutral)
            Divider()
            colorRow("epacStatus.success", Color.epacStatus.success)
            colorRow("epacStatus.warning", Color.epacStatus.warning)
            colorRow("epacStatus.destructive", Color.epacStatus.destructive)
            colorRow("epacStatus.info", Color.epacStatus.info)
        }
        .padding(EpacSpacing.m)
        .background(Color.epacSurface.primary)
    }

    private func colorRow(_ name: String, _ color: Color) -> some View {
        HStack(spacing: EpacSpacing.s) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 32, height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.epacText.tertiary.opacity(0.3), lineWidth: 0.5)
                )
            Text(name)
                .font(.epacCaption.monospaced())
                .foregroundStyle(Color.epacText.primary)
        }
    }
}

struct DesignSystemTypographyPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: EpacSpacing.s) {
            row("epacDisplay", font: .epacDisplay)
            row("epacTitle", font: .epacTitle)
            row("epacHeadline", font: .epacHeadline)
            row("epacBody", font: .epacBody)
            row("epacCallout", font: .epacCallout)
            row("epacSubheadline", font: .epacSubheadline)
            row("epacFootnote", font: .epacFootnote)
            row("epacCaption", font: .epacCaption)
        }
        .padding(EpacSpacing.m)
        .background(Color.epacSurface.primary)
    }

    private func row(_ label: String, font: Font) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Canada's Parliament")
                .font(font)
                .foregroundStyle(Color.epacText.primary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Color.epacText.tertiary)
        }
    }
}
