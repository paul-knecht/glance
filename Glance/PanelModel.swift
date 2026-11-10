import Foundation

// How far one answer has got.
enum AnswerState: Equatable {
    case idle                                   // not asked for yet
    case loading                                // asked, nothing has arrived
    case streaming(String)                      // the text so far
    case done(String)                           // the complete answer
    case failed(text: String, message: String)  // what arrived, and what went wrong

    // The answer's text, however far it got.
    var text: String {
        switch self {
        case .idle, .loading: return ""
        case .streaming(let text), .done(let text): return text
        case .failed(let text, _): return text
        }
    }
}

// Reasons the panel shows a notice instead of answers.
enum PanelNotice: Equatable {
    case needsPermission
    case nothingSelected
    case tooLong
}

// Holds everything the panel shows and starts the requests to Claude.
// The view only displays this; all decisions are made here.
@MainActor
final class PanelModel: ObservableObject {

    @Published var selection: Selection?
    @Published var notice: PanelNotice?
    @Published var selectedTab: Action = .explain
    @Published var answers: [Action: AnswerState] = [:]
    @Published var question = ""
    @Published var questionAnswer: AnswerState = .idle

    // What ⌘C copies: the tab being shown, or the question's answer.
    private enum CopySource { case tab, question }
    private var copySource = CopySource.tab

    // The real pieces, passed in so that tests can replace them.
    private let loadKey: () -> String?
    private let stream: (String, String, String?) -> AsyncThrowingStream<String, Error>

    // Requests that are still running.
    private var tabTasks: [Action: Task<Void, Never>] = [:]
    private var questionTask: Task<Void, Never>?

    // Goes up every time the panel opens or closes. An answer that belongs
    // to an older number is thrown away, so text from a previous look-up
    // can never show up in a new one.
    private var generation = 0

    // The same idea for questions: only the newest question may show its answer.
    private var questionNumber = 0

    init(loadKey: @escaping () -> String?,
         stream: @escaping (String, String, String?) -> AsyncThrowingStream<String, Error>) {
        self.loadKey = loadKey
        self.stream = stream
        reset()
    }

    // Called when the hotkey is pressed: start a fresh look-up.
    func open(selection: Selection?, hasPermission: Bool) {
        reset()

        if !hasPermission {
            notice = .needsPermission
        } else if selection == nil || selection!.text.isEmpty {
            notice = .nothingSelected
        } else if selection!.text.count > Selection.maxLength {
            notice = .tooLong
        } else {
            self.selection = selection
            load(.explain)
        }
    }

    // Called when the panel closes: stop everything.
    func close() {
        reset()
    }

    // Shows a tab. Its answer is fetched the first time (or again after a failure).
    func select(_ tab: Action) {
        guard selection != nil else { return }
        selectedTab = tab
        copySource = .tab

        switch answers[tab] ?? .idle {
        case .idle, .failed: load(tab)
        case .loading, .streaming, .done: break
        }
    }

    // Sends the typed question about the selection.
    func ask() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let selection, !text.isEmpty else { return }

        questionTask?.cancel()
        questionNumber += 1
        let number = questionNumber
        let generation = self.generation
        copySource = .question
        questionAnswer = .loading

        questionTask = Task {
            await run(user: Prompts.user(question: text, selection: selection)) { [weak self] state in
                guard let self, self.generation == generation, self.questionNumber == number else { return }
                self.questionAnswer = state
            }
        }
    }

    // The text ⌘C should copy, or nil if there is nothing yet.
    var textToCopy: String? {
        var text: String
        switch copySource {
        case .question:
            text = questionAnswer.text
        case .tab:
            text = (answers[selectedTab] ?? .idle).text
            // A word look-up is stored as labelled lines; copy it in readable form.
            if selectedTab == .explain, selection?.isWord == true {
                text = AnswerFormatter.plainText(from: text)
            }
        }
        return text.isEmpty ? nil : text
    }

    // Fetches the answer for one tab.
    private func load(_ tab: Action) {
        guard let selection else { return }
        tabTasks[tab]?.cancel()
        let generation = self.generation
        answers[tab] = .loading

        tabTasks[tab] = Task {
            await run(user: Prompts.user(for: tab, selection: selection)) { [weak self] state in
                guard let self, self.generation == generation else { return }
                self.answers[tab] = state
            }
        }
    }

    // Runs one request and reports each step through `update`.
    private func run(user: String, update: @escaping (AnswerState) -> Void) async {
        var text = ""
        do {
            for try await chunk in stream(Prompts.system, user, loadKey()) {
                text += chunk
                update(.streaming(text))
            }
            // A cancelled request ends quietly; it must not look finished.
            if Task.isCancelled { return }
            update(.done(text))
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            let message = (error as? ClaudeError ?? .failed).message
            update(.failed(text: text, message: message))
        }
    }

    // Stops all requests and clears the panel.
    private func reset() {
        generation += 1
        tabTasks.values.forEach { $0.cancel() }
        tabTasks = [:]
        questionTask?.cancel()
        questionTask = nil

        selection = nil
        notice = nil
        selectedTab = .explain
        answers = Dictionary(uniqueKeysWithValues: Action.allCases.map { ($0, AnswerState.idle) })
        question = ""
        questionAnswer = .idle
        copySource = .tab
    }
}
