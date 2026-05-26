//
//  SwiftDataStoreRecovery.swift
//  epac
//

import Foundation
import OSLog
import SwiftData

enum SwiftDataStoreRecoveryError: Error, CustomStringConvertible {
	case deleteFailed(initialOpenError: any Error, deleteError: any Error)
	case retryFailed(initialOpenError: any Error, retryError: any Error)

	var description: String {
		switch self {
		case let .deleteFailed(initialOpenError, deleteError):
			"SwiftData cache recovery could not delete the local store after open failed. initialOpenError=\(initialOpenError) deleteError=\(deleteError)"
		case let .retryFailed(initialOpenError, retryError):
			"SwiftData cache recovery retried once after deleting the local store, but open still failed. initialOpenError=\(initialOpenError) retryError=\(retryError)"
		}
	}
}

enum SwiftDataStoreRecovery {
	private static let logger = Logger(subsystem: "com.riddimsoftware.epac", category: "SwiftDataStoreRecovery")
	private static let defaultStoreFilename = "default.store"
	private static let sqliteSidecarSuffixes = ["", "-shm", "-wal", "-journal"]

	static var defaultStoreURL: URL {
		FileManager.default
			.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
			.appendingPathComponent(defaultStoreFilename)
	}

	static func makeContainer<Container>(
		usesInMemoryStore: Bool,
		storeURL: URL = defaultStoreURL,
		makeContainer: (ModelConfiguration) throws -> Container
	) throws -> Container {
		try prepareStoreDirectoryIfNeeded(usesInMemoryStore: usesInMemoryStore, storeURL: storeURL)
		let configuration = modelConfiguration(usesInMemoryStore: usesInMemoryStore, storeURL: storeURL)

		do {
			return try makeContainer(configuration)
		} catch {
			return try recoverContainer(
				configuration: configuration,
				usesInMemoryStore: usesInMemoryStore,
				storeURL: storeURL,
				initialOpenError: error,
				makeContainer: makeContainer
			)
		}
	}

	static func storeFileURLs(for storeURL: URL) -> [URL] {
		sqliteSidecarSuffixes.map { suffix in
			URL(fileURLWithPath: storeURL.path + suffix)
		}
	}

	static func deleteStoreFiles(at storeURL: URL, fileManager: FileManager = .default) throws {
		for fileURL in storeFileURLs(for: storeURL) where fileManager.fileExists(atPath: fileURL.path) {
			try fileManager.removeItem(at: fileURL)
		}
	}

	private static func modelConfiguration(usesInMemoryStore: Bool, storeURL: URL) -> ModelConfiguration {
		if usesInMemoryStore {
			ModelConfiguration(isStoredInMemoryOnly: true)
		} else {
			ModelConfiguration(url: storeURL)
		}
	}

	private static func prepareStoreDirectoryIfNeeded(usesInMemoryStore: Bool, storeURL: URL) throws {
		guard !usesInMemoryStore else { return }

		try FileManager.default.createDirectory(
			at: storeURL.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
	}

	private static func recoverContainer<Container>(
		configuration: ModelConfiguration,
		usesInMemoryStore: Bool,
		storeURL: URL,
		initialOpenError: any Error,
		makeContainer: (ModelConfiguration) throws -> Container
	) throws -> Container {
		guard !usesInMemoryStore else {
			throw initialOpenError
		}

		logger.error("SwiftData open failed; deleting local cache store and retrying once. storeFile=\(storeURL.lastPathComponent, privacy: .public) error=\(String(describing: initialOpenError), privacy: .public)")

		do {
			try deleteStoreFiles(at: storeURL)
		} catch {
			logger.fault("SwiftData cache store deletion failed. storeFile=\(storeURL.lastPathComponent, privacy: .public) error=\(String(describing: error), privacy: .public)")
			throw SwiftDataStoreRecoveryError.deleteFailed(initialOpenError: initialOpenError, deleteError: error)
		}

		do {
			return try makeContainer(configuration)
		} catch {
			logger.fault("SwiftData open failed after one destructive cache recovery attempt. storeFile=\(storeURL.lastPathComponent, privacy: .public) error=\(String(describing: error), privacy: .public)")
			throw SwiftDataStoreRecoveryError.retryFailed(initialOpenError: initialOpenError, retryError: error)
		}
	}
}
