import Testing
import Foundation
@testable import epac

// RidingLookupService throws .invalidPostalCode before making any network
// request, so postal-code validation cases are fully testable without a
// live server. The lookup flow beyond validation is not tested here because
// it requires stubbing URLSession, which is out of scope for this ticket.
struct RidingLookupServiceTests {

    private let service = RidingLookupService()

    // MARK: - Invalid postal codes

    @Test func emptyStringIsInvalid() async throws {
        await #expect(throws: RidingLookupError.invalidPostalCode) {
            try await service.lookupRiding(postalCode: "")
        }
    }

    @Test func tooShortCodeIsInvalid() async throws {
        await #expect(throws: RidingLookupError.invalidPostalCode) {
            try await service.lookupRiding(postalCode: "K1A")
        }
    }

    @Test func numericOnlyCodeIsInvalid() async throws {
        await #expect(throws: RidingLookupError.invalidPostalCode) {
            try await service.lookupRiding(postalCode: "123456")
        }
    }

    @Test func usZipCodeIsInvalid() async throws {
        await #expect(throws: RidingLookupError.invalidPostalCode) {
            try await service.lookupRiding(postalCode: "10001")
        }
    }

    @Test func wrongPatternIsInvalid() async throws {
        // Must be letter-digit-letter-digit-letter-digit; two leading letters is wrong.
        await #expect(throws: RidingLookupError.invalidPostalCode) {
            try await service.lookupRiding(postalCode: "KK1A0A")
        }
    }

    // MARK: - Valid postal codes (whitespace normalisation)

    // These reach the network and throw .networkError (or succeed) rather than
    // .invalidPostalCode, confirming the validator accepted the code.
    @Test func validCodeWithSpaceDoesNotThrowInvalidPostalCode() async {
        do {
            _ = try await service.lookupRiding(postalCode: "K1A 0A6")
        } catch RidingLookupError.invalidPostalCode {
            Issue.record("K1A 0A6 should be accepted as a valid postal code format")
        } catch {
            // networkError, noResults, noFederalRepresentative are all acceptable.
        }
    }

    @Test func validLowercaseCodeDoesNotThrowInvalidPostalCode() async {
        do {
            _ = try await service.lookupRiding(postalCode: "k1a0a6")
        } catch RidingLookupError.invalidPostalCode {
            Issue.record("k1a0a6 should be accepted after uppercasing")
        } catch {
            // Any non-invalidPostalCode error is fine.
        }
    }

    // MARK: - Riding name normalisation

    @Test func normalizeEmDashToHyphen() {
        let result = RidingLookupService.normalizeRidingName("Spadina\u{2014}Fort York")
        #expect(result == "spadina-fort york")
    }

    @Test func normalizeDiacritics() {
        let result = RidingLookupService.normalizeRidingName("Berthier\u{2014}Maskinongé")
        #expect(result == "berthier-maskinonge")
    }
}
