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
        
        // Find Ruby Sahota's speech anywhere in the parsed Hansard
        let rubySpeech = bro.ordersOfBusiness
            .flatMap { $0.subjects }
            .flatMap { $0.speeches }
            .first { speech in
                speech.messages.contains { $0.lastName == "Sahota" }
            }

        // Debugging output for all speeches to understand what's being parsed
        print("\n--- All Speeches Found ---")
        for order in bro.ordersOfBusiness {
            for subject in order.subjects {
                print("Subject: \(subject.title)")
                for speech in subject.speeches {
                    for message in speech.messages {
                        print("  Speaker: '\(message.firstName) \(message.lastName)'")
                        print("  Party: '\(message.partyAbbreviation)'")
                        print("  Riding: '\(message.ridingName)'")
                        print("  Hansard ID: \(message.hansardID)")
                    }
                }
            }
        }
        print("--- End All Speeches Found ---\\n")
        
        if let rubySpeech {
            #expect(rubySpeech.messages[0].firstName == "Ruby")
            #expect(rubySpeech.messages[0].lastName == "Sahota")
        } else {
            // Let's debug the XMLBro directly for the problematic speaker
            let personspeaking = "Hon. Ruby Sahota (Secretary of State (Combatting Crime), Lib.)"
            let result = parsePerson(personspeaking)
            print("Direct parse result: \(result)")
            Issue.record("Could not find Ruby Sahota in Public Safety. Parsed result for test string: \(result)")
        }
    }

    func parsePerson(_ personspeaking: String) -> (String, String, String) {
        var speakername: String = ""
        var partyname: String = ""
        var ridingname: String = ""
        var startspeaker: Bool?
        var startparty: Bool?
        var startriding: Bool?
        
        let ps = personspeaking.replacingOccurrences(of: "Mme ", with: "Mme. ")
        let startindex = ps.startIndex
        let endindex = ps.endIndex
        for i in 0..<ps.count {
            let index = ps.index(startindex, offsetBy: i)
            let backindex = ps.index(endindex, offsetBy: -(i+1))
            if let start = startspeaker, start {
                if ps[index] == "(" {
                    startspeaker = false
                } else {
                    speakername.append(ps[index])
                }
            } else {
                if ps[index] == "." && startspeaker == nil {
                    startspeaker = true
                }
            }
            if let start = startparty, start {
                if ps[backindex] == "," {
                    startparty = false
                } else {
                    partyname.append(ps[backindex])
                }
            } else {
                if ps[backindex] == ")" && startparty == nil {
                    startparty = true
                }
            }
            if let start = startriding, start {
                if ps[backindex] == "(" {
                    startriding = false
                } else {
                    ridingname.append(ps[backindex])
                }
            } else {
                if ps[backindex] == "," && startriding == nil {
                    startriding = true
                }
            }
        }
        if startspeaker == nil {
            if let parenIndex = ps.firstIndex(of: "(") {
                speakername = String(ps[..<parenIndex])
            } else {
                speakername = ps
            }
        }
        partyname = String(partyname.trimmingCharacters(in: CharacterSet.letters.inverted).reversed())
        ridingname = String(ridingname.trimmingCharacters(in: CharacterSet.whitespaces).reversed())
        
        let speakerNames = speakername.trimmingCharacters(in: CharacterSet.whitespaces).split(separator: " ")
        let cleanNames = speakerNames.filter { !["Hon.", "Rt.", "Mr.", "Ms.", "Mrs.", "Mme.", "Dr.", "The", "Hon", "Rt"].contains($0) }
        let firstName = cleanNames.dropLast().joined(separator: " ")
        let lastName = String(cleanNames.last ?? "")
        
        return (firstName, lastName, partyname)
    }
}
