import Foundation

// Cuts the sentence that contains a selected word out of a longer text.
// The sentence is sent along so the explanation fits the context.
enum SentenceFinder {

    // Characters that end a sentence.
    private static let enders: Set<Character> = [".", "!", "?"]

    // Returns the sentence around `range`, or nil if there is nothing more
    // than the selected text itself.
    static func sentence(in text: String, around range: Range<String.Index>) -> String? {
        // Walk left until the character before us ends a sentence or a line.
        var start = range.lowerBound
        while start > text.startIndex {
            let previous = text[text.index(before: start)]
            if enders.contains(previous) || previous.isNewline { break }
            start = text.index(before: start)
        }

        // Walk right until we have passed a sentence end, or reach a line break.
        var end = range.upperBound
        while end < text.endIndex {
            let character = text[end]
            if character.isNewline { break }
            end = text.index(after: end)
            if enders.contains(character) { break }
        }

        let sentence = text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = text[range].trimmingCharacters(in: .whitespacesAndNewlines)

        // If the "sentence" is just the selection (maybe with a full stop), it adds nothing.
        let bare = sentence.trimmingCharacters(in: CharacterSet(charactersIn: ".!?").union(.whitespaces))
        if bare.isEmpty || bare == selected { return nil }
        return sentence
    }
}
