//
//  SpeechView.swift
//  epac
//
//  Created by Sunny on 2024-12-14.
//

import SwiftUI
import SwiftyGif

struct SpeechView: View {
	let speech: Speech
	@State private var index: Int = 0
	@State private var messages = [SpeechMessage]()
	@State private var loading = false
	
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
						}
						if index == speech.length {
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
			if index < speech.length {
				TypingIndicator()
			}
		}
		.task {
			do {
				try await Task.sleep(nanoseconds: 700_000_000)
				withAnimation {
					messages.append(speech.messages.first!)
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
			if speech.messages.count > index {
				withAnimation {
					messages.append(speech.messages[index])
				}
				index += 1
			}
		}
	}
	
	//	var body: some View {
	//		List {
	//			Section {
	//				ForEach(messages) { message in
	//					Text(message.content)
	//				}
	//			} header: {
	//				VStack(alignment: .center) {
	//					Text(speech.messages.first!.speaker.name)
	//						.font(.headline)
	//					Text(speech.messages.first!.speaker.party.localizedAbbreviation)
	//						.font(.subheadline)
	//					Text(speech.messages.first!.speaker.riding)
	//						.font(.caption)
	//				}
	//			}
	//		}
	//	}
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

struct AnimatedGifView: UIViewRepresentable {
	func makeUIView(context: Context) -> UIImageView {
		let imageView = UIImageView.init(gifImage: UIImage(named: "typing.gif")!)
		imageView.contentMode = .scaleAspectFit
		return imageView
	}
	
	func updateUIView(_ uiView: UIImageView, context: Context) {
		uiView.startAnimatingGif()
	}
}
