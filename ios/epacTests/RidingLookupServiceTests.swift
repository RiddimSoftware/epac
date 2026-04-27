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
            try await service.lookup(postalCode: "")
        }
    }

    @Test func tooShortCodeIsInvalid() async throws {
        await #expect(throws: RidingLookupError.invalidPostalCode) {
            try await service.lookup(postalCode: "K1A")
        }
    }

    @Test func numericOnlyCodeIsInvalid() async throws {
        await #expect(throws: RidingLookupError.invalidPostalCode) {
            try await service.lookup(postalCode: "123456")
        }
    }

    @Test func usZipCodeIsInvalid() async throws {
        await #expect(throws: RidingLookupError.invalidPostalCode) {
            try await service.lookup(postalCode: "10001")
        }
    }

    @Test func wrongPatternIsInvalid() async throws {
        // Must be letter-digit-letter-digit-letter-digit; two leading letters is wrong.
        await #expect(throws: RidingLookupError.invalidPostalCode) {
            try await service.lookup(postalCode: "KK1A0A")
        }
    }

    // MARK: - Valid postal codes (whitespace normalisation)

    // These reach the network and throw .networkError (or succeed) rather than
    // .invalidPostalCode, confirming the validator accepted the code.
    @Test func validCodeWithSpaceDoesNotThrowInvalidPostalCode() async {
        do {
            _ = try await service.lookup(postalCode: "K1A 0A6")
            // If the live API responds successfully, the test passes.
        } catch RidingLookupError.invalidPostalCode {
            Issue.record("K1A 0A6 should be accepted as a valid postal code format")
        } catch {
            // networkError, noResults, noFederalRepresentative are all acceptable:
            // the format was valid; only the server response determines the rest.
        }
    }

    @Test func validLowercaseCodeDoesNotThrowInvalidPostalCode() async {
        do {
            _ = try await service.lookup(postalCode: "k1a0a6")
        } catch RidingLookupError.invalidPostalCode {
            Issue.record("k1a0a6 should be accepted after uppercasing")
        } catch {
            // Any non-invalidPostalCode error is fine.
        }
    }
}
