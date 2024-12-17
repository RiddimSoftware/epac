//
//  SpeechView.swift
//  epac
//
//  Created by Sunny on 2024-12-14.
//

import SwiftUI

struct SpeechView: View {
	let subject: SubjectOfBusiness
	@State private var index: Int = 0
	@State private var messages = [SpeechMessage]()
	@State private var loading = false
	@State private var currentSpeech: Speech

	init(subject: SubjectOfBusiness) {
		self.subject = subject
		self.currentSpeech = subject.speeches.first!
	}

	var body: some View {
		VStack {
			ScrollViewReader { proxy in
				ScrollView {
					LazyVStack {
						ForEach(messages) { message in
							HStack {
								MessageCell(message: message)
								Spacer(minLength: 40)
							}
							if message == messages.last, index < currentSpeech.length {
								VStack(alignment: .leading) {
									HStack {
										TypingIndicator()
											.padding(10)
											.background(Color(UIColor.systemGray6))
											.cornerRadius(10)
										Spacer(minLength: 40)
									}
									Text("Tap anywhere to continue")
										.font(.system(.footnote, design: .default, weight: .light))
										.foregroundStyle(Color.gray)
								}
							}
						}
						if index == currentSpeech.length {
							Text("End")
								.font(.caption)
						}
					}
				}
				.onChange(of: messages, { oldValue, newValue in
					if let id = newValue.last?.id {
						proxy.scrollTo(id, anchor: .bottom)
					}
				})
			}
			.padding(.horizontal)
			//			if index < currentSpeech.length {
			//				TypingIndicator()
			//			}
		}
		.task {
			do {
				try await Task.sleep(nanoseconds: 700_000_000)
				withAnimation {
					messages.append(currentSpeech.messages.first!)
				}
				index += 1
			} catch {
				print("Failed to sleep 0.7s \(error.localizedDescription)")
			}
		}
		.onAppear {
			withAnimation {
				self.loading = true
			}
		}
		.defaultScrollAnchor(.bottom)
		.onTapGesture {
			if currentSpeech.messages.count > index {
				withAnimation {
					messages.append(currentSpeech.messages[index])
				}
				index += 1
			}
		}
	}
}

struct MessageCell: View {
	@Environment(\.colorScheme) var colorScheme
	var message: SpeechMessage
	@State var content: String
	init(message: SpeechMessage) {
		self.message = message
		self.content = message.content
	}
	var body: some View {
		Text(verbatim: content)
			.padding(10)
			.foregroundColor(colorScheme == .dark ? Color(UIColor.white) : Color(UIColor.darkText))
			.background(Color(UIColor.systemGray6))
			.cornerRadius(10)
	}
}
