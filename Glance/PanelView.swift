import SwiftUI

// What the panel looks like. It only displays what PanelModel holds.
struct PanelView: View {
    @ObservedObject var model: PanelModel

    // Called whenever the panel's height changes, so the window can follow.
    var onHeightChange: (CGFloat) -> Void = { _ in }

    // The tab the mouse pointer is over, if any. Its shortcut hint is shown.
    @State private var hoveredTab: Action?

    // How tall the answer is, so the scrolling area is only as tall as needed.
    @State private var answerHeight: CGFloat = 0

    // The same for the answer to the user's own question.
    @State private var questionAnswerHeight: CGFloat = 0

    // The two answer areas never grow beyond these; longer answers scroll.
    // Together with the tabs, the field and the footer that keeps the panel
    // at roughly 460 points at most.
    private let maxAnswerHeight: CGFloat = 220
    private let maxQuestionAnswerHeight: CGFloat = 110

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let notice = model.notice {
                noticeView(notice)
            } else {
                tabBar
                answerArea
                questionArea
            }
            footer
        }
        .padding(12)
        .frame(width: 380, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        // Always take the height the content needs, even while the window is
        // still catching up.
        .fixedSize(horizontal: false, vertical: true)
        // Report our height to the window.
        .background(GeometryReader { geometry in
            Color.clear.preference(key: PanelHeightKey.self, value: geometry.size.height)
        })
        .onPreferenceChange(PanelHeightKey.self) { onHeightChange($0) }
    }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Action.allCases, id: \.self) { tab in
                Button {
                    model.select(tab)
                } label: {
                    VStack(spacing: 0) {
                        Text(tab.title)
                            .font(.system(size: 12, weight: model.selectedTab == tab ? .semibold : .regular))
                        // The hint always takes up its space, so nothing jumps on hover.
                        Text("⌘\(tab.rawValue + 1)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .opacity(hoveredTab == tab ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .background(model.selectedTab == tab ? Color(nsColor: .controlBackgroundColor) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { hoveredTab = tab } else if hoveredTab == tab { hoveredTab = nil }
                }
            }
        }
        .padding(2)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Answer

    private var answerArea: some View {
        ScrollView {
            answerContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: AnswerHeightKey.self, value: geometry.size.height)
                })
        }
        .frame(height: min(max(answerHeight, 20), maxAnswerHeight))
        .onPreferenceChange(AnswerHeightKey.self) { answerHeight = $0 }
    }

    // The answer of the tab being shown.
    @ViewBuilder
    private var answerContent: some View {
        let state = model.answers[model.selectedTab] ?? .idle
        let isWordLookup = model.selectedTab == .explain && model.selection?.isWord == true

        VStack(alignment: .leading, spacing: 8) {
            if isWordLookup {
                wordAnswer(state.text)
            } else {
                if model.selectedTab == .explain, let selection = model.selection {
                    quote(selection.text)
                    if !state.text.isEmpty { label("In plain words") }
                }
                if !state.text.isEmpty {
                    Text(state.text).font(.system(size: 13))
                }
            }
            statusLine(state)
        }
    }

    // The dictionary-style layout for a word: word, part of speech, labelled sections.
    @ViewBuilder
    private func wordAnswer(_ text: String) -> some View {
        let answer = AnswerFormatter.wordSections(from: text)

        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(model.selection?.text ?? "").font(.system(size: 17, weight: .semibold))
            if let part = answer.part {
                Text(part).font(.system(size: 12)).italic().foregroundStyle(.secondary)
            }
        }
        ForEach(answer.sections) { section in
            VStack(alignment: .leading, spacing: 2) {
                if let title = section.label { label(title) }
                Text(section.text).font(.system(size: 13))
            }
        }
    }

    // "…" while waiting, or the reason an answer failed.
    @ViewBuilder
    private func statusLine(_ state: AnswerState) -> some View {
        switch state {
        case .loading:
            Text("…").foregroundStyle(.secondary)
        case .failed(_, let message):
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
        case .idle, .streaming, .done:
            EmptyView()
        }
    }

    // The start of the selected passage, shown as a quote.
    private func quote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .padding(.leading, 8)
            .overlay(alignment: .leading) {
                Rectangle().fill(.tertiary).frame(width: 3)
            }
    }

    // A small uppercase heading such as "DEFINITION".
    private func label(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10))
            .kerning(0.6)
            .foregroundStyle(.secondary)
    }

    // MARK: - Question

    private var questionArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Ask about the selection…", text: $model.question)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit { model.ask() }

            if model.questionAnswer != .idle {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if !model.questionAnswer.text.isEmpty {
                            Text(model.questionAnswer.text).font(.system(size: 13))
                        }
                        statusLine(model.questionAnswer)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: QuestionAnswerHeightKey.self, value: geometry.size.height)
                    })
                }
                .frame(height: min(max(questionAnswerHeight, 16), maxQuestionAnswerHeight))
                .onPreferenceChange(QuestionAnswerHeightKey.self) { questionAnswerHeight = $0 }
            }
        }
    }

    // MARK: - Notices and footer

    @ViewBuilder
    private func noticeView(_ notice: PanelNotice) -> some View {
        switch notice {
        case .needsPermission:
            Text("Glance needs the Accessibility permission to read the text you selected in other apps.")
                .font(.system(size: 13))
            Button("Open System Settings") {
                SelectionReader.openPermissionSettings()
            }
        case .nothingSelected:
            Text("Select some text first, then press ⌃⌥Space.").font(.system(size: 13))
        case .tooLong:
            Text("The selection is too long. The limit is 20,000 characters.").font(.system(size: 13))
        }
    }

    private var footer: some View {
        HStack {
            if model.notice == nil {
                Text(model.justCopied ? "Copied" : "⌘C copy")
            }
            Spacer()
            Text("esc to close")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
}

// Carries the panel's height from the view up to the window.
private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// Carries the height of the question's answer to its scrolling area.
private struct QuestionAnswerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// Carries the answer's height to the scrolling area.
private struct AnswerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
