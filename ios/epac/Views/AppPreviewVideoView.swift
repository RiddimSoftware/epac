//
//  AppPreviewVideoView.swift
//  epac
//
//  Hidden App Store preview route. It is shown only for marketing capture launch
//  arguments so production users never see fixture content.
//

import SwiftUI

private enum AppPreviewVideoSpec {
    static let initialSceneIndex = 0
    static let gradientStart: (red: Double, green: Double, blue: Double) = (0.06, 0.08, 0.10)
    static let gradientMiddle: (red: Double, green: Double, blue: Double) = (0.10, 0.18, 0.20)
    static let gradientEnd: (red: Double, green: Double, blue: Double) = (0.19, 0.17, 0.13)
    static let rootSpacing: CGFloat = 18
    static let titleSpacing: CGFloat = 8
    static let appNameFontSize: CGFloat = 38
    static let headlineFontSize: CGFloat = 27
    static let headlineLineLimit = 2
    static let headlineMinimumScaleFactor: CGFloat = 0.75
    static let titleHorizontalPadding: CGFloat = 26
    static let pageIndicatorSpacing: CGFloat = 7
    static let pageIndicatorInactiveOpacity = 0.35
    static let pageIndicatorBottomPadding: CGFloat = 8
    static let rootTopPadding: CGFloat = 22
    static let rootBottomPadding: CGFloat = 14
    static let phoneContentSpacing: CGFloat = 18
    static let phoneTitleFontSize: CGFloat = 20
    static let phoneActionFontSize: CGFloat = 19
    static let tabItemSpacing: CGFloat = 4
    static let tabIconFontSize: CGFloat = 18
    static let tabTitleFontSize: CGFloat = 10
    static let tabBarTopPadding: CGFloat = 10
    static let dividerHeight: CGFloat = 0.5
    static let phoneContentPadding: CGFloat = 22
    static let phoneBorderOpacity = 0.45
    static let phoneShadowOpacity = 0.32
    static let statusBarTimeFontSize: CGFloat = 13
    static let statusBarFontSize: CGFloat = 12
    static let statusBarHorizontalPadding: CGFloat = 28
    static let statusBarTopPadding: CGFloat = 14
    static let statusBarBottomPadding: CGFloat = 10
    static let cardSpacing: CGFloat = 16
    static let rowSpacing: CGFloat = 10
    static let memberTextSpacing: CGFloat = 3
    static let detailGroupSpacing: CGFloat = 12
    static let debateLineLimit = 3
    static let lobbyingSpacing: CGFloat = 14
    static let fixtureSpacing: CGFloat = 13
    static let contactButtonSpacing: CGFloat = 8
    static let contactButtonVerticalPadding: CGFloat = 11
    static let contactButtonCornerRadius: CGFloat = 10
    static let activityIconWidth: CGFloat = 26
    static let cardPadding: CGFloat = 16
    static let cardCornerRadius: CGFloat = 14
    static let sourceBadgeLineLimit = 2
    static let speakerAvatarOpacity = 0.18
    static let speakerAvatarSize: CGFloat = 38
    static let speakerTextSpacing: CGFloat = 2
    static let speechBubbleLineLimit = 4
    static let speechBubblePadding: CGFloat = 12
    static let speechBubbleOpacity = 0.10
    static let speechBubbleCornerRadius: CGFloat = 12
    static let votePillHorizontalPadding: CGFloat = 10
    static let votePillVerticalPadding: CGFloat = 6
    static let communicationSpacing: CGFloat = 4
    static let communicationVerticalPadding: CGFloat = 5
    static let fieldSpacing: CGFloat = 5
    static let shortSceneDurationNanoseconds: UInt64 = 3_000_000_000
    static let mediumSceneDurationNanoseconds: UInt64 = 4_000_000_000
    static let standardSceneDurationNanoseconds: UInt64 = 5_000_000_000
}

struct AppPreviewVideoView: View {
    private let scenes = AppPreviewScene.scenes
    private let forcedSceneIndex: Int?
    @State private var selectedSceneIndex: Int

    init() {
        let forcedSceneIndex = AppPreviewScene.requestedSceneIndex
        self.forcedSceneIndex = forcedSceneIndex
        self._selectedSceneIndex = State(initialValue: forcedSceneIndex ?? AppPreviewVideoSpec.initialSceneIndex)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(
                        red: AppPreviewVideoSpec.gradientStart.red,
                        green: AppPreviewVideoSpec.gradientStart.green,
                        blue: AppPreviewVideoSpec.gradientStart.blue
                    ),
                    Color(
                        red: AppPreviewVideoSpec.gradientMiddle.red,
                        green: AppPreviewVideoSpec.gradientMiddle.green,
                        blue: AppPreviewVideoSpec.gradientMiddle.blue
                    ),
                    Color(
                        red: AppPreviewVideoSpec.gradientEnd.red,
                        green: AppPreviewVideoSpec.gradientEnd.green,
                        blue: AppPreviewVideoSpec.gradientEnd.blue
                    )
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: AppPreviewVideoSpec.rootSpacing) {
                VStack(alignment: .leading, spacing: AppPreviewVideoSpec.titleSpacing) {
                    Text("epac")
                        .font(.system(size: AppPreviewVideoSpec.appNameFontSize, weight: .bold, design: .rounded))
                    Text(scenes[selectedSceneIndex].headline)
                        .font(.system(size: AppPreviewVideoSpec.headlineFontSize, weight: .semibold, design: .rounded))
                        .lineLimit(AppPreviewVideoSpec.headlineLineLimit)
                        .minimumScaleFactor(AppPreviewVideoSpec.headlineMinimumScaleFactor)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppPreviewVideoSpec.titleHorizontalPadding)

                AppPreviewPhoneFrame(scene: scenes[selectedSceneIndex])
                    .id(selectedSceneIndex)
                    .accessibilityIdentifier(scenes[selectedSceneIndex].identifier)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                HStack(spacing: AppPreviewVideoSpec.pageIndicatorSpacing) {
                    ForEach(scenes.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == selectedSceneIndex ? Color.white : Color.white.opacity(AppPreviewVideoSpec.pageIndicatorInactiveOpacity))
                            .frame(
                                width: index == selectedSceneIndex ? EpacMedia.pageDotActiveWidth : EpacMedia.pageDotInactiveWidth,
                                height: EpacMedia.pageDotHeight
                            )
                            .animation(.easeInOut(duration: EpacAnimation.pageIndicator), value: selectedSceneIndex)
                    }
                }
                .padding(.bottom, AppPreviewVideoSpec.pageIndicatorBottomPadding)
            }
            .padding(.top, AppPreviewVideoSpec.rootTopPadding)
            .padding(.bottom, AppPreviewVideoSpec.rootBottomPadding)

            if AppPreviewScene.testProbesEnabled {
                VStack(spacing: EpacMedia.previewProbeSize) {
                    ForEach(AppPreviewScene.requiredAccessibilityIdentifiers, id: \.self) { identifier in
                        Text(identifier)
                            .font(.system(size: EpacMedia.previewProbeSize))
                            .frame(width: EpacMedia.previewProbeSize, height: EpacMedia.previewProbeSize)
                            .accessibilityLabel(identifier)
                            .accessibilityIdentifier(identifier)
                    }
                }
                .frame(width: EpacMedia.previewProbeSize, height: EpacMedia.previewProbeSize)
                .clipped()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard AppEnvironment.isAppPreviewManualSequence else { return }
            advanceScene()
        }
        .accessibilityIdentifier("app-preview-root")
        .preferredColorScheme(.light)
        .task {
            guard forcedSceneIndex == nil, !AppEnvironment.isAppPreviewManualSequence else { return }
            for index in scenes.indices.dropFirst() {
                try? await Task.sleep(nanoseconds: scenes[index - 1].durationNanoseconds)
                advanceScene()
            }
            if let finalScene = scenes.last {
                try? await Task.sleep(nanoseconds: finalScene.durationNanoseconds)
            }
        }
    }

    private func advanceScene() {
        guard selectedSceneIndex < scenes.count - 1 else { return }
        if AppEnvironment.isAppPreviewManualSequence {
            selectedSceneIndex += 1
            return
        }
        withAnimation(.easeInOut(duration: EpacAnimation.previewSceneTransition)) {
            selectedSceneIndex += 1
        }
    }
}

private struct AppPreviewPhoneFrame: View {
    let scene: AppPreviewScene

    var body: some View {
        VStack(spacing: 0) {
            phoneStatusBar
            VStack(spacing: AppPreviewVideoSpec.phoneContentSpacing) {
                HStack {
                    Label(scene.tabTitle, systemImage: scene.systemImage)
                        .font(.system(size: AppPreviewVideoSpec.phoneTitleFontSize, weight: .semibold))
                    Spacer()
                    Image(systemName: "star.circle")
                        .font(.system(size: AppPreviewVideoSpec.phoneActionFontSize, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                sceneBody

                Spacer(minLength: 0)

                HStack {
                    ForEach(AppPreviewTab.allCases) { tab in
                        VStack(spacing: AppPreviewVideoSpec.tabItemSpacing) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: AppPreviewVideoSpec.tabIconFontSize, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: AppPreviewVideoSpec.tabTitleFontSize, weight: .medium))
                        }
                        .foregroundStyle(tab.title == scene.tabTitle ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, AppPreviewVideoSpec.tabBarTopPadding)
                .overlay(Rectangle().fill(Color.appDivider).frame(height: AppPreviewVideoSpec.dividerHeight), alignment: .top)
            }
            .padding(AppPreviewVideoSpec.phoneContentPadding)
        }
        .frame(width: EpacMedia.previewPhoneWidth, height: EpacMedia.previewPhoneHeight)
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: EpacMedia.previewPhoneCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EpacMedia.previewPhoneCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(AppPreviewVideoSpec.phoneBorderOpacity), lineWidth: EpacMedia.previewPhoneBorderWidth)
        )
        .shadow(
            color: .black.opacity(AppPreviewVideoSpec.phoneShadowOpacity),
            radius: EpacMedia.previewPhoneShadowRadius,
            x: 0,
            y: EpacMedia.previewPhoneShadowYOffset
        )
    }

    private var phoneStatusBar: some View {
        HStack {
            Text("9:41")
                .font(.system(size: AppPreviewVideoSpec.statusBarTimeFontSize, weight: .semibold))
            Spacer()
            Image(systemName: "wifi")
            Image(systemName: "battery.100")
        }
        .font(.system(size: AppPreviewVideoSpec.statusBarFontSize, weight: .semibold))
        .padding(.horizontal, AppPreviewVideoSpec.statusBarHorizontalPadding)
        .padding(.top, AppPreviewVideoSpec.statusBarTopPadding)
        .padding(.bottom, AppPreviewVideoSpec.statusBarBottomPadding)
    }

    @ViewBuilder
    private var sceneBody: some View {
        switch scene.kind {
        case .homeFeed:
            previewCard {
                VStack(alignment: .leading, spacing: AppPreviewVideoSpec.cardSpacing) {
                    sourceBadge("Today in Parliament")
                        .accessibilityIdentifier("home-feed-scroll")
                    Text("Your MP. Everything they do.")
                        .font(.headline)
                        .accessibilityIdentifier("home-feed-today-card")
                    activityRow(
                        icon: "mic.fill",
                        title: "Spoke in debate",
                        detail: "Food price transparency",
                        accessibilityIdentifier: "home-feed-my-mp-link"
                    )
                    activityRow(icon: "checkmark.seal.fill", title: "Voted Yea", detail: "Division No. 926")
                    activityRow(icon: "doc.text.fill", title: "Bill C-226", detail: "Second reading")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home-feed-scroll")
            }
        case .mpProfile:
            previewCard {
                VStack(alignment: .leading, spacing: AppPreviewVideoSpec.cardSpacing) {
                    sourceBadge("House of Commons member profile")
                        .accessibilityIdentifier("mp-profile-scroll")
                    HStack(spacing: AppPreviewVideoSpec.rowSpacing) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: AppPreviewVideoSpec.memberTextSpacing) {
                            Text("Gurbux Saini")
                                .font(.headline)
                            Text("Fleetwood-Port Kells - Lib.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: AppPreviewVideoSpec.detailGroupSpacing) {
                        voteRow(title: "Division No. 926", detail: "Motion negatived", vote: "Yea", color: .appPositive, accessibilityIdentifier: "mp-profile-vote-row-0")
                            .accessibilityElement(children: .combine)
                        activityRow(icon: "dollarsign.circle.fill", title: "Expenses", detail: "Quarterly House disclosures")
                        activityRow(icon: "envelope.fill", title: "Contact", detail: "Official Hill and constituency offices")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("mp-profile-civic-list")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("mp-profile-scroll")
            }
        case .debate:
            VStack(spacing: AppPreviewVideoSpec.detailGroupSpacing) {
                previewCard {
                    VStack(alignment: .leading, spacing: AppPreviewVideoSpec.detailGroupSpacing) {
                        sourceBadge("House of Commons Debates, January 27, 2026")
                            .accessibilityIdentifier("parliament-sitting-row-0")
                        Text("National Framework for Food Price Transparency Act")
                            .font(.headline)
                            .lineLimit(AppPreviewVideoSpec.debateLineLimit)
                            .accessibilityIdentifier("speech-view-scroll")
                        speakerRow(name: "Gurbux Saini", riding: "Fleetwood-Port Kells", party: "Lib.")
                        speechBubble("Bill C-226 would establish a national framework to improve food price transparency.")
                    }
                }
                previewCard {
                    speakerRow(name: "Andrew Lawton", riding: "Elgin-St. Thomas-London South", party: "CPC")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("speech-view-scroll")
        case .lobbying:
            previewCard {
                VStack(alignment: .leading, spacing: AppPreviewVideoSpec.lobbyingSpacing) {
                    sourceBadge("Office of the Commissioner of Lobbying")
                        .accessibilityIdentifier("lobbying-list-scroll")
                    Text("Who's influencing them?")
                        .font(.headline)
                        .accessibilityIdentifier("accountability-lobbying-link")
                    communicationRow(org: "Registered communication", topic: "Subject matters from public registry")
                    communicationRow(org: "Designated office holder", topic: "Matched to member profile")
                    communicationRow(org: "Source record", topic: "Open in Commissioner registry")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("lobbying-list-scroll")
            }
        case .voteDetail:
            previewCard {
                VStack(alignment: .leading, spacing: AppPreviewVideoSpec.fixtureSpacing) {
                    sourceBadge("House of Commons recorded divisions")
                        .accessibilityIdentifier("vote-detail-scroll")
                    Text("They said it. Then voted against it.")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: AppPreviewVideoSpec.rowSpacing) {
                        voteRow(title: "Division No. 926", detail: "Motion negatived", vote: "Yea", color: .appPositive, accessibilityIdentifier: "vote-list-row-0")
                            .accessibilityElement(children: .combine)
                        voteRow(title: "Government", detail: "Most Liberal MPs", vote: "Nay", color: .appDestructive, accessibilityIdentifier: "vote-detail-mp-list")
                            .accessibilityElement(children: .combine)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("vote-detail-mp-list")
                    speechBubble("Related debate: grocery price transparency and affordability.")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("vote-detail-scroll")
            }
        case .contact:
            previewCard {
                VStack(alignment: .leading, spacing: AppPreviewVideoSpec.fixtureSpacing) {
                    sourceBadge("House of Commons member contact")
                        .accessibilityIdentifier("contact-sheet-scroll")
                    Text("Contact your MP")
                        .font(.headline)
                    field("Subject", value: "Bill C-226")
                    field("Message", value: "I am writing about the grocery price transparency debate.")
                        .accessibilityIdentifier("contact-message-field")
                    HStack(spacing: AppPreviewVideoSpec.contactButtonSpacing) {
                        Image(systemName: "envelope.fill")
                        Text("Open Mail")
                    }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppPreviewVideoSpec.contactButtonVerticalPadding)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: AppPreviewVideoSpec.contactButtonCornerRadius, style: .continuous))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("mp-profile-contact-button")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("contact-sheet-scroll")
            }
        }
    }

    private func previewCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppPreviewVideoSpec.cardPadding)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppPreviewVideoSpec.cardCornerRadius, style: .continuous))
    }

    private func sourceBadge(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.seal.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .lineLimit(AppPreviewVideoSpec.sourceBadgeLineLimit)
    }

    private func speakerRow(name: String, riding: String, party: String) -> some View {
        HStack(spacing: AppPreviewVideoSpec.rowSpacing) {
            Circle()
                .fill(Color.accentColor.opacity(AppPreviewVideoSpec.speakerAvatarOpacity))
                .frame(width: AppPreviewVideoSpec.speakerAvatarSize, height: AppPreviewVideoSpec.speakerAvatarSize)
                .overlay(Text(String(name.prefix(1))).font(.headline).foregroundStyle(Color.accentColor))
            VStack(alignment: .leading, spacing: AppPreviewVideoSpec.speakerTextSpacing) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Text("\(riding) - \(party)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(AppPreviewVideoSpec.sourceBadgeLineLimit)
            }
        }
    }

    private func speechBubble(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .lineLimit(AppPreviewVideoSpec.speechBubbleLineLimit)
            .padding(AppPreviewVideoSpec.speechBubblePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(AppPreviewVideoSpec.speechBubbleOpacity))
            .clipShape(RoundedRectangle(cornerRadius: AppPreviewVideoSpec.speechBubbleCornerRadius, style: .continuous))
    }

    private func voteRow(title: String, detail: String, vote: String, color: Color, accessibilityIdentifier: String? = nil) -> some View {
        HStack(spacing: AppPreviewVideoSpec.rowSpacing) {
            VStack(alignment: .leading, spacing: AppPreviewVideoSpec.speakerTextSpacing) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(vote)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, AppPreviewVideoSpec.votePillHorizontalPadding)
                .padding(.vertical, AppPreviewVideoSpec.votePillVerticalPadding)
                .background(color)
                .clipShape(Capsule())
        }
        .accessibilityElement(children: .combine)
        .optionalAccessibilityIdentifier(accessibilityIdentifier)
    }

    private func progressRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
        }
    }

    private func activityRow(icon: String, title: String, detail: String, accessibilityIdentifier: String? = nil) -> some View {
        HStack(spacing: AppPreviewVideoSpec.rowSpacing) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: AppPreviewVideoSpec.activityIconWidth)
            VStack(alignment: .leading, spacing: AppPreviewVideoSpec.speakerTextSpacing) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .optionalAccessibilityIdentifier(accessibilityIdentifier)
    }

    private func communicationRow(org: String, topic: String) -> some View {
        VStack(alignment: .leading, spacing: AppPreviewVideoSpec.communicationSpacing) {
            Text(org)
                .font(.subheadline.weight(.semibold))
            Text(topic)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppPreviewVideoSpec.communicationVerticalPadding)
    }

    private func timelineStage(_ title: String, done: Bool) -> some View {
        HStack(spacing: AppPreviewVideoSpec.rowSpacing) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.appPositive : Color.appNeutral)
            Text(title)
                .font(.subheadline)
            Spacer()
        }
    }

    private func field(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: AppPreviewVideoSpec.fieldSpacing) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .lineLimit(AppPreviewVideoSpec.debateLineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppPreviewVideoSpec.rowSpacing)
                .background(Color.appBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppPreviewVideoSpec.contactButtonCornerRadius, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AppPreviewScene {
    enum Kind {
        case homeFeed
        case mpProfile
        case debate
        case lobbying
        case voteDetail
        case contact
    }

    let headline: String
    let tabTitle: String
    let systemImage: String
    let kind: Kind
    let durationNanoseconds: UInt64

    var identifier: String {
        switch kind {
        case .homeFeed: return "home-feed-preview-scene"
        case .mpProfile: return "mp-profile-preview-scene"
        case .debate: return "speech-view-preview-scene"
        case .lobbying: return "lobbying-preview-scene"
        case .voteDetail: return "vote-detail-preview-scene"
        case .contact: return "contact-preview-scene"
        }
    }

    static let scenes: [AppPreviewScene] = [
        AppPreviewScene(
            headline: "Your MP. Everything they do.",
            tabTitle: "Home",
            systemImage: "house.fill",
            kind: .homeFeed,
            durationNanoseconds: AppPreviewVideoSpec.shortSceneDurationNanoseconds
        ),
        AppPreviewScene(
            headline: "Every vote. Every detail.",
            tabTitle: "Members",
            systemImage: "person.2.fill",
            kind: .mpProfile,
            durationNanoseconds: AppPreviewVideoSpec.standardSceneDurationNanoseconds
        ),
        AppPreviewScene(
            headline: "Hansard. Finally readable.",
            tabTitle: "Parliament",
            systemImage: "building.columns.fill",
            kind: .debate,
            durationNanoseconds: AppPreviewVideoSpec.standardSceneDurationNanoseconds
        ),
        AppPreviewScene(
            headline: "Who's influencing them?",
            tabTitle: "Members",
            systemImage: "person.text.rectangle.fill",
            kind: .lobbying,
            durationNanoseconds: AppPreviewVideoSpec.mediumSceneDurationNanoseconds
        ),
        AppPreviewScene(
            headline: "They said it. Then voted against it.",
            tabTitle: "Accountability",
            systemImage: "checklist.checked",
            kind: .voteDetail,
            durationNanoseconds: AppPreviewVideoSpec.standardSceneDurationNanoseconds
        ),
        AppPreviewScene(
            headline: "Democracy. One tap.",
            tabTitle: "Members",
            systemImage: "envelope.fill",
            kind: .contact,
            durationNanoseconds: AppPreviewVideoSpec.shortSceneDurationNanoseconds
        )
    ]

    static var requestedSceneIndex: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--app-preview-scene-index"),
              arguments.indices.contains(flagIndex + 1),
              let sceneIndex = Int(arguments[flagIndex + 1]),
              scenes.indices.contains(sceneIndex) else {
            return nil
        }
        return sceneIndex
    }

    static var testProbesEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--app-preview-test-probes")
    }

    static let requiredAccessibilityIdentifiers = [
        "home-feed-scroll",
        "home-feed-today-card",
        "home-feed-my-mp-link",
        "mp-profile-scroll",
        "mp-profile-civic-list",
        "mp-profile-vote-row-0",
        "speech-view-scroll",
        "parliament-sitting-row-0",
        "lobbying-list-scroll",
        "accountability-lobbying-link",
        "vote-detail-scroll",
        "vote-list-row-0",
        "vote-detail-mp-list",
        "mp-profile-contact-button",
        "contact-sheet-scroll",
        "contact-message-field"
    ]

}

private enum AppPreviewTab: CaseIterable, Identifiable {
    case home
    case parliament
    case members
    case accountability
    case search

    var id: String { title }

    var title: String {
        switch self {
        case .home: return "Home"
        case .parliament: return "Parliament"
        case .members: return "Members"
        case .accountability: return "Accountability"
        case .search: return "Search"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .parliament: return "building.columns.fill"
        case .members: return "person.2.fill"
        case .accountability: return "checklist"
        case .search: return "magnifyingglass"
        }
    }
}

private struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

private extension View {
    func optionalAccessibilityIdentifier(_ identifier: String?) -> some View {
        modifier(OptionalAccessibilityIdentifier(identifier: identifier))
    }
}

#Preview {
    AppPreviewVideoView()
}
