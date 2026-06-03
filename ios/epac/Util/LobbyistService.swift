//
//  LobbyistService.swift
//  epac
//
//  Created on 2026-04-27.
//
//  Fetches lobbying communication reports from the Commissioner of Lobbying
//  of Canada open dataset (communications_ocl_cal.zip).
//
//  The OCL does not expose a per-MP JSON API. The open data page
//  (https://lobbycanada.gc.ca/en/open-data/) publishes a single zip archive
//  containing all communication reports as a set of relational CSV files.
//  This service downloads the archive once per app session, parses the
//  relevant CSV files, and caches the parsed results in an actor-isolated
//  singleton so concurrent profile views don't duplicate the ~22 MB download.
//
//  Data source:  https://lobbycanada.gc.ca/media/mqbbmaqk/communications_ocl_cal.zip
//  Authority:    Office of the Commissioner of Lobbying of Canada
//  Licence:      Open Government Licence – Canada
//
//  Approach tried and rejected:
//    A. POST to lobbycanada.gc.ca/app/secure/ocl/lrs/do/cmmLg — 403 Forbidden
//    B. open.canada.ca CKAN datastore — resource not in datastore (CSV only)
//    C. GET with format=json query param — 404 Not Found
//  Conclusion: the zip download is the only machine-readable authoritative source.
//

import Foundation
import zlib

struct LobbyistService {

    // MARK: - Constants
    private enum Constants {
        static let requestTimeout: TimeInterval = 60
        static let successStatusLowerBound = 200
        static let successStatusUpperBound = 300
        static let zipLocalFileHeaderLength = 30
        static let localFileSignatureLength = 4
        static let localFileSignatureFirstByte: UInt8 = 0x50
        static let localFileSignatureSecondByte: UInt8 = 0x4B
        static let localFileSignatureThirdByte: UInt8 = 0x03
        static let localFileSignatureFourthByte: UInt8 = 0x04
        static let zipMethodOffset = 8
        static let zipMethodHighByteOffset = 9
        static let compressedSizeOffset = 18
        static let uncompressedSizeOffset = 22
        static let fileNameLengthOffset = 26
        static let fileNameLengthHighByteOffset = 27
        static let extraLengthOffset = 28
        static let extraLengthHighByteOffset = 29
        static let byteShift = 8
        static let littleEndianSecondByteOffset = 1
        static let littleEndianThirdByteOffset = 2
        static let littleEndianFourthByteOffset = 3
        static let shortShift = 16
        static let int24Shift = 24
        static let zipCompressionMethodStored: UInt16 = 0
        static let zipCompressionMethodDeflate: UInt16 = 8
        static let rawDeflateWindowBits: Int32 = -15
        static let dpohRequiredColumnCount = 7
        static let dpohIDColumn = 0
        static let dpohLastNameColumn = 1
        static let dpohFirstNameColumn = 2
        static let dpohInstitutionColumn = 6
        static let primaryRequiredColumnCount = 9
        static let primaryIDColumn = 0
        static let primaryEnglishOrgColumn = 2
        static let primaryFrenchOrgColumn = 3
        static let primaryRegistrantLastNameColumn = 5
        static let primaryRegistrantFirstNameColumn = 6
        static let primaryDateColumn = 7
        static let primaryRegistrantTypeColumn = 8
        static let subjectRequiredColumnCount = 2
        static let subjectIDColumn = 0
        static let subjectCodeColumn = 1
        static let smtRequiredColumnCount = 2
        static let smtCodeColumn = 0
        static let smtEnglishDescriptionColumn = 1
        static let communicationLimit = 50

        static var successStatusCodes: Range<Int> {
            successStatusLowerBound..<successStatusUpperBound
        }

        static var localFileHeaderSignature: [UInt8] {
            [
                localFileSignatureFirstByte,
                localFileSignatureSecondByte,
                localFileSignatureThirdByte,
                localFileSignatureFourthByte
            ]
        }
    }

    private static let zipURL = URL(string: "https://lobbycanada.gc.ca/media/mqbbmaqk/communications_ocl_cal.zip")!

    /// Deep link to the OCL open data page — used as the registryURL on each record
    /// because the OCL website does not provide stable per-record deep links.
    private static let openDataURL = URL(string: "https://lobbycanada.gc.ca/en/open-data/")!

    // MARK: - Session-level Cache (actor-isolated)

    private actor Cache {
        private var commsPerMP: [String: [LobbyistCommunication]] = [:]
        private(set) var isLoaded = false
        private(set) var loadError: Bool = false

        // In-flight download task — prevents a concurrent second 22 MB download when two
        // callers race through fetchCommunications before isLoaded becomes true.
        private var inflightTask: Task<Void, Error>?

        // Parsed tables — populated once on first download.
        private(set) var dpohTable: [String: [(lastName: String, firstName: String, institution: String)]] = [:]
        private(set) var primaryTable: [String: PrimaryRecord] = [:]
        private(set) var subjectTable: [String: [String]] = [:]
        private(set) var smtDescs: [String: String] = [:]

        func markLoaded(dpoh: [String: [(lastName: String, firstName: String, institution: String)]],
                        primary: [String: PrimaryRecord],
                        subjects: [String: [String]],
                        smt: [String: String]) {
            dpohTable    = dpoh
            primaryTable = primary
            subjectTable = subjects
            smtDescs     = smt
            isLoaded     = true
            inflightTask = nil
        }

        func markFailed() {
            loadError    = true
            isLoaded     = true   // prevent infinite retries in one session
            inflightTask = nil
        }

        /// Returns the existing in-flight download task if one is running, otherwise
        /// registers and returns a new one. The check+create is atomic within the actor
        /// so concurrent callers can never create two independent downloads.
        func inflightTaskOrNew(makeTask: () -> Task<Void, Error>) -> (task: Task<Void, Error>, isNew: Bool) {
            if let existing = inflightTask {
                return (existing, false)
            }
            let task = makeTask()
            inflightTask = task
            return (task, true)
        }

        func cached(key: String) -> [LobbyistCommunication]? { commsPerMP[key] }

        func store(_ comms: [LobbyistCommunication], key: String) { commsPerMP[key] = comms }

        /// Returns the number of OCL communication records for the given organization name,
        /// or nil if the dataset has not been loaded yet.
        func communicationCount(forOrganization name: String) -> Int? {
            guard isLoaded, !loadError else { return nil }
            let query = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return primaryTable.values.filter {
                $0.organizationName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == query
            }.count
        }
    }

    private static let cache = Cache()

    // MARK: - Public API

    /// True if the last download attempt failed. Lets callers distinguish
    /// "network error" from "MP has no registered communications".
    static var lastFetchFailed: Bool {
        get async { await cache.loadError }
    }

    /// Returns at most 50 lobbying communications where the MP identified by
    /// `lastName` / `firstName` is the Designated Public Office Holder.
    /// Sorted by date descending. Always returns an array — never throws.
    static func fetchCommunications(lastName: String, firstName: String) async -> [LobbyistCommunication] {
        let key = cacheKey(lastName: lastName, firstName: firstName)

        if let cached = await cache.cached(key: key) { return cached }

        if !(await cache.isLoaded) {
            do {
                try await ensureLoaded()
            } catch {
                await cache.markFailed()
                return []
            }
        }

        if await cache.loadError { return [] }

        let result = await buildCommunications(lastName: lastName, firstName: firstName)
        await cache.store(result, key: key)
        return result
    }

    /// Returns the number of OCL communications for `organizationName` if the dataset is already
    /// loaded, or nil when it has not yet been fetched. Used for witness cross-reference badges
    /// to avoid triggering a 22 MB download solely for badge population.
    static func communicationCount(forOrganization name: String) async -> Int? {
        await cache.communicationCount(forOrganization: name)
    }

    /// Convenience overload that extracts name components from a ParliamentMember.
    /// Must be called on the Main Actor (where the model is accessible).
    @MainActor
    static func fetchCommunications(for member: ParliamentMember) async -> [LobbyistCommunication] {
        let ln = member.lastName
        let fn = member.firstName
        return await fetchCommunications(lastName: ln, firstName: fn)
    }

    // MARK: - Download + Parse

    /// Ensures the ZIP is downloaded and parsed exactly once per session.
    /// Concurrent callers that arrive while the download is in-flight await the
    /// same Task instead of starting a second 22 MB download.
    ///
    /// The check+create is performed inside a single actor call so it is atomic
    /// with respect to other callers — no two tasks are ever registered.
    private static func ensureLoaded() async throws {
        let (task, _) = await cache.inflightTaskOrNew {
            Task<Void, Error> { try await downloadAndParse() }
        }
        try await task.value
    }

    private static func downloadAndParse() async throws {
        var request = URLRequest(url: zipURL, timeoutInterval: Constants.requestTimeout)
        request.cachePolicy = .returnCacheDataElseLoad
        let (data, response) = try await NetworkService.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, Constants.successStatusCodes.contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let (dpoh, primary, subjects, smt) = try parseZip(data)
        await cache.markLoaded(dpoh: dpoh, primary: primary, subjects: subjects, smt: smt)
    }

    // MARK: - ZIP + CSV Parsing

    private static func parseZip(_ data: Data) throws -> (
        dpoh: [String: [(lastName: String, firstName: String, institution: String)]],
        primary: [String: PrimaryRecord],
        subjects: [String: [String]],
        smt: [String: String]
    ) {
        // Names of the entries we need (in order they appear in the archive).
        let dpohEntry     = "Communication_DpohExport.csv"
        let primaryEntry  = "Communication_PrimaryExport.csv"
        let subjectEntry  = "Communication_SubjectMattersExport.csv"
        let smtEntry      = "Codes_SubjectMatterTypesExport.csv"

        let dpohCSV    = try extractZipEntry(named: dpohEntry, from: data)
        let primaryCSV = try extractZipEntry(named: primaryEntry, from: data)
        let subjectCSV = try extractZipEntry(named: subjectEntry, from: data)
        let smtCSV     = try extractZipEntry(named: smtEntry, from: data)

        return (
            parseDpohCSV(dpohCSV),
            parsePrimaryCSV(primaryCSV),
            parseSubjectCSV(subjectCSV),
            parseSmtCSV(smtCSV)
        )
    }

    // MARK: - ZIP Local-File-Header Parser

    /// Scans `zipData` for the local file header matching `name` and decompresses it.
    /// Supports DEFLATE (method 8) and stored (method 0) entries.
    private static func extractZipEntry(named name: String, from zipData: Data) throws -> String {
        let nameBytes = Array(name.utf8)
        var offset = 0

        while offset + Constants.zipLocalFileHeaderLength <= zipData.count {
            guard isLocalFileHeader(in: zipData, at: offset) else {
                // Not a local file header — scan forward looking for next signature.
                // (End of central directory or other record.)
                break
            }

            let header = zipHeader(in: zipData, at: offset)
            let dataStart = offset + Constants.zipLocalFileHeaderLength + header.fileNameLength + header.extraLength

            // Check filename match.
            if entryNameBytes(in: zipData, offset: offset, length: header.fileNameLength) == nameBytes {
                return try decodedZipEntry(from: zipData, dataStart: dataStart, header: header)
            }

            // Advance past this entry.
            offset = dataStart + header.compressedSize
        }

        throw URLError(.cannotParseResponse)
    }

    private static func isLocalFileHeader(in zipData: Data, at offset: Int) -> Bool {
        // Local file header signature: PK\x03\x04
        let sig = zipData[offset..<offset + Constants.localFileSignatureLength]
        return sig.elementsEqual(Constants.localFileHeaderSignature)
    }

    private static func zipHeader(in zipData: Data, at offset: Int) -> ZipHeader {
        ZipHeader(
            method: UInt16(zipData[offset + Constants.zipMethodOffset])
                | (UInt16(zipData[offset + Constants.zipMethodHighByteOffset]) << Constants.byteShift),
            compressedSize: littleEndianInt32(in: zipData, at: offset + Constants.compressedSizeOffset),
            uncompressedSize: littleEndianInt32(in: zipData, at: offset + Constants.uncompressedSizeOffset),
            fileNameLength: Int(
                UInt16(zipData[offset + Constants.fileNameLengthOffset])
                    | (UInt16(zipData[offset + Constants.fileNameLengthHighByteOffset]) << Constants.byteShift)
            ),
            extraLength: Int(
                UInt16(zipData[offset + Constants.extraLengthOffset])
                    | (UInt16(zipData[offset + Constants.extraLengthHighByteOffset]) << Constants.byteShift)
            )
        )
    }

    private static func littleEndianInt32(in data: Data, at offset: Int) -> Int {
        Int(UInt32(data[offset]) |
            (UInt32(data[offset + Constants.littleEndianSecondByteOffset]) << Constants.byteShift) |
            (UInt32(data[offset + Constants.littleEndianThirdByteOffset]) << Constants.shortShift) |
            (UInt32(data[offset + Constants.littleEndianFourthByteOffset]) << Constants.int24Shift))
    }

    private static func entryNameBytes(in zipData: Data, offset: Int, length: Int) -> [UInt8] {
        Array(zipData[
            (offset + Constants.zipLocalFileHeaderLength)..<(offset + Constants.zipLocalFileHeaderLength + length)
        ])
    }

    private static func decodedZipEntry(from zipData: Data, dataStart: Int, header: ZipHeader) throws -> String {
        guard dataStart + header.compressedSize <= zipData.count else {
            throw URLError(.cannotParseResponse)
        }

        let compressedSlice = zipData[dataStart..<(dataStart + header.compressedSize)]
        let raw = try zipEntryData(
            method: header.method,
            compressed: Data(compressedSlice),
            uncompressedSize: header.uncompressedSize
        )

        // The OCL CSVs use Windows Latin-1 (ISO 8859-1 compatible) encoding.
        return String(data: raw, encoding: .isoLatin1)
            ?? String(data: raw, encoding: .utf8)
            ?? ""
    }

    private static func zipEntryData(method: UInt16, compressed: Data, uncompressedSize: Int) throws -> Data {
        switch method {
        case Constants.zipCompressionMethodStored:
            // Stored — no compression.
            return compressed
        case Constants.zipCompressionMethodDeflate:
            // Deflate — decompress.
            return try inflate(compressed, uncompressedSize: uncompressedSize)
        default:
            throw URLError(.cannotParseResponse)
        }
    }

    /// Decompresses raw DEFLATE-compressed bytes (ZIP compression method 8) using libz.
    ///
    /// Apple's Compression framework constant `COMPRESSION_ZLIB` decompresses
    /// **zlib-wrapped** data (RFC 1950: 2-byte header + Adler-32 trailer). ZIP stores
    /// **raw DEFLATE** (RFC 1951) with no header or trailer; passing raw DEFLATE bytes
    /// to `compression_decode_buffer` with `COMPRESSION_ZLIB` always returns 0 (failure).
    ///
    /// The fix uses libz directly with `inflateInit2_` and `windowBits = -15`, which
    /// tells zlib to expect raw DEFLATE with no framing.
    private static func inflate(_ compressed: Data, uncompressedSize: Int) throws -> Data {
        let capacity = max(uncompressedSize, 1)
        var output = Data(count: capacity)
        var totalOut: Int = 0

        try compressed.withUnsafeBytes { srcPtr in
            try output.withUnsafeMutableBytes { dstPtr in
                var stream = z_stream()
                // windowBits = -15 → raw DEFLATE (no zlib header/trailer)
                guard inflateInit2_(&stream,
                                    Constants.rawDeflateWindowBits,
                                    ZLIB_VERSION,
                                    Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                    throw URLError(.cannotParseResponse)
                }
                defer { inflateEnd(&stream) }

                stream.next_in   = UnsafeMutablePointer(mutating: srcPtr.bindMemory(to: UInt8.self).baseAddress!)
                stream.avail_in  = uInt(compressed.count)
                stream.next_out  = dstPtr.bindMemory(to: UInt8.self).baseAddress!
                stream.avail_out = uInt(capacity)

                let status = zlib.inflate(&stream, Z_FINISH)
                guard status == Z_STREAM_END || status == Z_OK else {
                    throw URLError(.cannotParseResponse)
                }
                totalOut = Int(stream.total_out)
            }
        }

        guard totalOut > 0 else { throw URLError(.cannotParseResponse) }
        output.count = totalOut
        return output
    }

    // MARK: - CSV Parsers

    private static func parseDpohCSV(_ csv: String) -> [String: [(lastName: String, firstName: String, institution: String)]] {
        // Header: COMLOG_ID, DPOH_LAST_NM_TCPD, DPOH_FIRST_NM_PRENOM_TCPD, DPOH_TITLE_TITRE_TCPD,
        //         BRANCH_UNIT_DIRECTION_SERVICE, OTHER_INSTITUTION_AUTRE, INSTITUTION
        var result: [String: [(lastName: String, firstName: String, institution: String)]] = [:]
        parseCSVRows(csv, skipHeader: true) { row in
            guard row.count >= Constants.dpohRequiredColumnCount else { return }
            let id   = row[Constants.dpohIDColumn]
            let last = row[Constants.dpohLastNameColumn]
            let first = row[Constants.dpohFirstNameColumn]
            let inst = row[Constants.dpohInstitutionColumn]
            result[id, default: []].append((lastName: last, firstName: first, institution: inst))
        }
        return result
    }

    private static func parsePrimaryCSV(_ csv: String) -> [String: PrimaryRecord] {
        // Header: COMLOG_ID, CLIENT_ORG_CORP_NUM, EN_CLIENT_ORG_CORP_NM_AN, FR_CLIENT_ORG_CORP_NM,
        //         REGISTRANT_NUM_DECLARANT, RGSTRNT_LAST_NM_DCLRNT, RGSTRNT_1ST_NM_PRENOM_DCLRNT,
        //         COMM_DATE, REG_TYPE_ENR, ...
        var result: [String: PrimaryRecord] = [:]
        parseCSVRows(csv, skipHeader: true) { row in
            guard row.count >= Constants.primaryRequiredColumnCount else { return }
            let id      = row[Constants.primaryIDColumn]
            let orgName = row[Constants.primaryEnglishOrgColumn].isEmpty
                ? row[Constants.primaryFrenchOrgColumn]
                : row[Constants.primaryEnglishOrgColumn]
            let regLast = row[Constants.primaryRegistrantLastNameColumn]
            let regFirst = row[Constants.primaryRegistrantFirstNameColumn]
            let dateStr  = row[Constants.primaryDateColumn]
            let regType  = registrantTypeName(row[Constants.primaryRegistrantTypeColumn])
            result[id] = PrimaryRecord(
                organizationName: orgName,
                registrantName: "\(regFirst) \(regLast)".trimmingCharacters(in: .whitespaces),
                communicationDateString: dateStr,
                registrantType: regType
            )
        }
        return result
    }

    private static func parseSubjectCSV(_ csv: String) -> [String: [String]] {
        // Header: COMLOG_ID, SUBJECT_CODE_OBJET, CUSTOM_SUBJ_OBJET_PERSO
        var result: [String: [String]] = [:]
        parseCSVRows(csv, skipHeader: true) { row in
            guard row.count >= Constants.subjectRequiredColumnCount else { return }
            result[row[Constants.subjectIDColumn], default: []].append(row[Constants.subjectCodeColumn])
        }
        return result
    }

    private static func parseSmtCSV(_ csv: String) -> [String: String] {
        // Header: SUBJECT_CODE_OBJET, SMT_EN_DESC, SMT_FR_DESC
        var result: [String: String] = [:]
        parseCSVRows(csv, skipHeader: true) { row in
            guard row.count >= Constants.smtRequiredColumnCount else { return }
            result[row[Constants.smtCodeColumn]] = row[Constants.smtEnglishDescriptionColumn]
        }
        return result
    }

    // MARK: - RFC 4180-compatible CSV Row Parser

    private static func parseCSVRows(_ csv: String, skipHeader: Bool, handler: ([String]) -> Void) {
        var state = CSVParserState()

        var idx = csv.startIndex
        while idx < csv.endIndex {
            let ch   = csv[idx]
            let next = csv.index(after: idx)
            let advancedIndex = processCSVCharacter(
                ch,
                next: next,
                csv: csv,
                state: &state,
                skipHeader: skipHeader,
                handler: handler
            )
            idx = advancedIndex ?? next
        }

        // Handle final row (no trailing newline).
        finishFinalCSVRow(state: &state, skipHeader: skipHeader, handler: handler)
    }

    #if DEBUG
    static func parseCSVRowsForTesting(_ csv: String, skipHeader: Bool = false) -> [[String]] {
        var rows: [[String]] = []
        parseCSVRows(csv, skipHeader: skipHeader) { rows.append($0) }
        return rows
    }
    #endif

    private static func processCSVCharacter(
        _ ch: Character,
        next: String.Index,
        csv: String,
        state: inout CSVParserState,
        skipHeader: Bool,
        handler: ([String]) -> Void
    ) -> String.Index? {
        if state.inQuotes {
            return processQuotedCSVCharacter(ch, next: next, csv: csv, state: &state)
        }

        return processUnquotedCSVCharacter(ch, next: next, csv: csv, state: &state, skipHeader: skipHeader, handler: handler)
    }

    private static func processQuotedCSVCharacter(
        _ ch: Character,
        next: String.Index,
        csv: String,
        state: inout CSVParserState
    ) -> String.Index? {
        guard ch == "\"" else {
            state.currentField.append(ch)
            return nil
        }
        guard next < csv.endIndex && csv[next] == "\"" else {
            state.inQuotes = false
            return nil
        }

        state.currentField.append("\"")
        return csv.index(after: next)
    }

    private static func processUnquotedCSVCharacter(
        _ ch: Character,
        next: String.Index,
        csv: String,
        state: inout CSVParserState,
        skipHeader: Bool,
        handler: ([String]) -> Void
    ) -> String.Index? {
        switch ch {
        case "\"":
            state.inQuotes = true
        case ",":
            appendCSVField(state: &state)
        case "\r", "\n", "\r\n":
            return finishCSVLine(ch, next: next, csv: csv, state: &state, skipHeader: skipHeader, handler: handler)
        default:
            state.currentField.append(ch)
        }
        return nil
    }

    private static func appendCSVField(state: inout CSVParserState) {
        state.currentRow.append(state.currentField)
        state.currentField = ""
    }

    private static func finishCSVLine(
        _ ch: Character,
        next: String.Index,
        csv: String,
        state: inout CSVParserState,
        skipHeader: Bool,
        handler: ([String]) -> Void
    ) -> String.Index? {
        appendCSVField(state: &state)
        emitCSVRow(state: &state, skipHeader: skipHeader, handler: handler)
        return shouldSkipNextLineFeed(after: ch, next: next, csv: csv) ? next : nil
    }

    private static func shouldSkipNextLineFeed(after ch: Character, next: String.Index, csv: String) -> Bool {
        ch == "\r" && next < csv.endIndex && csv[next] == "\n"
    }

    private static func finishFinalCSVRow(
        state: inout CSVParserState,
        skipHeader: Bool,
        handler: ([String]) -> Void
    ) {
        guard !state.currentField.isEmpty || !state.currentRow.isEmpty else { return }
        appendCSVField(state: &state)
        emitCSVRow(state: &state, skipHeader: skipHeader, handler: handler)
    }

    private static func emitCSVRow(state: inout CSVParserState, skipHeader: Bool, handler: ([String]) -> Void) {
        guard !(state.currentRow.count == 1 && state.currentRow[0].isEmpty) else {
            state.currentRow = []
            return
        }
        guard !state.isFirstRow || !skipHeader else {
            state.isFirstRow = false
            state.currentRow = []
            return
        }

        state.isFirstRow = false
        handler(state.currentRow)
        state.currentRow = []
    }

    // MARK: - Build LobbyistCommunication Records

    private static func buildCommunications(lastName: String, firstName: String) async -> [LobbyistCommunication] {
        let dpohTable    = await cache.dpohTable
        let primaryTable = await cache.primaryTable
        let subjectTable = await cache.subjectTable
        let smtDescs     = await cache.smtDescs

        let lastLower  = lastName.lowercased()
        let firstLower = firstName.lowercased()

        var communications: [LobbyistCommunication] = []

        for (comlogID, dpohs) in dpohTable {
            let matched = dpohs.contains { matchesDPOH($0, lastLower: lastLower, firstLower: firstLower) }
            guard matched, let primary = primaryTable[comlogID] else { continue }

            communications.append(LobbyistCommunication(
                id: comlogID,
                lobbyistName: primary.registrantName,
                organizationName: primary.organizationName,
                communicationDate: parseDate(primary.communicationDateString),
                subjectMatter: subjectMatter(for: comlogID, subjectTable: subjectTable, smtDescs: smtDescs),
                registrantType: primary.registrantType,
                registryURL: openDataURL
            ))
        }

        // Sort descending by date; nil dates go last.
        communications.sort(by: sortsByMostRecentCommunication)

        return Array(communications.prefix(Constants.communicationLimit))
    }

    private static func matchesDPOH(
        _ dpoh: (lastName: String, firstName: String, institution: String),
        lastLower: String,
        firstLower: String
    ) -> Bool {
        dpoh.lastName.lowercased() == lastLower &&
        dpoh.firstName.lowercased().contains(firstLower) &&
        dpoh.institution.lowercased().contains("house of commons")
    }

    private static func subjectMatter(
        for comlogID: String,
        subjectTable: [String: [String]],
        smtDescs: [String: String]
    ) -> String {
        let smtCodes = subjectTable[comlogID] ?? []
        let subjectText = smtCodes.compactMap { smtDescs[$0] }.joined(separator: ", ")
        return subjectText.isEmpty
            ? NSLocalizedString("lobbying.subject.unspecified", comment: "")
            : subjectText
    }

    private static func sortsByMostRecentCommunication(
        _ lhs: LobbyistCommunication,
        _ rhs: LobbyistCommunication
    ) -> Bool {
        switch (lhs.communicationDate, rhs.communicationDate) {
        case let (left?, right?): return left > right
        case (_?, nil):          return true
        case (nil, _?):          return false
        case (nil, nil):         return false
        }
    }

    // MARK: - Helpers

    private static func cacheKey(lastName: String, firstName: String) -> String {
        "\(lastName.lowercased())_\(firstName.lowercased())"
    }

    private static let regTypeCodes: [String: String] = [
        "1": "Consultant",
        "2": "In-house (corporation)",
        "3": "In-house (organization)"
    ]
    private static func registrantTypeName(_ code: String) -> String {
        regTypeCodes[code] ?? code
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale  = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    private static func parseDate(_ raw: String) -> Date? {
        dateFormatter.date(from: raw)
    }

    // MARK: - Internal Types

    private struct PrimaryRecord: Sendable {
        let organizationName: String
        let registrantName: String
        let communicationDateString: String
        let registrantType: String
    }

    private struct ZipHeader {
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let fileNameLength: Int
        let extraLength: Int
    }

    private struct CSVParserState {
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        var isFirstRow = true
    }
}
