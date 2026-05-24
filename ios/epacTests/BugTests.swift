@testable import epac
import Foundation
import SWXMLHash
import Testing

struct BugTests {
    @Test func testRubySahotaPublicSafetyNameParsing() async throws {
        guard let fixtureURL = Bundle(for: ForThisOnly.self).url(forResource: "45-1-HAN074-E", withExtension: "XML") else {
            Issue.record("Could not find fixture for 45-1-HAN074-E")
            return
        }
        let xmlstring = try String(contentsOf: fixtureURL, encoding: .utf8)
        let bro = XMLBro(xml: xmlstring).parseXML()

        // Debugging output for all speeches to understand what's being parsed
        printAllSpeeches(in: bro)
        
        let rubySpeech = rubySahotaSpeech(in: bro)
        if let rubySpeech {
            #expect(rubySpeech.messages[0].firstName == "Ruby")
            #expect(rubySpeech.messages[0].lastName == "Sahota")
            #expect(rubySpeech.messages[0].partyAbbreviation == "Lib")
            #expect(rubySpeech.messages[0].ridingName == "")
        } else {
            // Let's debug the XMLBro directly for the problematic speaker
            let personspeaking = "Hon. Ruby Sahota (Secretary of State (Combatting Crime), Lib.)"
            let result = HansardSpeakerParser.parse(personspeaking)
            print("Direct parse result: \(result)")
            Issue.record("Could not find Ruby Sahota in Public Safety. Parsed result for test string: \(result)")
        }
    }

    func rubySahotaSpeech(in bro: XMLBro) -> SpeechDTO? {
        bro.ordersOfBusiness
            .flatMap { $0.subjects }
            .flatMap { $0.speeches }
            .first { speech in
                speech.messages.contains { $0.lastName == "Sahota" }
            }
    }

    func printAllSpeeches(in bro: XMLBro) {
        print("\n--- All Speeches Found ---")
        for order in bro.ordersOfBusiness {
            for subject in order.subjects {
                print("Subject: \(subject.title)")
                for speech in subject.speeches {
                    printMessages(in: speech)
                }
            }
        }
        print("--- End All Speeches Found ---\\n")
    }

    func printMessages(in speech: SpeechDTO) {
        for message in speech.messages {
            print("  Speaker: '\(message.firstName) \(message.lastName)'")
            print("  Party: '\(message.partyAbbreviation)'")
            print("  Riding: '\(message.ridingName)'")
            print("  Hansard ID: \(message.hansardID)")
        }
    }
}
