//
//  Logging.swift
//  prompty
//
//  Created by Sunny on 2024-10-25.
//

import Logging

actor Log {
	 private var logger: Logger = {
		var logger = Logger(label: "com.riddimsoftware.epac")
		#if DEBUG
		logger.logLevel = .trace
		#else
		logger.logLevel = .warning
		#endif
		return logger
	}()

	static let shared = Log()

	private func setLevel(_ level: Logger.Level) {
		logger.logLevel = level
	}

	private func log(level: Logger.Level, _ message: Logger.Message) {
		logger.log(level: level, message)
	}

	static func setLevel(_ level: Logger.Level) {
		Task { await shared.setLevel(level) }
	}

	static func debug(_ message: Logger.Message) {
		Task { await shared.log(level: .debug, message) }
	}

	static func info(_ message: Logger.Message) {
		Task { await shared.log(level: .info, message) }
	}

	static func verbose(_ message: Logger.Message) {
		Task { await shared.log(level: .trace, message) }
	}

	static func error(_ message: Logger.Message) {
		Task { await shared.log(level: .error, message) }
	}

	static func warning(_ message: Logger.Message) {
		Task { await shared.log(level: .warning, message) }
	}
}
