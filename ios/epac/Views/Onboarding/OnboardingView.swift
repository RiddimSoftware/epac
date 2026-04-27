//
//  OnboardingView.swift
//  epac
//
//  5-screen onboarding flow (EPAC-296):
//  1. What is epac? — three data-source statements
//  2. Your MP — postal code lookup (reuses PostalCodeSetupView logic)
//  3. Topics — chip picker (1–4 topics, max)
//  4. Notifications — contextual permission request
//  5. Promise — "here's what you'll get"
//
//  Each screen has a Skip button (dismisses the whole flow) and a Continue
//  button (advances). Completion is persisted to UserDefaults so it never
//  shows again.
//

import SwiftUI
import SwiftData

@MainActor
struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var page = 0
    @State private var postalCodeVM = PostalCodeViewModel()
    @State private var selectedTopics: Set<String> = []
    @Environment(\.modelContext) private var modelContext
    @Environment(NotificationManager.self) private var notificationManager

    private let totalPages = 5

    var body: some View {
        TabView(selection: $page) {
            whatIsEpacScreen.tag(0)
            yourMPScreen.tag(1)
            topicsScreen.tag(2)
            notificationsScreen.tag(3)
            promiseScreen.tag(4)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut, value: page)
        .overlay(alignment: .topTrailing) {
            if page < totalPages - 1 {
                Button(NSLocalizedString("onboarding.skip", comment: "")) {
                    complete()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
            }
        }
        .overlay(alignment: .bottom) {
            pageIndicator
                .padding(.bottom, 16)
        }
    }

    // MARK: - Page indicator

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalPages, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: i == page ? 20 : 6, height: 6)
                    .animation(.spring(duration: 0.3), value: page)
            }
        }
    }

    // MARK: - Screen 1: What is epac?

    private var whatIsEpacScreen: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 32) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(NSLocalizedString("onboarding.what.title", comment: ""))
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)

                    Text(NSLocalizedString("onboarding.what.subtitle", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 16) {
                    DataPointRow(icon: "text.document.fill",
                                 text: NSLocalizedString("onboarding.what.point1", comment: ""))
                    DataPointRow(icon: "checkmark.seal.fill",
                                 text: NSLocalizedString("onboarding.what.point2", comment: ""))
                    DataPointRow(icon: "person.2.badge.key.fill",
                                 text: NSLocalizedString("onboarding.what.point3", comment: ""))
                }
                .padding(.horizontal, 8)

                Text(NSLocalizedString("onboarding.what.trust", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()

            ContinueButton(label: NSLocalizedString("onboarding.getStarted", comment: "")) {
                advance()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Screen 2: Your MP

    private var yourMPScreen: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                            .padding(.top, 60)

                        Text(NSLocalizedString("riding.setup.title", comment: ""))
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)

                        Text(NSLocalizedString("riding.setup.subtitle", comment: ""))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 14) {
                        TextField(NSLocalizedString("riding.setup.placeholder", comment: ""),
                                  text: $postalCodeVM.postalCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .onSubmit { Task { await postalCodeVM.lookup(modelContext: modelContext) } }

                        Button {
                            Task { await postalCodeVM.lookup(modelContext: modelContext) }
                        } label: {
                            Group {
                                if postalCodeVM.isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(NSLocalizedString("riding.setup.lookupButton", comment: ""))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                        }
                        .disabled(postalCodeVM.isLoading || postalCodeVM.postalCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 24)

                    if let error = postalCodeVM.errorMessage {
                        Text(error).font(.subheadline).foregroundStyle(.red).padding(.horizontal, 24)
                    }

                    if let result = postalCodeVM.result {
                        mpResultCard(result)
                            .padding(.horizontal, 24)
                    }

                    Spacer(minLength: 80)
                }
            }

            if postalCodeVM.result == nil {
                ContinueButton(label: NSLocalizedString("onboarding.skip", comment: ""),
                               style: .secondary) {
                    advance()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 60)
            }
        }
    }

    private func mpResultCard(_ result: RidingLookupResult) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(result.ridingName).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                if !result.memberName.isEmpty {
                    Text(result.memberName).font(.subheadline).foregroundStyle(.secondary)
                    if !result.partyName.isEmpty {
                        Text(result.partyName).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(NSLocalizedString("riding.result.mpLoadingLater", comment: ""))
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)

            ContinueButton(label: NSLocalizedString("riding.setup.confirmButton", comment: "")) {
                postalCodeVM.confirm()
                HapticEngine.success()
                advance()
            }
        }
    }

    // MARK: - Screen 3: Topics

    private var topicsScreen: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                    .padding(.top, 60)

                VStack(spacing: 8) {
                    Text(NSLocalizedString("onboarding.topics.title", comment: ""))
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text(NSLocalizedString("onboarding.topics.subtitle", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(ParliamentaryTopic.all.prefix(12)) { topic in
                        TopicChip(
                            topic: topic,
                            isSelected: selectedTopics.contains(topic.id),
                            isDisabled: !selectedTopics.contains(topic.id) && selectedTopics.count >= 4
                        ) {
                            if selectedTopics.contains(topic.id) {
                                selectedTopics.remove(topic.id)
                            } else if selectedTopics.count < 4 {
                                selectedTopics.insert(topic.id)
                                HapticEngine.light()
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .padding(.bottom, 80)
            }

            ContinueButton(label: selectedTopics.isEmpty
                           ? NSLocalizedString("onboarding.skip", comment: "")
                           : String(format: NSLocalizedString("onboarding.topics.follow", comment: ""), selectedTopics.count)) {
                // Persist topic selections
                let store = TopicFollowStore.shared
                for id in selectedTopics { store.follow(id) }
                advance()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Screen 4: Notifications

    private var notificationsScreen: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(NSLocalizedString("onboarding.notifications.title", comment: ""))
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text(NSLocalizedString("onboarding.notifications.subtitle", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    NotificationPreviewRow(
                        icon: "person.fill",
                        text: NSLocalizedString("onboarding.notifications.preview1", comment: ""))
                    NotificationPreviewRow(
                        icon: "doc.text.fill",
                        text: NSLocalizedString("onboarding.notifications.preview2", comment: ""))
                    NotificationPreviewRow(
                        icon: "tag.fill",
                        text: NSLocalizedString("onboarding.notifications.preview3", comment: ""))
                }
                .padding(.horizontal, 8)

                Text(NSLocalizedString("onboarding.notifications.privacy", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()

            VStack(spacing: 12) {
                ContinueButton(label: NSLocalizedString("onboarding.notifications.allow", comment: "")) {
                    Task {
                        await notificationManager.requestAuthorization()
                        advance()
                    }
                }
                Button(NSLocalizedString("onboarding.notifications.skip", comment: "")) {
                    advance()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Screen 5: Promise

    private var promiseScreen: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(NSLocalizedString("onboarding.promise.title", comment: ""))
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)

                    Text(NSLocalizedString("onboarding.promise.subtitle", comment: ""))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    PromiseRow(icon: "building.columns.fill",
                               text: NSLocalizedString("onboarding.promise.point1", comment: ""))
                    if !selectedTopics.isEmpty {
                        PromiseRow(icon: "tag.fill",
                                   text: String(format: NSLocalizedString("onboarding.promise.point2", comment: ""),
                                                selectedTopics.count))
                    }
                    PromiseRow(icon: "lock.shield.fill",
                               text: NSLocalizedString("onboarding.promise.point3", comment: ""))
                }
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 32)
            Spacer()

            ContinueButton(label: NSLocalizedString("onboarding.promise.start", comment: "")) {
                complete()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Navigation helpers

    private func advance() {
        if page < totalPages - 1 {
            withAnimation { page += 1 }
        } else {
            complete()
        }
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: "epac.onboarding.completed")
        onComplete()
    }
}

// MARK: - Sub-components

private struct DataPointRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct NotificationPreviewRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PromiseRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.green)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TopicChip: View {
    let topic: ParliamentaryTopic
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(topic.localizedName)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 12)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .cornerRadius(12)
                .opacity(isDisabled ? 0.4 : 1)
        }
        .disabled(isDisabled)
        .accessibilityLabel(topic.localizedName)
        .accessibilityValue(isSelected ? "selected" : "not selected")
    }
}

private struct ContinueButton: View {
    enum Style { case primary, secondary }
    let label: String
    var style: Style = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding()
                .background(style == .primary ? Color.accentColor : Color.clear)
                .foregroundStyle(style == .primary ? .white : Color.accentColor)
                .cornerRadius(14)
                .overlay(style == .secondary
                         ? RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, lineWidth: 1.5)
                         : nil)
        }
    }
}
