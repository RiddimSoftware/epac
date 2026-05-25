// WhatsNewView.swift
// epac
//
// Modal sheet shown exactly once after each app update (never on first install).
// Content is driven by whats-new.json in the app bundle.
// Dismisses via the Continue button or automatically after 5 seconds.

import SwiftUI

private enum WhatsNewLayout {
    static let rootSpacing: CGFloat = 24
    static let titleSpacing = EpacSpacing.s
    static let iconFontSize = EpacSpacing.avatar
    static let titleTopPadding = EpacSpacing.xl
    static let itemListSpacing: CGFloat = 20
    static let itemRowSpacing = EpacSpacing.m
    static let itemIconWidth: CGFloat = 36
    static let itemTextSpacing = EpacSpacing.xs
    static let itemHorizontalPadding = EpacSpacing.s
    static let continueBottomPadding = EpacSpacing.xl
    static let horizontalPadding: CGFloat = 28
    static let autoDismissSeconds: Int64 = 5
}

struct WhatsNewEntry: Decodable {
    let version: String
    let headline: String
    let items: [WhatsNewItem]
}

struct WhatsNewItem: Decodable {
    let icon: String
    let title: String
    let body: String
}

@MainActor
final class WhatsNewManager {
    static let shared = WhatsNewManager()

    private let lastSeenKey = "epac.whatsNew.lastSeenVersion"

    private init() {}

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    // Returns true if the sheet should be shown (app was updated, not first install).
    // Side effect: if this is a first install, records the current version so no sheet shows.
    func shouldShow() -> Bool {
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: lastSeenKey)
        if stored == nil {
            // First install — record current version silently, don't show.
            defaults.set(currentVersion, forKey: lastSeenKey)
            return false
        }
        return stored != currentVersion
    }

    func markSeen() {
        UserDefaults.standard.set(currentVersion, forKey: lastSeenKey)
    }

    func entry() -> WhatsNewEntry? {
        guard let url = Bundle.main.url(forResource: "whats-new", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([WhatsNewEntry].self, from: data) else {
            return nil
        }
        return entries.first(where: { $0.version == currentVersion }) ?? entries.first
    }
}

struct WhatsNewView: View {
    var onDismiss: () -> Void

    @State private var dismissTask: Task<Void, Never>?
    // Guard against dismiss() being called more than once (button + auto-timer race).
    @State private var hasDismissed = false
    // Loaded once on appear; avoids re-reading the bundle JSON on every render.
    @State private var entry: WhatsNewEntry?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: WhatsNewLayout.rootSpacing) {
                VStack(spacing: WhatsNewLayout.titleSpacing) {
                    Image(systemName: "sparkles")
                        .font(.system(size: WhatsNewLayout.iconFontSize))
                        .foregroundStyle(Color.accentColor)
                    Text(entry?.headline ?? "What's new in epac")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                }
                .padding(.top, WhatsNewLayout.titleTopPadding)

                if let items = entry?.items {
                    VStack(alignment: .leading, spacing: WhatsNewLayout.itemListSpacing) {
                        ForEach(items, id: \.title) { item in
                            HStack(alignment: .top, spacing: WhatsNewLayout.itemRowSpacing) {
                                Text(item.icon)
                                    .font(.title2)
                                    .frame(width: WhatsNewLayout.itemIconWidth)
                                VStack(alignment: .leading, spacing: WhatsNewLayout.itemTextSpacing) {
                                    Text(item.title)
                                        .font(.headline)
                                    Text(item.body)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, WhatsNewLayout.itemHorizontalPadding)
                }

                Spacer(minLength: 0)

                Button {
                    dismiss()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, WhatsNewLayout.continueBottomPadding)
            }
            .padding(.horizontal, WhatsNewLayout.horizontalPadding)
        }
        .onAppear {
            entry = WhatsNewManager.shared.entry()
            dismissTask = Task {
                try? await Task.sleep(for: .seconds(WhatsNewLayout.autoDismissSeconds))
                dismiss()
            }
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }

    private func dismiss() {
        guard !hasDismissed else { return }
        hasDismissed = true
        dismissTask?.cancel()
        WhatsNewManager.shared.markSeen()
        onDismiss()
    }
}
