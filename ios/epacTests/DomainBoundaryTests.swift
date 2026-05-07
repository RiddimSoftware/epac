@testable import epac
import Foundation
import Testing

struct DomainBoundaryTests {

	@Test func domainFilesDoNotImportSwiftDataOrUIFrameworks() throws {
		let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		let domainDirectory = testsDirectory.deletingLastPathComponent().appendingPathComponent("epac/Domain")
		let forbiddenImports = ["import SwiftData", "import SwiftUI", "import UIKit"]

		let enumerator = FileManager.default.enumerator(at: domainDirectory, includingPropertiesForKeys: nil)
		let swiftFiles = (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
		#expect(!swiftFiles.isEmpty)

		let violations = try swiftFiles.flatMap { fileURL -> [String] in
			let source = try String(contentsOf: fileURL, encoding: .utf8)
			return forbiddenImports.compactMap { forbidden in
				source.contains(forbidden) ? "\(fileURL.lastPathComponent): \(forbidden)" : nil
			}
		}

		#expect(violations.isEmpty, "Forbidden framework imports found in domain files: \(violations.joined(separator: ", "))")
	}

	@Test func hansardDTOCanRoundTripThroughSwiftDataAdapters() {
		let dto = HansardDTO(
			date: Date(timeIntervalSince1970: 1_234_567),
			hansardID: "hansard-123",
			parliamentNumber: 45,
			sessionNumber: 1,
			orders: [
				OrderOfBusinessDTO(
					hansardID: "order-123",
					catchline: "Government Orders",
					subjects: [
						SubjectOfBusinessDTO(
							title: "Housing Affordability",
							hansardID: "subject-123",
							speeches: [
								SpeechDTO(
									messages: [
										SpeechMessageDTO(
											firstName: "Mark",
											lastName: "Carney",
											partyAbbreviation: "Lib",
											ridingName: "Nepean",
											hansardID: "msg-123",
											content: "We need more homes.",
											timestamp: Date(timeIntervalSince1970: 1_234_567)
										)
									],
									hansardID: "speech-123",
									currentMessageID: "msg-123",
									date: Date(timeIntervalSince1970: 1_234_567),
									length: 1,
									title: "Housing Affordability"
								)
							],
							currentSpeechID: "speech-123"
						)
					]
				)
			]
		)

		let model = Hansard(domain: dto)

		#expect(model.domainDTO == dto)
	}

	@Test func previewStyleMemberFixtureCanStartAsPlainDTO() {
		let dto = ParliamentMemberDTO(
			name: "Justin Trudeau",
			memberID: 123,
			lastName: "Trudeau",
			firstName: "Justin",
			photoURL: URL(string: "https://www.ourcommons.ca/Content/Parliamentarians/Images/OfficialMPPhotos/44/TrudeauJustin_LIB.jpg")!,
			riding: "Papineau",
			province: .Quebec,
			party: .liberal,
			websiteURL: URL(string: "https://liberal.ca"),
			imageData: nil,
			fromDateTime: nil,
			toDateTime: nil,
			email: nil,
			hillPhone: nil,
			constituencyPhone: nil,
			constituencyAddress: nil,
			contactFetched: false
		)

		let member = ParliamentMember(domain: dto)

		#expect(member.domainDTO == dto)
		#expect(member.initials == "JT")
	}
}
