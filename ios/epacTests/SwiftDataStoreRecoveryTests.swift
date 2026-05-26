@testable import epac
import Foundation
import SwiftData
import Testing

private enum TestOpenError: Error {
	case failed
}

struct SwiftDataStoreRecoveryTests {

	@Test func compatibleStoreDoesNotWipeCache() throws {
		let storeURL = try makeTemporaryStoreURL()
		try "cache".write(to: storeURL, atomically: true, encoding: .utf8)
		var attempts = 0

		let result = try SwiftDataStoreRecovery.makeContainer(
			usesInMemoryStore: false,
			storeURL: storeURL
		) { _ in
			attempts += 1
			return "opened"
		}

		#expect(result == "opened")
		#expect(attempts == 1)
		#expect(FileManager.default.fileExists(atPath: storeURL.path))
	}

	@Test func firstOpenFailureDeletesStoreFilesAndRetriesOnce() throws {
		let storeURL = try makeTemporaryStoreURL()
		let sidecarURLs = SwiftDataStoreRecovery.storeFileURLs(for: storeURL)
		for fileURL in sidecarURLs {
			try "cache".write(to: fileURL, atomically: true, encoding: .utf8)
		}
		var attempts = 0

		let result = try SwiftDataStoreRecovery.makeContainer(
			usesInMemoryStore: false,
			storeURL: storeURL
		) { _ in
			attempts += 1
			if attempts == 1 {
				throw TestOpenError.failed
			}
			return "opened after recovery"
		}

		#expect(result == "opened after recovery")
		#expect(attempts == 2)
		for fileURL in sidecarURLs {
			#expect(!FileManager.default.fileExists(atPath: fileURL.path))
		}
	}

	@Test func retryFailureThrowsTerminalErrorWithoutLooping() throws {
		let storeURL = try makeTemporaryStoreURL()
		try "cache".write(to: storeURL, atomically: true, encoding: .utf8)
		var attempts = 0

		do {
			_ = try SwiftDataStoreRecovery.makeContainer(
				usesInMemoryStore: false,
				storeURL: storeURL
			) { _ in
				attempts += 1
				throw TestOpenError.failed
			}
			Issue.record("Expected destructive recovery retry to throw")
		} catch SwiftDataStoreRecoveryError.retryFailed {
			#expect(attempts == 2)
		} catch {
			Issue.record("Expected retryFailed, got \(error)")
		}
	}

	@Test func inMemoryStoreFailureDoesNotDeleteDiskCache() throws {
		let storeURL = try makeTemporaryStoreURL()
		try "cache".write(to: storeURL, atomically: true, encoding: .utf8)
		var attempts = 0

		do {
			_ = try SwiftDataStoreRecovery.makeContainer(
				usesInMemoryStore: true,
				storeURL: storeURL
			) { _ in
				attempts += 1
				throw TestOpenError.failed
			}
			Issue.record("Expected in-memory open failure to throw")
		} catch {
			#expect(attempts == 1)
			#expect(FileManager.default.fileExists(atPath: storeURL.path))
		}
	}

	private func makeTemporaryStoreURL() throws -> URL {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory.appendingPathComponent("default.store")
	}
}
