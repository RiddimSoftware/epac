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
import Compression

struct LobbyistService {

    // MARK: - Constants

    private static let zipURL = URL(string: "https://lobbycanada.gc.ca/media/mqbbmaqk/communications_ocl_cal.zip")!

    /// Deep link to the OCL open data page — used as the registryURL on each record
    /// because the OCL website does not provide stable per-record deep links.
    private static let openDataURL = URL(string: "https://lobbycanada.gc.ca/en/open-data/")!

    // MARK: - Session-level Cache (actor-isolated)

    private actor Cache {
        private var commsPerMP: [String: [LobbyistCommunication]] = [:]
        private(set) var isLoaded = false
        private(set) var loadError: Bool = false

        // Parsed tables — populated once on first download.
        private(set) var dpohTable:    [String: [(lastName: String, firstName: String, institution: String)]] = [:]
        private(set) var primaryTable: [String: PrimaryRecord] = [:]
        private(set) var subjectTable: [String: [String]] = [:]
        private(set) var smtDescs:     [String: String] = [:]

        func markLoaded(dpoh: [String: [(lastName: String, firstName: String, institution: String)]],
                        primary: [String: PrimaryRecord],
                        subjects: [String: [String]],
                        smt: [String: String]) {
            dpohTable    = dpoh
            primaryTable = primary
            subjectTable = subjects
            smtDescs     = smt
            isLoaded     = true
        }

        func markFailed() {
            loadError = true
            isLoaded  = true   // prevent infinite retries in one session
        }

        func cached(key: String) -> [LobbyistCommunication]? { commsPerMP[key] }

        func store(_ comms: [LobbyistCommunication], key: String) { commsPerMP[key] = comms }
    }

    private static let cache = Cache()

    // MARK: - Public API

    /// Returns at most 50 lobbying communications where the MP identified by
    /// `lastName` / `firstName` is the Designated Public Office Holder.
    /// Sorted by date descending. Always returns an array — never throws.
    static func fetchCommunications(lastName: String, firstName: String) async -> [LobbyistCommunication] {
        let key = cacheKey(lastName: lastName, firstName: firstName)

        if let cached = await cache.cached(key: key) { return cached }

        if !(await cache.isLoaded) {
            do {
                try await downloadAndParse()
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

    /// Convenience overload that extracts name components from a ParliamentMember.
    /// Must be called on the Main Actor (where the model is accessible).
    @MainActor
    static func fetchCommunications(for member: ParliamentMember) async -> [LobbyistCommunication] {
        let ln = member.lastName
        let fn = member.firstName
        return await fetchCommunications(lastName: ln, firstName: fn)
    }

    // MARK: - Download + Parse

    private static func downloadAndParse() async throws {
        var request = URLRequest(url: zipURL, timeoutInterval: 60)
        request.cachePolicy = .returnCacheDataElseLoad
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let (dpoh, primary, subjects, smt) = try parseZip(data)
        await cache.markLoaded(dpoh: dpoh, primary: primary, subjects: subjects, smt: smt)
    }

    // MARK: - ZIP + CSV Parsing

    private static func parseZip(_ data: Data) throws -> (
        dpoh:    [String: [(lastName: String, firstName: String, institution: String)]],
        primary: [String: PrimaryRecord],
        subjects:[String: [String]],
        smt:     [String: String]
    ) {
        // Names of the entries we need (in order they appear in the archive).
        let dpohEntry     = "Communication_DpohExport.csv"
        let primaryEntry  = "Communication_PrimaryExport.csv"
        let subjectEntry  = "Communication_SubjectMattersExport.csv"
        let smtEntry      = "Codes_SubjectMatterTypesExport.csv"

        let dpohCSV    = try extractZipEntry(named: dpohEntry,    from: data)
        let primaryCSV = try extractZipEntry(named: primaryEntry,  from: data)
        let subjectCSV = try extractZipEntry(named: subjectEntry,  from: data)
        let smtCSV     = try extractZipEntry(named: smtEntry,      from: data)

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

        while offset + 30 <= zipData.count {
            // Local file header signature: PK\x03\x04
            let sig = zipData[offset..<offset+4]
            guard sig.elementsEqual([0x50, 0x4B, 0x03, 0x04]) else {
                // Not a local file header — scan forward looking for next signature.
                // (End of central directory or other record.)
                break
            }

            let method       = UInt16(zipData[offset + 8]) | (UInt16(zipData[offset + 9]) << 8)
            let compressedSz = Int(UInt32(zipData[offset + 18]) |
                                   (UInt32(zipData[offset + 19]) << 8) |
                                   (UInt32(zipData[offset + 20]) << 16) |
                                   (UInt32(zipData[offset + 21]) << 24))
            let uncompressedSz = Int(UInt32(zipData[offset + 22]) |
                                     (UInt32(zipData[offset + 23]) << 8) |
                                     (UInt32(zipData[offset + 24]) << 16) |
                                     (UInt32(zipData[offset + 25]) << 24))
            let fnLen  = Int(UInt16(zipData[offset + 26]) | (UInt16(zipData[offset + 27]) << 8))
            let extLen = Int(UInt16(zipData[offset + 28]) | (UInt16(zipData[offset + 29]) << 8))

            let dataStart = offset + 30 + fnLen + extLen

            // Check filename match.
            let fnBytes = Array(zipData[(offset + 30)..<(offset + 30 + fnLen)])
            if fnBytes == nameBytes {
                guard dataStart + compressedSz <= zipData.count else {
                    throw URLError(.cannotParseResponse)
                }
                let compressedSlice = zipData[dataStart..<(dataStart + compressedSz)]
                let raw: Data
                switch method {
                case 0:
                    // Stored — no compression.
                    raw = Data(compressedSlice)
                case 8:
                    // Deflate — decompress.
                    raw = try inflate(Data(compressedSlice), uncompressedSize: uncompressedSz)
                default:
                    throw URLError(.cannotParseResponse)
                }
                // The OCL CSVs use Windows Latin-1 (ISO 8859-1 compatible) encoding.
                return String(data: raw, encoding: .isoLatin1)
                    ?? String(data: raw, encoding: .utf8)
                    ?? ""
            }

            // Advance past this entry.
            offset = dataStart + compressedSz
        }

        throw URLError(.cannotParseResponse)
    }

    /// Decompresses raw DEFLATE-compressed bytes using Apple's Compression framework.
    private static func inflate(_ data: Data, uncompressedSize: Int) throws -> Data {
        // Copy input to a raw buffer to avoid overlapping-access errors when
        // both withUnsafeBytes blocks are nested.
        let inputBytes = [UInt8](data)
        var outputBytes = [UInt8](repeating: 0, count: max(uncompressedSize, 1))

        let result = compression_decode_buffer(
            &outputBytes, outputBytes.count,
            inputBytes, inputBytes.count,
            nil,
            COMPRESSION_ZLIB   // raw DEFLATE — matches ZIP compression method 8
        )

        guard result > 0 else { throw URLError(.cannotParseResponse) }
        return Data(outputBytes.prefix(result))
    }

    // MARK: - CSV Parsers

    private static func parseDpohCSV(_ csv: String) -> [String: [(lastName: String, firstName: String, institution: String)]] {
        // Header: COMLOG_ID, DPOH_LAST_NM_TCPD, DPOH_FIRST_NM_PRENOM_TCPD, DPOH_TITLE_TITRE_TCPD,
        //         BRANCH_UNIT_DIRECTION_SERVICE, OTHER_INSTITUTION_AUTRE, INSTITUTION
        var result: [String: [(lastName: String, firstName: String, institution: String)]] = [:]
        parseCSVRows(csv, skipHeader: true) { row in
            guard row.count >= 7 else { return }
            let id   = row[0]
            let last = row[1]
            let first = row[2]
            let inst = row[6]
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
            guard row.count >= 9 else { return }
            let id      = row[0]
            let orgName = row[2].isEmpty ? row[3] : row[2]   // prefer English
            let regLast = row[5]
            let regFirst = row[6]
            let dateStr  = row[7]
            let regType  = registrantTypeName(row[8])
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
            guard row.count >= 2 else { return }
            result[row[0], default: []].append(row[1])
        }
        return result
    }

    private static func parseSmtCSV(_ csv: String) -> [String: String] {
        // Header: SUBJECT_CODE_OBJET, SMT_EN_DESC, SMT_FR_DESC
        var result: [String: String] = [:]
        parseCSVRows(csv, skipHeader: true) { row in
            guard row.count >= 2 else { return }
            result[row[0]] = row[1]
        }
        return result
    }

    // MARK: - RFC 4180-compatible CSV Row Parser

    private static func parseCSVRows(_ csv: String, skipHeader: Bool, handler: ([String]) -> Void) {
        var currentRow:   [String] = []
        var currentField = ""
        var inQuotes     = false
        var isFirstRow   = true

        var idx = csv.startIndex
        while idx < csv.endIndex {
            let ch   = csv[idx]
            let next = csv.index(after: idx)

            if inQuotes {
                if ch == "\"" {
                    if next < csv.endIndex && csv[next] == "\"" {
                        currentField.append("\"")
                        idx = csv.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(ch)
                }
            } else {
                switch ch {
                case "\"":
                    inQuotes = true
                case ",":
                    currentRow.append(currentField)
                    currentField = ""
                case "\r", "\n":
                    if ch == "\r", next < csv.endIndex, csv[next] == "\n" {
                        idx = next
                    }
                    currentRow.append(currentField)
                    currentField = ""
                    let isBlank = currentRow.count == 1 && currentRow[0].isEmpty
                    if !isBlank {
                        if isFirstRow && skipHeader {
                            isFirstRow = false
                        } else {
                            handler(currentRow)
                        }
                    }
                    currentRow = []
                default:
                    currentField.append(ch)
                }
            }
            idx = next
        }
        // Handle final row (no trailing newline).
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            let isBlank = currentRow.count == 1 && currentRow[0].isEmpty
            if !isBlank && !(isFirstRow && skipHeader) {
                handler(currentRow)
            }
        }
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
            let matched = dpohs.contains { dpoh in
                dpoh.lastName.lowercased() == lastLower &&
                dpoh.firstName.lowercased().contains(firstLower) &&
                dpoh.institution.lowercased().contains("house of commons")
            }
            guard matched, let primary = primaryTable[comlogID] else { continue }

            let smtCodes    = subjectTable[comlogID] ?? []
            let subjectText = smtCodes.compactMap { smtDescs[$0] }.joined(separator: ", ")

            communications.append(LobbyistCommunication(
                id: comlogID,
                lobbyistName: primary.registrantName,
                organizationName: primary.organizationName,
                communicationDate: parseDate(primary.communicationDateString),
                subjectMatter: subjectText.isEmpty
                    ? NSLocalizedString("lobbying.subject.unspecified", comment: "")
                    : subjectText,
                registrantType: primary.registrantType,
                registryURL: openDataURL
            ))
        }

        // Sort descending by date; nil dates go last.
        communications.sort {
            switch ($0.communicationDate, $1.communicationDate) {
            case let (a?, b?): return a > b
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return false
            }
        }

        return Array(communications.prefix(50))
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
}
