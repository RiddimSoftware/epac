//
//  SpeechView2.swift
//  epac
//
//  Created by Sunny on 2024-12-16.
//

import SwiftUI
import ExyteChat

struct SpeechView2: View {
	let subject: SubjectOfBusiness
	@State private var index: Int = 0
	@State var messages = [Message]()
	init(subject: SubjectOfBusiness) {
		self.subject = subject
	}

	var body: some View {
		VStack {
			ChatView(messages: messages) { _ in
				
			} inputViewBuilder: { text, attachments, inputViewState, inputViewStyle, inputViewActionClosure, dismissKeyboardClosure in
				EmptyView()
			}
			.showDateHeaders(false)
			.showMessageMenuOnLongPress(false)
			.showMessageTimeView(false)
			.showNetworkConnectionProblem(false)
		}
		.simultaneousGesture(
			TapGesture()
				.onEnded {
				let speech = subject.speeches.first!
				if speech.messages.count > index {
					withAnimation {
						messages.append(Message(speech.messages[index]))
					}
					index += 1
				}
			}
			)
		.task {
			do {
				try await Task.sleep(nanoseconds: 700_000_000)
				withAnimation {
					let message = Message(subject.speeches.first!.messages.first!)
					messages.append(message)
					index += 1
				}
				index += 1
			} catch {
				print("Failed to sleep 0.7s \(error.localizedDescription)")
			}
		}
	}
}

extension Message {
	init(_ message: SpeechMessage) {
		let speaker = message.speaker
		let user = User(id: speaker.name, name: speaker.name, avatarURL: speaker.photoURL, isCurrentUser: false)
		self.init(id: message.hansardID, user: user, text: message.content)
	}
}
