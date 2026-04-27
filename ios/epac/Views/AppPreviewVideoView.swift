//
//  AppPreviewVideoView.swift
//  epac
//
//  Hidden App Store preview route for EPAC-110. It is shown only when the app
//  launches with -AppPreviewVideo so production users never see fixture content.
//

import SwiftUI

struct AppPreviewVideoView: View {
    private let scenes = AppPreviewScene.scenes
    private let sceneDuration: UInt64 = 4_700_000_000
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
        .preferredColorScheme(.light)
        .task {
            for index in scenes.indices.dropFirst() {
                try? await Task.sleep(nanoseconds: sceneDuration)
                withAnimation(.easeInOut(duration: 0.65)) {
                    selectedSceneIndex = index
                }
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
        case .postalCode:
            previewCard {
                VStack(alignment: .leading, spacing: 16) {
                    sourceBadge("Elections Canada riding lookup")
                    Text("M5V 0C7")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Spadina-Harbourfront")
                                .font(.headline)
                            Text("Find the representative for your riding.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    progressRow(label: "Riding matched", value: "Ready")
                }
            }
        case .debate:
            VStack(spacing: 12) {
                previewCard {
                    VStack(alignment: .leading, spacing: 12) {
                        sourceBadge("House of Commons Debates, June 18, 2026")
                        Text("National Framework for Food Price Transparency Act")
                            .font(.headline)
                            .lineLimit(3)
                        speakerRow(name: "Gurbux Saini", riding: "Fleetwood-Port Kells", party: "Lib.")
                        speechBubble("Bill C-226 would create a national framework for grocery price transparency.")
                    }
                }
                previewCard {
                    speakerRow(name: "Andrew Lawton", riding: "Elgin-St. Thomas-London South", party: "CPC")
                }
            }
        case .memberVotes:
            previewCard {
                VStack(alignment: .leading, spacing: 14) {
                    sourceBadge("House of Commons recorded divisions")
                    Text("Your MP's voting record")
                        .font(.headline)
                    voteRow(title: "Division No. 926", detail: "Motion negatived", vote: "Yea", color: .appPositive)
                    voteRow(title: "Division No. 927", detail: "Motion agreed to", vote: "Yea", color: .appPositive)
                    voteRow(title: "Division No. 928", detail: "Motion agreed to", vote: "Nay", color: .appDestructive)
                    progressRow(label: "Votes with party", value: "2 of 3")
                }
            }
        case .bill:
            previewCard {
                VStack(alignment: .leading, spacing: 13) {
                    sourceBadge("Parliament of Canada LEGISinfo")
                    Text("Bill C-226")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("National framework to improve food price transparency")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    timelineStage("Introduced", done: true)
                    timelineStage("Second reading", done: true)
                    timelineStage("Committee", done: false)
                    Label("Follow bill", systemImage: "doc.badge.clock")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        case .notification:
            VStack(spacing: 12) {
                previewCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "bell.badge.fill")
                                .font(.title2)
                                .foregroundStyle(Color.appWarning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Vote result")
                                    .font(.headline)
                                Text("Your MP voted Yea on Division No. 926.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        sourceBadge("House of Commons Journals")
                    }
                }
                previewCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Opened from notification")
                            .font(.headline)
                        voteRow(title: "Division No. 926", detail: "Motion negatived", vote: "Yea", color: .appPositive)
                    }
                }
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
        case postalCode
        case debate
        case memberVotes
        case bill
        case notification
        case contact
    }

    let headline: String
    let tabTitle: String
    let systemImage: String
    let kind: Kind

    static let scenes: [AppPreviewScene] = [
        AppPreviewScene(
            headline: "Start with your postal code.",
            tabTitle: "Home",
            systemImage: "house.fill",
            kind: .postalCode
        ),
        AppPreviewScene(
            headline: "Read Parliament as it happens.",
            tabTitle: "Parliament",
            systemImage: "building.columns.fill",
            kind: .debate
        ),
        AppPreviewScene(
            headline: "See how your MP votes.",
            tabTitle: "Members",
            systemImage: "person.2.fill",
            kind: .memberVotes
        ),
        AppPreviewScene(
            headline: "Follow bills from debate to vote.",
            tabTitle: "Accountability",
            systemImage: "doc.text.fill",
            kind: .bill
        ),
        AppPreviewScene(
            headline: "Get the vote result.",
            tabTitle: "Home",
            systemImage: "bell.badge.fill",
            kind: .notification
        ),
        AppPreviewScene(
            headline: "Then contact your MP.",
            tabTitle: "Members",
            systemImage: "envelope.fill",
            kind: .contact
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
