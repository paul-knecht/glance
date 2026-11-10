import Foundation

// The text the user selected in another app, plus what we know about it.
struct Selection: Equatable {

    // The selected text, without spaces or line breaks around it.
    let text: String

    // The sentence around a selected word, if the other app let us read it.
    let context: String?

    // Where the selection is on screen (AppKit coordinates), if known.
    let anchor: CGRect?

    // Longer selections are refused instead of being cut short.
    static let maxLength = 20_000

    init(text: String, context: String?, anchor: CGRect?) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.context = context
        self.anchor = anchor
    }

    // True for a word or short phrase (up to three words), which gets the
    // dictionary-style answer. Anything longer is treated as a passage.
    var isWord: Bool {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        return (1...3).contains(words.count) && text.count <= 60
    }
}
