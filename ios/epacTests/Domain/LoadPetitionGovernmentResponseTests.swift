//
//  LoadPetitionGovernmentResponseTests.swift
//  epacTests
//

@testable import epac
import Foundation
import Testing

@MainActor
struct LoadPetitionGovernmentResponseTests {

    struct StubPetitionGovernmentResponseQueryPort: PetitionGovernmentResponseQueryPort {
        var result: Result<PetitionGovernmentResponse?, Error>

        func fetchGovernmentResponse(for petitionID: String) async throws -> PetitionGovernmentResponse? {
            try result.get()
        }
    }

    @Test func executeReturnsResponseWhenExists() async throws {
        let expectedResponse = PetitionGovernmentResponse(
            text: "This is the official response.",
            tabledOn: Date(),
            respondingMinister: "Minister of Transport"
        )
        let queryPort = StubPetitionGovernmentResponseQueryPort(result: .success(expectedResponse))
        let useCase = LoadPetitionGovernmentResponse(queryPort: queryPort)

        let result = try await useCase.execute(petitionID: "e-1234")

        #expect(result == expectedResponse)
    }

    @Test func executeReturnsNilWhenNoResponse() async throws {
        let queryPort = StubPetitionGovernmentResponseQueryPort(result: .success(nil))
        let useCase = LoadPetitionGovernmentResponse(queryPort: queryPort)

        let result = try await useCase.execute(petitionID: "e-1234")

        #expect(result == nil)
    }

    @Test func executePropagatesErrors() async throws {
        let expectedError = URLError(.badServerResponse)
        let queryPort = StubPetitionGovernmentResponseQueryPort(result: .failure(expectedError))
        let useCase = LoadPetitionGovernmentResponse(queryPort: queryPort)

        await #expect(throws: URLError.self) {
            try await useCase.execute(petitionID: "e-1234")
        }
    }
}
