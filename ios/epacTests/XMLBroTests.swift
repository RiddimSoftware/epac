@testable import epac
import Foundation
import Testing

struct XMLBroTests {

    @Test func testNameParsingWithTitles() async throws {
        let xml = """
        <Hansard id="123">
            <HansardBody>
                <OrderOfBusiness id="1">
                    <CatchLine>Debate</CatchLine>
                    <SubjectOfBusiness id="1">
                        <SubjectOfBusinessTitle>Title</SubjectOfBusinessTitle>
                        <SubjectOfBusinessContent>
                            <Intervention id="1">
                                <PersonSpeaking>
                                    <Affiliation>Hon. Anita Anand (President of the Treasury Board and Minister of Transport, Lib.)</Affiliation>
                                </PersonSpeaking>
                                <Content><ParaText id="1">Text</ParaText></Content>
                            </Intervention>
                            <Intervention id="2">
                                <PersonSpeaking>
                                    <Affiliation>Mr. Kyle Seeback (Dufferin—Caledon, CPC)</Affiliation>
                                </PersonSpeaking>
                                <Content><ParaText id="2">Text</ParaText></Content>
                            </Intervention>
                            <Intervention id="3">
                                <PersonSpeaking>
                                    <Affiliation>The Speaker</Affiliation>
                                </PersonSpeaking>
                                <Content><ParaText id="3">Text</ParaText></Content>
                            </Intervention>
                        </SubjectOfBusinessContent>
                    </SubjectOfBusiness>
                </OrderOfBusiness>
            </HansardBody>
        </Hansard>
        """
        let bro = XMLBro(xml: xml).parseXML()
        #expect(bro.ordersOfBusiness.count == 1)
        #expect(bro.ordersOfBusiness[0].subjects.count == 1)
        let speeches = bro.ordersOfBusiness[0].subjects[0].speeches
        #expect(speeches.count == 3)

        let speech1 = speeches[0]
        #expect(speech1.messages[0].firstName == "Anita")
        #expect(speech1.messages[0].lastName == "Anand")
        #expect(speech1.messages[0].partyAbbreviation == "Lib")

        let speech2 = speeches[1]
        #expect(speech2.messages[0].firstName == "Kyle")
        #expect(speech2.messages[0].lastName == "Seeback")
        #expect(speech2.messages[0].partyAbbreviation == "CPC")
        
        let speech3 = speeches[2]
        #expect(speech3.messages[0].firstName == "")
        #expect(speech3.messages[0].lastName == "Speaker")
    }

    @Test func testParsingAcrossParliaments() async throws {
        let files = ["39-2-HAN047-E", "42-1-HAN019-E", "44-1-HAN291-E", "45-1-HAN073-E"]
        for file in files {
            guard let fixtureURL = Bundle(for: ForThisOnly.self).url(forResource: file, withExtension: "XML") else {
                Issue.record("Could not find fixture for \(file)")
				continue
            }
            let xmlstring = try String(contentsOf: fixtureURL, encoding: .utf8)
            let bro = XMLBro(xml: xmlstring).parseXML()
            #expect(!bro.ordersOfBusiness.isEmpty)
            
            // Verify that we found some speeches
            let allSpeeches = bro.ordersOfBusiness.flatMap { $0.subjects.flatMap { $0.speeches } }
            #expect(!allSpeeches.isEmpty)
        }
    }

    @Test func testRobustTextExtraction() async throws {
        let xml = """
        <Hansard id="456">
            <HansardBody>
                <OrderOfBusiness id="1">
                    <CatchLine>Debate</CatchLine>
                    <SubjectOfBusiness id="1">
                        <SubjectOfBusinessTitle>Title</SubjectOfBusinessTitle>
                        <SubjectOfBusinessContent>
                            <Intervention id="1">
                                <PersonSpeaking>
                                    <Affiliation>Mr. <I>John</I> Doe (Riding, NDP)</Affiliation>
                                </PersonSpeaking>
                                <Content><ParaText id="1">Text with <B>bold</B> and <I>italics</I>.</ParaText></Content>
                            </Intervention>
                        </SubjectOfBusinessContent>
                    </SubjectOfBusiness>
                </OrderOfBusiness>
            </HansardBody>
        </Hansard>
        """
        let bro = XMLBro(xml: xml).parseXML()
        #expect(!bro.ordersOfBusiness.isEmpty)
        let speech = bro.ordersOfBusiness[0].subjects[0].speeches[0]
        #expect(speech.messages[0].firstName == "John")
        #expect(speech.messages[0].lastName == "Doe")
        #expect(speech.messages[0].content.contains("bold"))
        #expect(speech.messages[0].content.contains("italics"))
    }
    
    @Test func testSplitAffiliation() async throws {
        let xml = """
        <Hansard id="789">
            <HansardBody>
                <OrderOfBusiness id="1">
                    <CatchLine>Debate</CatchLine>
                    <SubjectOfBusiness id="1">
                        <SubjectOfBusinessTitle>Title</SubjectOfBusinessTitle>
                        <SubjectOfBusinessContent>
                            <Intervention id="1">
                                <PersonSpeaking>
                                    <Affiliation DbId="123">Mr. John Doe</Affiliation>
                                    <Affiliation DbId="456"> (Riding, Lib.)</Affiliation>
                                </PersonSpeaking>
                                <Content><ParaText id="1">Text</ParaText></Content>
                            </Intervention>
                        </SubjectOfBusinessContent>
                    </SubjectOfBusiness>
                </OrderOfBusiness>
            </HansardBody>
        </Hansard>
        """
        let bro = XMLBro(xml: xml).parseXML()
        #expect(!bro.ordersOfBusiness.isEmpty)
        let speech = bro.ordersOfBusiness[0].subjects[0].speeches[0]
        #expect(speech.messages[0].firstName == "John")
        #expect(speech.messages[0].lastName == "Doe")
        #expect(speech.messages[0].partyAbbreviation == "Lib")
    }

    @Test func testRightHonTitleParsing() async throws {
        let xml = """
        <Hansard id="101">
            <HansardBody>
                <OrderOfBusiness id="1">
                    <CatchLine>Oral Questions</CatchLine>
                    <SubjectOfBusiness id="1">
                        <SubjectOfBusinessTitle>Oral Questions</SubjectOfBusinessTitle>
                        <SubjectOfBusinessContent>
                            <Intervention id="1">
                                <PersonSpeaking>
                                    <Affiliation>Right Hon. Mark Carney (Prime Minister, Lib.)</Affiliation>
                                </PersonSpeaking>
                                <Content><ParaText id="1">Text</ParaText></Content>
                            </Intervention>
                        </SubjectOfBusinessContent>
                    </SubjectOfBusiness>
                </OrderOfBusiness>
            </HansardBody>
        </Hansard>
        """
        let bro = XMLBro(xml: xml).parseXML()
        let speech = bro.ordersOfBusiness[0].subjects[0].speeches[0]
        #expect(speech.messages[0].firstName == "Mark")
        #expect(speech.messages[0].lastName == "Carney")
    }

    @Test func testParseMembers() async throws {
        guard let fixtureURL = Bundle(for: ForThisOnly.self).url(forResource: "fixtures/members", withExtension: "xml") else {
            return
        }
        let xmlstring = try String(contentsOf: fixtureURL, encoding: .utf8)
        let members = XMLBro.parseMembers(xmlstring)
        #expect(!members.isEmpty)
        
        // Ziad Aboultaif is the first one in the downloaded file
        if let ziad = members.first(where: { $0.firstName == "Ziad" && $0.lastName == "Aboultaif" }) {
            #expect(ziad.memberID == 89156)
            #expect(ziad.riding == "Edmonton Manning")
            #expect(ziad.province == .Alberta)
            #expect(ziad.party == .conservative)
            #expect(ziad.fromDateTime != nil)
            #expect(ziad.toDateTime == nil)
        } else {
            Issue.record("Could not find Ziad Aboultaif in parsed members")
        }
    }
}
