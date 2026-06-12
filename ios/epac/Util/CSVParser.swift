import Foundation

struct CSVParser {
	private let lines: AsyncStream<String>

	init(file: URL) {
		self.lines = AsyncStream { continuation in
			Task {
				do {
					for try await line in file.lines {
						continuation.yield(line)
					}
				} catch {
					Log.error("CSVParser error: \(error.localizedDescription)")
				}
				continuation.finish()
			}
		}
	}

	init(content: String) {
		self.lines = AsyncStream { continuation in
			for line in content.components(separatedBy: .newlines) {
				if !line.isEmpty {
					continuation.yield(line)
				}
			}
			continuation.finish()
		}
	}

	func parse() -> AsyncStream<[String]> {
		AsyncStream { continuation in
			Task {
				for await line in lines {
					let row = parseLine(line)
					continuation.yield(row)
				}
				continuation.finish()
			}
		}
	}

	private func parseLine(_ line: String) -> [String] {
		var fields: [String] = []
		var currentField = ""
		var insideQuotes = false

		let chars = Array(line)
		var i = 0
		while i < chars.count {
			let char = chars[i]
			if char == "\"" {
				if insideQuotes && i + 1 < chars.count && chars[i+1] == "\"" {
					currentField.append("\"")
					i += 1
				} else {
					insideQuotes.toggle()
				}
			} else if char == "," && !insideQuotes {
				fields.append(currentField.trimmingCharacters(in: .whitespaces))
				currentField = ""
			} else {
				currentField.append(char)
			}
			i += 1
		}
		fields.append(currentField.trimmingCharacters(in: .whitespaces))
		return fields
	}
}
