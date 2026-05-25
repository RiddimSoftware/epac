//
//  SpeechViewModel+Sharing.swift
//  epac
//

import ActivityView
import ExyteChat
import SwiftUI

extension SpeechViewModel {
    @MainActor
    func shareMessage(_ message: Message, subject: SubjectOfBusiness, hansard: Hansard) -> ActivityItem? {
        guard let speaker = speakers[message.id] else { return nil }
        let renderer = ImageRenderer(content: createMessageView(
            message,
            speaker: speaker,
            subject: subject,
            hansard: hansard
        ))
        renderer.scale = UIScreen.main.scale
        if let image = renderer.uiImage {
            let source = ShareActivityItemSource(image: image, title: subject.title)
            return ActivityItem(items: source)
        }
        return nil
    }

    @MainActor
    func shareLast5Messages(subject: SubjectOfBusiness, hansard: Hansard) -> ActivityItem? {
        let lastMessages = Array(messages.suffix(SpeechViewModelLayout.shareMessageLimit))
        let baseURL = "https://epac.riddimsoftware.com/app"
            + "?date=\(hansard.date.ISO8601Format())"
            + "&subjectID=\(subject.hansardID)"
        let url: URL
        if didFinish {
            url = URL(string: baseURL)!
        } else if let nextMessage = nextSpeechMessage,
                  let speechID = speechID(containing: nextMessage.interventionID, in: subject) {
            url = URL(string: "\(baseURL)&speechID=\(speechID)&messageID=\(nextMessage.interventionID)")!
        } else {
            url = URL(string: baseURL)!
        }

        let shareView = MultiMessageShareView(
            messages: lastMessages,
            speakers: speakers,
            parliamentNumber: hansard.parliamentNumber,
            subjectTitle: subject.title,
            date: hansard.date
        )
        let renderer = ImageRenderer(content: shareView)
        renderer.scale = UIScreen.main.scale
        if let image = renderer.uiImage {
            let source = ShareActivityItemSource(image: image, title: subject.title, url: url)
            return ActivityItem(items: source, url)
        } else {
            return ActivityItem(items: url)
        }
    }

    private func createMessageView(
        _ message: Message,
        speaker: ParliamentMember,
        subject: SubjectOfBusiness,
        hansard: Hansard
    ) -> some View {
        VStack(alignment: .leading, spacing: SpeechViewModelLayout.shareRootSpacing) {
            VStack(alignment: .leading, spacing: SpeechViewModelLayout.shareHeaderSpacing) {
                Text(subject.title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.gray)
                Text(hansard.date.formatted(date: .long, time: .omitted))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.gray.opacity(SpeechViewModelLayout.shareHeaderOpacity))
            }
            .padding(.bottom, SpeechViewModelLayout.shareHeaderBottomPadding)

            HStack(alignment: .bottom) {
                if message.user.isCurrentUser {
                    Spacer()
                }
                if !message.user.isCurrentUser {
                    SpeakerImageView(speaker: speaker, parliamentNumber: hansard.parliamentNumber)
                }
                VStack(alignment: message.user.isCurrentUser ? .trailing : .leading) {
                    VStack(alignment: .leading, spacing: SpeechViewModelLayout.shareMessageSpacing) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(speaker.name)
                                .font(.system(.caption, design: .rounded, weight: .bold))
                            Text("\(speaker.riding), \(speaker.province.rawValue)")
                                .font(.system(.caption2, design: .rounded))
                        }
                        .foregroundStyle(.white.opacity(SpeechViewModelLayout.shareSpeakerOpacity))
                        Text(verbatim: message.text)
                            .lineSpacing(SpeechViewModelLayout.shareLineSpacing)
                    }
                    .padding(SpeechViewModelLayout.shareBubblePadding)
                    .background(message.user.isCurrentUser ? Color(UIColor.darkGray) : Color(UIColor.gray))
                    .cornerRadius(SpeechViewModelLayout.shareBubbleCornerRadius)
                    .foregroundStyle(.white)
                }
                if message.user.isCurrentUser {
                    SpeakerImageView(speaker: speaker, parliamentNumber: hansard.parliamentNumber)
                }
                if !message.user.isCurrentUser {
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color.appBackground)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: SpeechViewModelLayout.shareWidth)
    }
}
