@testable import epac
import Foundation
import SwiftData
import Testing

/// Stub resolver that returns a pre-built member without touching SwiftData.
/// Demonstrates MemberResolving injection — no network or disk I/O required.
@MainActor
private struct StubMemberResolver: MemberResolving {
    let member: ParliamentMember
    func resolve(
        firstName: String, lastName: String,
        partyAbbreviation: String, ridingName: String,
        parliamentNumber: Int, modelContext: ModelContext, fetch: Fetch
    ) -> ParliamentMember { member }
}

@MainActor
struct SpeechViewModelTests {

	// MARK: - Helpers

	private func makeContainer() throws -> ModelContainer {
		let config = ModelConfiguration(isStoredInMemoryOnly: true)
		return try ModelContainer(for: Schema(SchemaV5.models), configurations: config)
	}

	/// Creates a Hansard with one subject → one speech → `messageCount` messages,
	/// all attributed to a single Liberal speaker. Everything is saved to context.
	private func setup(messageCount: Int = 3) throws -> (ModelContainer, ModelContext, Hansard, SubjectOfBusiness) {
		try setup(parties: Array(repeating: "Lib", count: messageCount))
	}

	/// Creates a Hansard whose single speech has one message per entry in `parties`.
	/// Each message gets a distinct speaker name so party changes produce distinct members.
	private func setup(parties: [String]) throws -> (ModelContainer, ModelContext, Hansard, SubjectOfBusiness) {
		let container = try makeContainer()
		let context = ModelContext(container)

		let messages = parties.enumerated().map { i, party in
			SpeechMessage(
				firstName: "Speaker\(i)",
				lastName: "Last\(i)",
				partyAbbreviation: party,
				ridingName: "Riding\(i)",
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
		#expect(membersAfter.first?.firstName == "Speaker0")
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

	@Test func resetClearsMemberResolutionCache() throws {
		let (container, context, hansard, subject) = try setup(messageCount: 1)
		let navigator = SubjectNavigator(subject)
		let vm = SpeechViewModel()
		let fetch = Fetch(modelContainer: container)

		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)
		let cachedMembers = try context.fetch(FetchDescriptor<ParliamentMember>())
		#expect(cachedMembers.count == 1)
		let cachedID = cachedMembers[0].persistentModelID

		context.delete(cachedMembers[0])
		try context.save()
		vm.reset(navigator: navigator, subject: subject)
		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)

		let refreshedMembers = try context.fetch(FetchDescriptor<ParliamentMember>())
		#expect(refreshedMembers.count == 1)
		#expect(refreshedMembers[0].persistentModelID != cachedID)
		#expect(vm.speakers.values.first?.persistentModelID == refreshedMembers[0].persistentModelID)
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

	/// isResuming overrides the message-count check: opacity stays 1 while replaying saved position.
	@Test func tapAnywhereOpacityIsOneWhenIsResuming() throws {
		let (container, context, hansard, subject) = try setup(messageCount: 3)

		// Save a position at the second message so prepareResume replays 2 messages.
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

		// 2 messages visible, but isResuming is true, so opacity must be 1.
		#expect(vm.messages.count == 2)
		#expect(vm.isResuming)
		#expect(vm.tapAnywhereOpacity == 1.0)
	}

	// MARK: - isCurrentUser assignment

	/// The first speaker in a fresh chat is Liberal, so they appear on the right (isCurrentUser = true).
	@Test func nextMessageFirstLiberalSpeakerIsCurrentUser() throws {
		let (container, context, hansard, subject) = try setup(parties: ["Lib"])
		let navigator = SubjectNavigator(subject)
		let vm = SpeechViewModel()
		let fetch = Fetch(modelContainer: container)

		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)

		#expect(vm.messages.first?.user.isCurrentUser == true)
	}

	/// The first speaker in a fresh chat is Conservative (non-Liberal), so they appear on the left.
	@Test func nextMessageFirstNonLiberalSpeakerIsNotCurrentUser() throws {
		let (container, context, hansard, subject) = try setup(parties: ["CPC"])
		let navigator = SubjectNavigator(subject)
		let vm = SpeechViewModel()
		let fetch = Fetch(modelContainer: container)

		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)

		#expect(vm.messages.first?.user.isCurrentUser == false)
	}

	/// When the speaker changes, isCurrentUser toggles so consecutive speakers
	/// appear on opposite sides of the chat UI.
	@Test func nextMessageTogglesIsCurrentUserOnSpeakerChange() throws {
		// Lib speaker followed by a CPC speaker — distinct members, so toggle fires.
		let (container, context, hansard, subject) = try setup(parties: ["Lib", "CPC"])
		let navigator = SubjectNavigator(subject)
		let vm = SpeechViewModel()
		let fetch = Fetch(modelContainer: container)

		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)
		let firstSide = vm.messages[0].user.isCurrentUser

		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard, modelContext: context, fetch: fetch)
		let secondSide = vm.messages[1].user.isCurrentUser

		#expect(secondSide == !firstSide)
	}

	// MARK: - MemberResolving injection

	/// Injected StubMemberResolver is used: no SwiftData member lookup occurs.
	@Test func nextMessageUsesInjectedResolver() throws {
		let (container, context, hansard, subject) = try setup(messageCount: 1)
		let navigator = SubjectNavigator(subject)
		let vm = SpeechViewModel()
		let fetch = Fetch(modelContainer: container)
		let stubMember = ParliamentMember(
			name: "Injected Member",
			lastName: "Member",
			firstName: "Injected",
			photoURL: URL(string: "https://example.com/photo.jpg")!,
			riding: "Stub Riding",
			province: .Ontario,
			party: .liberal
		)
		let resolver = StubMemberResolver(member: stubMember)

		vm.nextMessage(navigator: navigator, subject: subject, hansard: hansard,
		               modelContext: context, fetch: fetch, resolver: resolver)

		#expect(vm.messages.first?.user.name == "Injected Member")
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
