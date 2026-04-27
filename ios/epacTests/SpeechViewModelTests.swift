import Testing
import SwiftData
import Foundation
@testable import epac

@MainActor
struct SpeechViewModelTests {

	// MARK: - Helpers

	private func makeContainer() throws -> ModelContainer {
		let config = ModelConfiguration(isStoredInMemoryOnly: true)
		return try ModelContainer(for: Schema(SchemaV3.models), configurations: config)
	}

	/// Creates a Hansard with one subject → one speech → `messageCount` messages,
	/// all attributed to a single Liberal speaker. Everything is saved to context.
	private func setup(messageCount: Int = 3) throws -> (ModelContainer, ModelContext, Hansard, SubjectOfBusiness) {
		let container = try makeContainer()
		let context = ModelContext(container)

		let messages = (0..<messageCount).map { i in
			SpeechMessage(
				firstName: "Justin",
				lastName: "Trudeau",
				partyAbbreviation: "Lib",
				ridingName: "Papineau",
				hansardID: String(format: "msg-%04d", i),
				content: "Content \(i)",
				timestamp: Date(timeIntervalSince1970: Double(i))
			)
		}
		let speech = Speech(messages: messages, hansardID: "speech-0", date: Date(), title: "Speech 0")
		let subject = SubjectOfBusiness(title: "Test Subject", hansardID: "subject-0", speeches: [speech])
		let order = OrderOfBusiness(hansardID: "order-0", catchline: "Routine Proceedings", subjects: [subject])
		let hansard = Hansard(date: Date(), hansardID: "hansard-0", parliamentNumber: 45, sessionNumber: 1, orders: [order])
		context.insert(hansard)
		try context.save()
		return (container, context, hansard, subject)
	}

	// MARK: - nextMessage

	@Test func nextMessageAppendsOneMessagePerCall() throws {
		let (container, context, hansard, subject) = try setup(messageCount: 3)
		let navigator = SubjectNavigator(subject)
		let vm = SpeechViewModel()
		let fetch = Fetch(modelContainer: container)

		#expect(vm.messages.isEmpty)
		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)
		#expect(vm.messages.count == 1)
		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)
		#expect(vm.messages.count == 2)
	}

	@Test func nextMessageSetsDidFinishAfterLastMessage() throws {
		let (container, context, hansard, subject) = try setup(messageCount: 2)
		let navigator = SubjectNavigator(subject)
		let vm = SpeechViewModel()
		let fetch = Fetch(modelContainer: container)

		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)
		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)
		#expect(!vm.didFinish)

		// One more call with no messages remaining
		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)
		#expect(vm.didFinish)
		#expect(vm.messages.count == 2)
	}

	@Test func nextMessageNoOpsAfterDidFinish() throws {
		let (container, context, hansard, subject) = try setup(messageCount: 1)
		let navigator = SubjectNavigator(subject)
		let vm = SpeechViewModel()
		let fetch = Fetch(modelContainer: container)

		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)
		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch) // sets didFinish
		let count = vm.messages.count
		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch) // no-op
		#expect(vm.messages.count == count)
	}

	@Test func nextMessageTracksCurrentSpeechAndMessage() throws {
		let (container, context, hansard, subject) = try setup(messageCount: 2)
		let navigator = SubjectNavigator(subject)
		let vm = SpeechViewModel()
		let fetch = Fetch(modelContainer: container)

		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)

		#expect(subject.currentSpeechID == "speech-0")
		#expect(subject.currentSpeech?.currentMessageID == "msg-0000")
	}

	@Test func nextMessageInsertsTemporaryMemberWhenNotFound() throws {
		let (container, context, hansard, subject) = try setup(messageCount: 1)
		let navigator = SubjectNavigator(subject)
		let vm = SpeechViewModel()
		let fetch = Fetch(modelContainer: container)

		let membersBefore = try context.fetch(FetchDescriptor<ParliamentMember>())
		#expect(membersBefore.isEmpty)

		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)

		let membersAfter = try context.fetch(FetchDescriptor<ParliamentMember>())
		#expect(membersAfter.count == 1)
		#expect(membersAfter.first?.firstName == "Justin")
	}

	// MARK: - reset

	@Test func resetClearsMessagesAndSpeakers() throws {
		let (container, context, hansard, subject) = try setup(messageCount: 2)
		let navigator = SubjectNavigator(subject)
		let vm = SpeechViewModel()
		let fetch = Fetch(modelContainer: container)

		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)
		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)
		#expect(vm.messages.count == 2)
		#expect(!vm.speakers.isEmpty)

		vm.reset(navigator: navigator, subject: subject)

		#expect(vm.messages.isEmpty)
		#expect(vm.speakers.isEmpty)
		#expect(!vm.didFinish)
	}

	@Test func resetClearsSubjectNavigationState() throws {
		let (container, context, hansard, subject) = try setup(messageCount: 2)
		let navigator = SubjectNavigator(subject)
		let vm = SpeechViewModel()
		let fetch = Fetch(modelContainer: container)

		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)
		#expect(subject.currentSpeechID != nil)

		vm.reset(navigator: navigator, subject: subject)

		#expect(subject.currentSpeech == nil)
		#expect(subject.currentSpeechID == nil)
	}

	// MARK: - tapAnywhereOpacity

	@Test func tapAnywhereOpacityIsOneWithFewerThanTwoMessages() throws {
		let (container, context, hansard, subject) = try setup(messageCount: 3)
		let navigator = SubjectNavigator(subject)
		let vm = SpeechViewModel()
		let fetch = Fetch(modelContainer: container)

		#expect(vm.tapAnywhereOpacity == 1.0)
		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)
		#expect(vm.tapAnywhereOpacity == 1.0)
	}

	@Test func tapAnywhereOpacityIsZeroWithTwoOrMoreMessages() throws {
		let (container, context, hansard, subject) = try setup(messageCount: 3)
		let navigator = SubjectNavigator(subject)
		let vm = SpeechViewModel()
		let fetch = Fetch(modelContainer: container)

		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)
		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)
		#expect(vm.tapAnywhereOpacity == 0.0)
	}

	// MARK: - prepareResume

	@Test func prepareResumeRestoresPositionFromSavedIDs() throws {
		let (container, context, hansard, subject) = try setup(messageCount: 3)

		// Simulate the app having stopped at the second message
		let speech = subject.speeches.first!
		subject.currentSpeech = speech
		subject.currentSpeechID = speech.hansardID
		let savedMessage = speech.messages.first(where: { $0.hansardID == "msg-0001" })!
		speech.currentMessage = savedMessage
		speech.currentMessageID = savedMessage.hansardID
		try context.save()

		let navigator = SubjectNavigator(subject)
		let vm = SpeechViewModel()
		let fetch = Fetch(modelContainer: container)

		vm.prepareResume(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)

		// Replayed msg-0000 and msg-0001 (2 messages)
		#expect(vm.messages.count == 2)
		#expect(vm.messages.last?.id == "msg-0001")
		#expect(vm.isResuming)
	}

	@Test func prepareResumeIsNoOpWhenMessagesAlreadyPresent() throws {
		let (container, context, hansard, subject) = try setup(messageCount: 3)
		let navigator = SubjectNavigator(subject)
		let fetch = Fetch(modelContainer: container)

		// Pre-populate so prepareResume's guard fires
		let existingVM = SpeechViewModel()
		existingVM.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)
		let countBefore = existingVM.messages.count

		existingVM.prepareResume(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)
		#expect(existingVM.messages.count == countBefore)
	}
}
