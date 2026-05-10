//
//  OnboardingView.swift
//  epac
//
//  6-step onboarding flow (EPAC-621):
//  1. Welcome — one-line value prop "Canada's parliament, in your pocket"
//  2. Postal code — capture for riding lookup
//  3. MP confirm — "Your MP is X — follow?"
//  4. Topics — pick 1+ topics to follow
//  5. Notifications — per-category toggles
//  6. Home — land on home (triggered by completion)
//
//  Each step logs a telemetry event. Every step has a Skip path.
//

import SwiftData
import SwiftUI

@MainActor
struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var page = 0
    @State private var postalCodeVM = PostalCodeViewModel()
    @State private var selectedTopics: Set<String> = []
    @State private var notifPrefs = NotificationPreferenceStore.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(NotificationManager.self) private var notificationManager

    private let totalPages = 5

    var body: some View {
        TabView(selection: $page) {
            welcomeScreen.tag(0)
            postalCodeScreen.tag(1)
            mpConfirmScreen.tag(2)
            topicsScreen.tag(3)
            notificationsScreen.tag(4)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .overlay(alignment: .topTrailing) {
            if page < totalPages {
                Button(NSLocalizedString("onboarding.skip", comment: "")) {
                    Log.info("onboarding.step.\(page).skipped")
                    if page == totalPages - 1 {
                        complete()
                    } else {
                        advance()
                    }
                }
                .font(.epacSubheadline)
                .foregroundStyle(Color.epacText.secondary)
                .padding()
            }
        }
        .overlay(alignment: .bottom) {
            pageIndicator
                .padding(.bottom, 16)
        }
        .onChange(of: page) { _, newPage in
            Log.info("onboarding.step.\(newPage).viewed")
        }
        .onAppear {
            Log.info("onboarding.step.0.viewed")
        }
    }

    // MARK: - Page indicator

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalPages, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Color.epacBrand.accent : Color.epacText.secondary.opacity(0.3))
                    .frame(width: i == page ? 20 : 6, height: 6)
                    .animation(.spring(duration: 0.3), value: page)
            }
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeScreen: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: EpacSpacing.xl) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.epacBrand.accent)
                    .accessibilityHidden(true)

                VStack(spacing: EpacSpacing.m) {
                    Text(NSLocalizedString("onboarding.welcome.title", comment: ""))
                        .font(.epacDisplay.bold())
                        .multilineTextAlignment(.center)

                    Text(NSLocalizedString("onboarding.welcome.oneLineValueProp", comment: ""))
                        .font(.epacHeadline)
                        .foregroundStyle(Color.epacText.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: EpacSpacing.m) {
                    DataPointRow(icon: "text.document.fill",
                                 text: NSLocalizedString("onboarding.what.point1", comment: ""))
                    DataPointRow(icon: "checkmark.seal.fill",
                                 text: NSLocalizedString("onboarding.what.point2", comment: ""))
                    DataPointRow(icon: "person.2.badge.key.fill",
                                 text: NSLocalizedString("onboarding.what.point3", comment: ""))
                }
                .padding(.top, EpacSpacing.l)

                Text(NSLocalizedString("onboarding.what.trust", comment: ""))
                    .font(.epacCaption)
                    .foregroundStyle(Color.epacText.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, EpacSpacing.m)
            }
            .padding(.horizontal, EpacSpacing.xl)

            Spacer()

            ContinueButton(label: NSLocalizedString("onboarding.getStarted", comment: "")) {
                Log.info("onboarding.step.0.completed")
                advance()
            }
            .padding(.horizontal, EpacSpacing.l)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Step 2: Postal code

    private var postalCodeScreen: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: EpacSpacing.xl) {
                    VStack(spacing: EpacSpacing.m) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.epacBrand.accent)
                            .accessibilityHidden(true)
                            .padding(.top, 60)

                        Text(NSLocalizedString("riding.setup.title", comment: ""))
                            .font(.epacDisplay.bold())
                            .multilineTextAlignment(.center)

                        Text(NSLocalizedString("riding.setup.subtitle", comment: ""))
                            .font(.epacBody)
                            .foregroundStyle(Color.epacText.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: EpacSpacing.m) {
                        TextField(NSLocalizedString("riding.setup.placeholder", comment: ""),
                                  text: $postalCodeVM.postalCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color.epacSurface.elevated)
                            .cornerRadius(12)
                            .onSubmit { lookupAndAdvance() }

                        Button {
                            lookupAndAdvance()
                        } label: {
                            Group {
                                if postalCodeVM.isLoading {
                                    ProgressView().tint(Color.epacText.onAccent)
                                } else {
                                    Text(NSLocalizedString("riding.setup.lookupButton", comment: ""))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.epacBrand.accent)
                            .foregroundStyle(Color.epacText.onAccent)
                            .cornerRadius(12)
                        }
                        .disabled(postalCodeVM.isLoading ||
                                  postalCodeVM.postalCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, EpacSpacing.l)

                    if let error = postalCodeVM.errorMessage {
                        Text(error)
                            .font(.epacSubheadline)
                            .foregroundStyle(Color.epacStatus.destructive)
                            .padding(.horizontal, EpacSpacing.l)
                    }

                    Spacer(minLength: 80)
                }
            }

            ContinueButton(label: NSLocalizedString("onboarding.skip", comment: ""),
                           style: .secondary) {
                Log.info("onboarding.step.1.skipped")
                advance()
            }
            .padding(.horizontal, EpacSpacing.l)
            .padding(.bottom, 60)
        }
    }

    private func lookupAndAdvance() {
        Task {
            await postalCodeVM.lookup(modelContext: modelContext)
            if postalCodeVM.result != nil {
                Log.info("onboarding.step.1.completed")
                advance()
            }
        }
    }

    // MARK: - Step 3: MP Confirm

    private var mpConfirmScreen: some View {
        VStack(spacing: 0) {
            Spacer()
            if let result = postalCodeVM.result {
                VStack(spacing: EpacSpacing.xl) {
                    Image(systemName: "person.fill.viewfinder")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.epacBrand.accent)
                        .accessibilityHidden(true)

                    VStack(spacing: EpacSpacing.s) {
                        Text(String(format: NSLocalizedString("onboarding.mp.confirm.title", comment: ""),
                                    result.memberName.isEmpty ? result.ridingName : result.memberName))
                            .font(.epacDisplay.bold())
                            .multilineTextAlignment(.center)

                        Text(NSLocalizedString("onboarding.mp.confirm.subtitle", comment: ""))
                            .font(.epacHeadline)
                            .foregroundStyle(Color.epacText.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if !result.memberName.isEmpty {
                        VStack(spacing: EpacSpacing.xs) {
                            Text(result.ridingName)
                                .font(.epacSubheadline)
                                .foregroundStyle(Color.epacText.secondary)
                            Text(result.partyName)
                                .font(.epacCaption)
                                .foregroundStyle(Color.epacText.secondary)
                        }
                    } else {
                        Text(NSLocalizedString("riding.result.mpLoadingLater", comment: ""))
                            .font(.epacCaption)
                            .foregroundStyle(Color.epacText.secondary)
                    }
                }
                .padding(.horizontal, EpacSpacing.xl)
            } else {
                // If they reached here without a result (skipped step 2), show a generic message
                VStack(spacing: EpacSpacing.m) {
                    Text(NSLocalizedString("myMP.noMP.title", comment: ""))
                        .font(.epacDisplay.bold())
                    Text(NSLocalizedString("myMP.noMP.description", comment: ""))
                        .font(.epacBody)
                        .foregroundStyle(Color.epacText.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, EpacSpacing.xl)
            }
            Spacer()

            VStack(spacing: EpacSpacing.m) {
                if let result = postalCodeVM.result {
                    ContinueButton(label: NSLocalizedString("onboarding.mp.confirm.follow", comment: "")) {
                        postalCodeVM.confirm()
                        HapticEngine.success()
                        if !result.memberName.isEmpty {
                            let members = (try? modelContext.fetch(FetchDescriptor<ParliamentMember>())) ?? []
                            if let mp = members.first(where: {
                                $0.name.localizedCaseInsensitiveContains(result.memberName) ||
                                result.memberName.localizedCaseInsensitiveContains($0.lastName)
                            }) {
                                MemberFollowStore.shared.follow(mp.memberID)
                                Log.info("onboarding.step.2.mpFollowed memberID=\(mp.memberID)")
                            }
                        }
                        Log.info("onboarding.step.2.completed")
                        advance()
                    }
                }

                ContinueButton(label: NSLocalizedString("onboarding.mp.confirm.skip", comment: ""),
                               style: .secondary) {
                    Log.info("onboarding.step.2.skipped")
                    advance()
                }
            }
            .padding(.horizontal, EpacSpacing.l)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Step 4: Topics

    private var topicsScreen: some View {
        VStack(spacing: 0) {
            VStack(spacing: EpacSpacing.l) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.epacBrand.accent)
                    .accessibilityHidden(true)
                    .padding(.top, 60)

                VStack(spacing: EpacSpacing.s) {
                    Text(NSLocalizedString("onboarding.topics.title", comment: ""))
                        .font(.epacDisplay.bold())
                        .multilineTextAlignment(.center)
                    Text(NSLocalizedString("onboarding.topics.subtitle.v2", comment: ""))
                        .font(.epacSubheadline)
                        .foregroundStyle(Color.epacText.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, EpacSpacing.l)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: EpacSpacing.m) {
                    ForEach(ParliamentaryTopic.all.prefix(10)) { topic in
                        TopicChip(
                            topic: topic,
                            isSelected: selectedTopics.contains(topic.id)
                        ) {
                            if selectedTopics.contains(topic.id) {
                                selectedTopics.remove(topic.id)
                            } else {
                                selectedTopics.insert(topic.id)
                                HapticEngine.light()
                            }
                        }
                    }
                }
                .padding(.horizontal, EpacSpacing.l)
                .padding(.vertical, EpacSpacing.l)
                .padding(.bottom, 80)
            }

            ContinueButton(label: selectedTopics.isEmpty
                           ? NSLocalizedString("onboarding.skip", comment: "")
                           : String(format: NSLocalizedString("onboarding.topics.follow", comment: ""),
                                    selectedTopics.count)) {
                if !selectedTopics.isEmpty {
                    FollowTopic.live().execute(topicIDs: selectedTopics)
                    Log.info("onboarding.step.3.completed topicsFollowed=\(selectedTopics.count)")
                } else {
                    Log.info("onboarding.step.3.skipped")
                }
                advance()
            }
            .padding(.horizontal, EpacSpacing.l)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Step 5: Notifications

    private var notificationsScreen: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: EpacSpacing.xl) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.epacBrand.accent)
                    .accessibilityHidden(true)

                VStack(spacing: EpacSpacing.s) {
                    Text(NSLocalizedString("onboarding.notifications.title", comment: ""))
                        .font(.epacDisplay.bold())
                        .multilineTextAlignment(.center)
                    Text(NSLocalizedString("onboarding.notifications.subtitle.v2", comment: ""))
                        .font(.epacSubheadline)
                        .foregroundStyle(Color.epacText.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: EpacSpacing.m) {
                    Toggle(NSLocalizedString("notifications.category.dailyDigest", comment: ""),
                           isOn: $notifPrefs.dailyDigest)
                    .font(.epacSubheadline)
                    Toggle(NSLocalizedString("notifications.category.mpVotes", comment: ""),
                           isOn: $notifPrefs.followedMPVotes)
                    .font(.epacSubheadline)
                    Toggle(NSLocalizedString("notifications.category.billStatus", comment: ""),
                           isOn: $notifPrefs.followedBillStatusChanges)
                    .font(.epacSubheadline)
                }
                .padding(EpacSpacing.m)
                .background(Color.epacSurface.elevated)
                .cornerRadius(12)
                .padding(.horizontal, EpacSpacing.s)

                Text(NSLocalizedString("onboarding.notifications.privacy", comment: ""))
                    .font(.epacCaption)
                    .foregroundStyle(Color.epacText.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, EpacSpacing.xl)
            Spacer()

            VStack(spacing: EpacSpacing.m) {
                ContinueButton(label: NSLocalizedString("onboarding.notifications.allow", comment: "")) {
                    Task {
                        await notificationManager.requestAuthorization()
                        Log.info("onboarding.step.4.completed notifAllowed=true")
                        complete()
                    }
                }
                Button(NSLocalizedString("onboarding.notifications.skip", comment: "")) {
                    Log.info("onboarding.step.4.skipped")
                    complete()
                }
                .font(.epacSubheadline)
                .foregroundStyle(Color.epacText.secondary)
            }
            .padding(.horizontal, EpacSpacing.l)
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
        Log.info("onboarding.completed")
        UserDefaults.standard.set(true, forKey: "epac.onboarding.completed")
        onComplete()
    }
}

// MARK: - Sub-components

private struct DataPointRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: EpacSpacing.m) {
            Image(systemName: icon)
                .font(.epacBody)
                .foregroundStyle(Color.epacBrand.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.epacSubheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TopicChip: View {
    let topic: ParliamentaryTopic
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(topic.localizedName)
                .font(.epacSubheadline.weight(isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, EpacSpacing.m)
                .background(isSelected ? Color.epacBrand.accent : Color.epacSurface.elevated)
                .foregroundStyle(isSelected ? Color.epacText.onAccent : Color.epacText.primary)
                .cornerRadius(12)
        }
        .accessibilityLabel(topic.localizedName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                .font(.epacBody.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding()
                .background(style == .primary ? Color.epacBrand.accent : Color.clear)
                .foregroundStyle(style == .primary ? Color.epacText.onAccent : Color.epacBrand.accent)
                .cornerRadius(14)
                .overlay(style == .secondary
                         ? RoundedRectangle(cornerRadius: 14).strokeBorder(Color.epacBrand.accent, lineWidth: 1.5)
                         : nil)
        }
    }
}
