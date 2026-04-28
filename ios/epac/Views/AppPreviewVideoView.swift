//
//  AppPreviewVideoView.swift
//  epac
//
//  Hidden App Store preview route. It is shown only for marketing capture launch
//  arguments so production users never see fixture content.
//

import SwiftUI

struct AppPreviewVideoView: View {
    private let scenes = AppPreviewScene.scenes
    @State private var selectedSceneIndex = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.10),
                    Color(red: 0.10, green: 0.18, blue: 0.20),
                    Color(red: 0.19, green: 0.17, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("epac")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text(scenes[selectedSceneIndex].headline)
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 26)

                AppPreviewPhoneFrame(scene: scenes[selectedSceneIndex])
                    .id(selectedSceneIndex)
                    .accessibilityIdentifier(scenes[selectedSceneIndex].identifier)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                HStack(spacing: 7) {
                    ForEach(scenes.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == selectedSceneIndex ? Color.white : Color.white.opacity(0.35))
                            .frame(width: index == selectedSceneIndex ? 26 : 8, height: 8)
                            .animation(.easeInOut(duration: 0.35), value: selectedSceneIndex)
                    }
                }
                .padding(.bottom, 8)
            }
            .padding(.top, 22)
            .padding(.bottom, 14)
        }
        .accessibilityIdentifier("app-preview-root")
        .preferredColorScheme(.light)
        .task {
            for index in scenes.indices.dropFirst() {
                try? await Task.sleep(nanoseconds: scenes[index - 1].durationNanoseconds)
                withAnimation(.easeInOut(duration: 0.65)) {
                    selectedSceneIndex = index
                }
            }
            if let finalScene = scenes.last {
                try? await Task.sleep(nanoseconds: finalScene.durationNanoseconds)
            }
        }
    }
}

private struct AppPreviewPhoneFrame: View {
    let scene: AppPreviewScene

    var body: some View {
        VStack(spacing: 0) {
            phoneStatusBar
            VStack(spacing: 18) {
                HStack {
                    Label(scene.tabTitle, systemImage: scene.systemImage)
                        .font(.system(size: 20, weight: .semibold))
                    Spacer()
                    Image(systemName: "bell.badge")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                sceneBody

                Spacer(minLength: 0)

                HStack {
                    ForEach(AppPreviewTab.allCases) { tab in
                        VStack(spacing: 4) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 18, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(tab.title == scene.tabTitle ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 10)
                .overlay(Rectangle().fill(Color.appDivider).frame(height: 0.5), alignment: .top)
            }
            .padding(22)
        }
        .frame(width: 338, height: 650)
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 3)
        )
        .shadow(color: .black.opacity(0.32), radius: 28, x: 0, y: 22)
    }

    private var phoneStatusBar: some View {
        HStack {
            Text("9:41")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Image(systemName: "wifi")
            Image(systemName: "battery.100")
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var sceneBody: some View {
        switch scene.kind {
        case .homeFeed:
            previewCard {
                VStack(alignment: .leading, spacing: 16) {
                    sourceBadge("Today in Parliament")
                    Text("Your MP. Everything they do.")
                        .font(.headline)
                    activityRow(icon: "mic.fill", title: "Spoke in debate", detail: "Food price transparency")
                    activityRow(icon: "checkmark.seal.fill", title: "Voted Yea", detail: "Division No. 926")
                    activityRow(icon: "doc.text.fill", title: "Bill C-226", detail: "Second reading")
                }
                .accessibilityIdentifier("home-feed-today-cards")
            }
        case .mpProfile:
            previewCard {
                VStack(alignment: .leading, spacing: 16) {
                    sourceBadge("House of Commons member profile")
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Gurbux Saini")
                                .font(.headline)
                            Text("Fleetwood-Port Kells - Lib.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    speechBubble("Every word. Every vote.")
                    voteRow(title: "Division No. 926", detail: "Motion negatived", vote: "Yea", color: .appPositive)
                }
                .accessibilityIdentifier("mp-profile-activity")
            }
        case .debate:
            VStack(spacing: 12) {
                previewCard {
                    VStack(alignment: .leading, spacing: 12) {
                        sourceBadge("House of Commons Debates, January 27, 2026")
                        Text("National Framework for Food Price Transparency Act")
                            .font(.headline)
                            .lineLimit(3)
                        speakerRow(name: "Gurbux Saini", riding: "Fleetwood-Port Kells", party: "Lib.")
                        speechBubble("Bill C-226 would establish a national framework to improve food price transparency.")
                    }
                    .accessibilityIdentifier("speech-view-bubbles")
                }
                previewCard {
                    speakerRow(name: "Andrew Lawton", riding: "Elgin-St. Thomas-London South", party: "CPC")
                }
            }
        case .lobbying:
            previewCard {
                VStack(alignment: .leading, spacing: 14) {
                    sourceBadge("Office of the Commissioner of Lobbying")
                    Text("Who's influencing them?")
                        .font(.headline)
                    communicationRow(org: "Registered communication", topic: "Subject matters from public registry")
                    communicationRow(org: "Designated office holder", topic: "Matched to member profile")
                    communicationRow(org: "Source record", topic: "Open in Commissioner registry")
                }
                .accessibilityIdentifier("lobbying-communications-list")
            }
        case .voteDetail:
            previewCard {
                VStack(alignment: .leading, spacing: 13) {
                    sourceBadge("House of Commons recorded divisions")
                    Text("They said it. Then voted against it.")
                        .font(.headline)
                    voteRow(title: "Division No. 926", detail: "Motion negatived", vote: "Yea", color: .appPositive)
                    voteRow(title: "Government", detail: "Most Liberal MPs", vote: "Nay", color: .appDestructive)
                    speechBubble("Related debate: grocery price transparency and affordability.")
                }
                .accessibilityIdentifier("vote-detail-breakdown")
            }
        case .contact:
            previewCard {
                VStack(alignment: .leading, spacing: 13) {
                    sourceBadge("House of Commons member contact")
                    Text("Contact your MP")
                        .font(.headline)
                    field("Subject", value: "Bill C-226")
                    field("Message", value: "I am writing about the grocery price transparency debate.")
                    Label("Open Mail", systemImage: "envelope.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .accessibilityIdentifier("contact-compose-sheet")
            }
        }
    }

    private func previewCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func sourceBadge(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.seal.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .lineLimit(2)
    }

    private func speakerRow(name: String, riding: String, party: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 38, height: 38)
                .overlay(Text(String(name.prefix(1))).font(.headline).foregroundStyle(Color.accentColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Text("\(riding) - \(party)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func speechBubble(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .lineLimit(4)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func voteRow(title: String, detail: String, vote: String, color: Color) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
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
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(color)
                .clipShape(Capsule())
        }
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

    private func activityRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func communicationRow(org: String, topic: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(org)
                .font(.subheadline.weight(.semibold))
            Text(topic)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
    }

    private func timelineStage(_ title: String, done: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.appPositive : Color.appNeutral)
            Text(title)
                .font(.subheadline)
            Spacer()
        }
    }

    private func field(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.appBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
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
            durationNanoseconds: 5_000_000_000
        ),
        AppPreviewScene(
            headline: "Every word. Every vote.",
            tabTitle: "Members",
            systemImage: "person.2.fill",
            kind: .mpProfile,
            durationNanoseconds: 6_000_000_000
        ),
        AppPreviewScene(
            headline: "Hansard. Finally readable.",
            tabTitle: "Parliament",
            systemImage: "building.columns.fill",
            kind: .debate,
            durationNanoseconds: 6_000_000_000
        ),
        AppPreviewScene(
            headline: "Who's influencing them?",
            tabTitle: "Members",
            systemImage: "person.text.rectangle.fill",
            kind: .lobbying,
            durationNanoseconds: 5_000_000_000
        ),
        AppPreviewScene(
            headline: "They said it. Then voted against it.",
            tabTitle: "Accountability",
            systemImage: "checklist.checked",
            kind: .voteDetail,
            durationNanoseconds: 5_000_000_000
        ),
        AppPreviewScene(
            headline: "Democracy. One tap.",
            tabTitle: "Members",
            systemImage: "envelope.fill",
            kind: .contact,
            durationNanoseconds: 3_000_000_000
        )
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

#Preview {
    AppPreviewVideoView()
}
