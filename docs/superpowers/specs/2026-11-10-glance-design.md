# Glance — design

Date: 2026-11-10
Status: approved in conversation on 2026-11-10 (the idea, the panel and the
defaults); this document records it.

"Glance" is a working name and may change. Lines marked **(Claude's call)**
are defaults Claude chose that the user accepted with "that works" or that
Claude settled while writing this document; any of them can be changed.
Everything else is what the user decided.

## Intent and why

While reading on the Mac (an article, a PDF, an email), the user wants to look
something up without leaving the app: what a word means, how it translates,
what a passage is saying. He compared it to the strong click on the trackpad
(Look Up): one action, and the answer appears right next to the text. Glance
does that with Claude's answer, and adds summarising, rewriting and asking
his own question about the selection.

The user is a beginner learning Swift, Xcode and Git through these projects.
The code must stay simple enough for him to read. This is the fourth project
in the series and reuses the patterns of KeyPeek (`~/Developer/keypeek`).

## Goals (version 1)

1. Select text in any app, press a global hotkey, and a small floating panel
   opens near the selection with the answer already loading (instant answer).
2. A tab bar on top with four tabs: Explain, Translate, Summarise, Rewrite.
   `⌘1` to `⌘4` switch tabs. The shortcut hint for a tab appears only while
   the pointer hovers over it.
3. The first tab (Explain) loads as the panel opens. Each other tab loads the
   first time it is opened and keeps its answer while the panel is open.
4. Explain for a single word shows a definition, the German translation and a
   short explanation in context. For a passage it shows a short explanation in
   plain words.
5. A text field for the user's own question about the selection; the answer
   appears in the same panel.
6. Answers appear as they are written (streaming), so the panel feels quick.

## Non-goals (later, not now)

- Custom actions or editable prompts
- A history of look-ups
- Replacing the selected text in the other app
- A local model
- Changing the hotkey in the app, launch at login, an app icon
- Follow-up conversation (each question stands alone)

## Anti-goals (would make it a failure even if it works)

- The API key in Git, in a source file, in a plain file, or in a log
- Anything sent to Anthropic without the hotkey being pressed, or anything
  sent other than the selection, the sentence around it, and the user's
  question
- Anything about look-ups written to disk
- The other app's content being changed, or the user's clipboard being left
  different from how it was
- A panel that blocks: it must open at once and never freeze the Mac
- Code a beginner can't follow

## How it behaves

**Trigger.** Hotkey `⌃⌥Space`. **(Claude's call)** It is fixed in version 1.

**The panel.** Floating, about 380 points wide, as tall as its content up to
about 460 points, then it scrolls. It opens just below the selection when the
other app reports where the selection is, otherwise at the mouse pointer, and
is moved as needed to stay fully on screen. **(Claude's call)** The other app
stays the active app, so its selection stays highlighted. The look follows
the agreed mockup (`docs/mockup-panel.html` in the repo, copied from the
brainstorm): tab bar, answer with small uppercase labels, question field,
a footer with "⌘C copy" on the left and "esc to close" on the right.

**Closing.** `esc`, a click outside the panel, or pressing the hotkey again.
While the panel is open the hotkey always closes it; a new look-up needs a
second press. **(Claude's call, to keep it simple.)** Closing stops any
answers still loading.

**Explain, for a word.** A selection of up to three words counts as "a word"
**(Claude's call)** (so "loss aversion" is looked up like a word). The panel
shows the word in large type with its part of speech, then "Definition",
"German" and "In this sentence". If the word is German, the translation is
into English and the label is "English". If no surrounding sentence is
available, the third part explains typical use instead, under "In use".

**Explain, for a passage.** The start of the selection as a quote (two lines
at most), then "In plain words" with two to four sentences.

**Translate.** Into German; into English if the selection is German.

**Summarise.** At most three short sentences. For a single word or a very
short selection the tab still works and simply says what it means in one
sentence. **(Claude's call)**

**Rewrite.** A clearer, corrected version of the selection in the same
language, shown for copying. It does not change the text in the other app.

**Language of answers.** Explanations, summaries and answers to questions are
in the language of the selection. **(Claude's call)**

**The user's own question.** Typing in the field and pressing Return sends
the selection with the question. The answer appears directly under the
field and replaces the previous question's answer. The tabs are unaffected.

**Copy.** `⌘C` copies the answer the user acted on last: the tab being shown,
or the question's answer if he asked a question after last switching tabs.
**(Claude's call)** If text is selected in the question field, `⌘C` copies
that as usual.

**Background app (changed on 2026-11-10 at the user's request).** Glance has
no menu bar icon and no Dock icon. It is installed in `/Applications`, runs
in the background and starts at login. Opening the app again while it runs
shows a small settings window: the hotkey, "Start Glance when I log in",
"Set API key…" and "Quit Glance". An installed copy adds itself to the login
items the first time it runs; a copy in a build folder never does.
**(Claude's call on the settings window and the first-run behaviour.)**

**Messages** (exact text):

| Situation | Text |
|---|---|
| No Accessibility permission | "Glance needs the Accessibility permission to read the text you selected in other apps." Button: "Open System Settings" |
| Nothing selected | "Select some text first, then press ⌃⌥Space." |
| Selection too long | "The selection is too long. The limit is 20,000 characters." |
| No API key | "Add an Anthropic API key to get answers: open the Glance app again and choose Set API key." |
| Offline | "No internet connection." |
| HTTP 401 | "The API key was not accepted. Open the Glance app again and set it once more." |
| Model declined | "Claude declined to answer this." |
| No credit on the account (402, or a "credit balance" error) | "Your Anthropic account has no credit. Add credit in the Anthropic Console." |
| Rate limited or overloaded (429, 529) | "Claude is busy right now. Try again in a moment." |
| Any other failure | "Something went wrong. Try again." |
| Answer cut off at the length limit | the text so far, then "(The answer was cut off.)" |
| Loading | "…" in the answer area until the first words arrive |

## Constraints

- macOS 27 (Golden Gate), Xcode 27.2, Apple M3. Swift 5, AppKit for the menu
  bar icon, hotkey and panel window; SwiftUI for the panel's contents (as in
  KeyPeek). No third-party libraries.
- Its own folder and local Git repo at `~/Developer/glance`. No remotes and
  no pushing unless the user asks. Bundle identifier `local.glance`.
- The user's standing rules (`CLAUDE.md`): explain each step in plain
  language, keep code simple, feature branch then local merge, build and run
  before saying it's done, one sentence for each commit, branch and merge.
- Openable in Xcode with Run and buildable with `xcodebuild`; project set up
  like `~/Developer/keypeek/KeyPeek.xcodeproj` (app target plus hosted tests,
  shared scheme). App Sandbox off. Signed to run locally.
- The user grants the Accessibility permission himself and types the API key
  into the app himself. Claude never asks for, reads, prints or types the key.

## How it gets made

**Hotkey.** Registered with the system's hotkey service (Carbon
`RegisterEventHotKey`), which needs no permission and keeps the key press
from reaching the other app.

**Reading the selection.** Two steps, both needing the Accessibility
permission:
1. Ask the focused element of the front app for its selected text.
2. If that gives nothing (many browsers and Electron apps), copy instead:
   remember the clipboard, send `⌘C` to the front app once the hotkey's
   modifier keys are released, read the clipboard, then put the old
   clipboard contents back. **(Claude's call)**

**Context for a word.** Where step 1 works and the app can return the text
around the selection, up to about 300 characters on each side are read and
the sentence containing the word is cut out and sent as context. Otherwise no
context is sent.

**Claude requests.** One streaming HTTPS request per tab or question, with
`URLSession`. KeyPeek's client supplies the pattern for headers, key handling
and error mapping; reading the answer as a stream is new.
- Model: Claude Haiku, model ID `claude-haiku-5-5` **(Claude's call, for
  speed)**, in one constant. Low effort, thinking off, for the quickest
  first words; the builder checks these settings against the `claude-api`
  skill, which wins where it differs.
- The selection, context and question are passed as clearly marked data, and
  the instructions tell the model to treat the selection as text to work on,
  never as instructions to follow.
- Answers are plain text. For a word, the model writes four labelled lines
  (part of speech, definition, translation, context) that the panel turns
  into the labelled layout; lines can be shown as they arrive.
- Haiku has no automatic fallback when it declines; the panel shows the
  "declined" message.
- The builder must load the `claude-api` skill before writing this code and
  must not write requests from memory.

**API key.** Stored in the macOS Keychain under service `local.glance`,
entered through "Set API key…" (same dialog as KeyPeek). API use is billed
separately from a Claude subscription; a look-up costs a fraction of a cent.

**Limits.** Selections longer than 20,000 characters are refused with the
message above, never silently shortened. **(Claude's call)**

**Suggested code layout** (builder may adjust): app start and menu; hotkey;
selection reader; sentence finder; prompts; Claude client and stream parser;
answer formatter; panel window and placement; panel model; panel view;
Keychain store. Each in its own small file.

## Known risks

- **Permission and Keychain prompts after each rebuild.** Because the app is
  signed for local use, macOS treats every new build as a different app (seen
  in KeyPeek). After a rebuild the Accessibility permission must be reset with
  `tccutil reset Accessibility local.glance` and granted again, and the
  Keychain asks once before handing over the key ("Always Allow").
- **Apps that don't share the selection.** The copy fallback covers most. In
  apps where copying is blocked or slow, the panel shows "Select some text
  first…" even though text is selected.
- **Clipboard managers** may record the brief copy made by the fallback.
- **Hotkey taken.** If another app already uses `⌃⌥Space`, the hotkey may not
  fire; the settings window then says so.
- **Speed.** The first words depend on the network and the model; expect
  around a second.

## Left to the builder

- Exact sizes, fonts, colours and the menu bar symbol
- Prompt wording
- How the panel takes keyboard input without activating Glance
- Which parts get automated tests (good candidates: stream parsing, the
  answer formatter, the sentence finder, panel placement, the request body,
  and the panel model with a fake Claude)

## Done means

- The app builds from Xcode and from the command line, tests pass, and it
  runs in the menu bar.
- With the permission granted and a key set, the user has pressed the hotkey
  on a single word and on a passage: the panel opened near the text with the
  Explain answer streaming in.
- All four tabs work with `⌘1`–`⌘4` and by clicking; hints show on hover.
- A typed question gets an answer in the panel.
- `esc` closes the panel; `⌘C` copies the answer; the clipboard is unchanged
  after a look-up that used the copy fallback.
- No key or secret appears anywhere in the repo.
- Work is committed on a feature branch and merged into `main` locally, and
  the user has been told what was not verified.
