@testable import epac
import Foundation
import SwiftData
import SwiftUI
import Testing

@MainActor
struct MembersSelectionTests {

	private func makeContainer() throws -> ModelContainer {
		let config = ModelConfiguration(isStoredInMemoryOnly: true)
		return try ModelContainer(for: Schema(SchemaV10.models), configurations: config)
	}

	private func member(
		firstName: String,
		lastName: String,
		context: ModelContext,
		memberID: Int
	) -> ParliamentMember {
		let member = ParliamentMember(
			name: "\(firstName) \(lastName)",
			lastName: lastName,
			firstName: firstName,
			photoURL: URL(string: "https://example.com/photo.jpg")!,
			riding: "Test Riding",
			province: .Ontario,
			party: .liberal,
			memberID: memberID
		)
		context.insert(member)
		return member
	}

	@Test func selectingMemberWritesBinding() throws {
		let context = ModelContext(try makeContainer())
		let expected = member(firstName: "Ada", lastName: "Lovelace", context: context, memberID: 1001)
		let box = SelectedMemberBox()
		let binding = Binding<ParliamentMember?>(
			get: { box.member },
			set: { box.member = $0 }
		)

		MembersSelection.select(expected, selection: binding)

		#expect(box.member == expected)
	}

	@Test func selectedStateUsesParliamentMemberIdentity() throws {
		let context = ModelContext(try makeContainer())
		let selected = member(firstName: "Grace", lastName: "Hopper", context: context, memberID: 1002)
		let other = member(firstName: "Katherine", lastName: "Johnson", context: context, memberID: 1003)

		#expect(MembersSelection.isSelected(selected, selectedMember: selected))
		#expect(!MembersSelection.isSelected(other, selectedMember: selected))
		#expect(!MembersSelection.isSelected(selected, selectedMember: nil))
	}

	@Test func routerRetainsMemberSelectionAcrossTabChanges() throws {
		let context = ModelContext(try makeContainer())
		let selected = member(firstName: "Mary", lastName: "Jackson", context: context, memberID: 1004)
		let router = NavigationRouter()

		router.selectedMember = selected
		router.selectedTab = .home
		router.selectedTab = .members

		#expect(router.selectedMember == selected)
	}
}

@MainActor
private final class SelectedMemberBox {
	var member: ParliamentMember?
}
