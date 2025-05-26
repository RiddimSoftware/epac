//
//  Logging.swift
//  prompty
//
//  Created by Sunny on 2024-10-25.
//

import Logging

actor Log {
	private static var logger = {
		var logger = Logger(label: "com.riddimsoftware.epac")
		#if DEBUG
		logger.logLevel = .trace
		#else
		logger.logLevel = .warning
		#endif
		return logger
	}()
	static func setLevel(_ level: Logger.Level) {
		logger.logLevel = level
	}
	static func debug(_ message: Logger.Message) {
		logger.log(level: .debug, message)
	}
	static func info(_ message: Logger.Message) {
		logger.log(level: .info, message)
	}
	static func verbose(_ message: Logger.Message) {
		logger.log(level: .trace, message)
	}
	static func error(_ message: Logger.Message) {
		logger.log(level: .error, message)
	}
	static func warning(_ message: Logger.Message) {
		logger.log(level: .warning, message)
	}
}
