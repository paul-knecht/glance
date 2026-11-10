import Foundation

// One labelled part of a word look-up, for example "Definition".
struct AnswerSection: Equatable, Identifiable {
    let label: String?
    let text: String

    // Its position in the answer, so the list can tell sections apart.
    let id: Int
}

// For a word, Claude answers with lines like "DEFINITION: …". This turns
// those lines into the sections the panel shows. It is called again each
// time more of the answer arrives, so it must cope with half-finished text.
enum AnswerFormatter {

    // The labels Claude writes, and what the panel shows for each.
    private static let labels: [(key: String, label: String)] = [
        ("DEFINITION", "Definition"),
        ("GERMAN", "German"),
        ("ENGLISH", "English"),
        ("CONTEXT", "In this sentence"),
        ("USE", "In use"),
    ]

    static func wordSections(from text: String) -> (part: String?, sections: [AnswerSection]) {
        var part: String?
        // Sections as (label, text) while we build them.
        var parts: [(label: String?, text: String)] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = clean(rawLine)
            if line.isEmpty { continue }

            if let value = value(of: "PART", in: line) {
                if !value.isEmpty { part = value }
            } else if let (label, value) = labelledValue(in: line) {
                // A label with nothing after it yet is not shown.
                if !value.isEmpty { parts.append((label, value)) }
            } else if isStartOfAKey(line) {
                // The line is still arriving ("DEFIN"); wait for the rest.
                continue
            } else if let last = parts.indices.last {
                // A line without a label continues the section above it.
                parts[last].text += "\n" + line
            } else {
                parts.append((nil, line))
            }
        }

        let sections = parts.enumerated().map { index, part in
            AnswerSection(label: part.label, text: part.text, id: index)
        }
        return (part, sections)
    }

    // The same answer as simple "Label: text" lines, for copying.
    static func plainText(from text: String) -> String {
        wordSections(from: text).sections.map { section in
            if let label = section.label { return "\(label): \(section.text)" }
            return section.text
        }.joined(separator: "\n")
    }

    // Removes list markers and Markdown stars that the model sometimes adds.
    private static func clean(_ line: String) -> String {
        var result = line.trimmingCharacters(in: .whitespaces)
        while let first = result.first, first == "-" || first == "*" || first == " " {
            result.removeFirst()
        }
        return result
    }

    // If the line starts with "KEY:", returns what follows it.
    private static func value(of key: String, in line: String) -> String? {
        guard line.uppercased().hasPrefix(key) else { return nil }
        var rest = line.dropFirst(key.count)
        // Skip stars between the key and the colon, as in "**KEY:** text".
        while rest.first == "*" { rest.removeFirst() }
        guard rest.first == ":" else { return nil }
        rest.removeFirst()
        while let first = rest.first, first == "*" || first == " " { rest.removeFirst() }
        return String(rest).trimmingCharacters(in: .whitespaces)
    }

    private static func labelledValue(in line: String) -> (String, String)? {
        for (key, label) in labels {
            if let value = value(of: key, in: line) { return (label, value) }
        }
        return nil
    }

    // True if the line could be the beginning of "PART:", "DEFINITION:" and so on.
    private static func isStartOfAKey(_ line: String) -> Bool {
        let upper = line.uppercased()
        let keys = ["PART"] + labels.map(\.key)
        return keys.contains { ($0 + ":").hasPrefix(upper) }
    }
}
