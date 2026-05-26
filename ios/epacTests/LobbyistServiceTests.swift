@testable import epac
import Testing

#if DEBUG
struct LobbyistServiceTests {
    @Test func parsesRFC4180Rows() {
        let csv = #"""
        id,name,notes,empty
        1,"Doe, Jane","Line one
        Line two",""
        2,"Quoted ""Nickname""","Plain",tail
        3,,,
        """#

        let rows = LobbyistService.parseCSVRowsForTesting(csv, skipHeader: true)

        #expect(rows == [
            ["1", "Doe, Jane", "Line one\nLine two", ""],
            ["2", "Quoted \"Nickname\"", "Plain", "tail"],
            ["3", "", "", ""]
        ])
    }

    @Test func preservesHeaderWhenNotSkipped() {
        let csv = "first,second\r\nalpha,beta"

        let rows = LobbyistService.parseCSVRowsForTesting(csv, skipHeader: false)

        #expect(rows == [
            ["first", "second"],
            ["alpha", "beta"]
        ])
    }

    @Test func ignoresBlankRowsBeforeSkippedHeader() {
        let csv = "\nheader,value\nkept,row"

        let rows = LobbyistService.parseCSVRowsForTesting(csv, skipHeader: true)

        #expect(rows == [["kept", "row"]])
    }
}
#endif
