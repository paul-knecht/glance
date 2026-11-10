# Glance

A small macOS app that runs in the background, with no Dock icon and no menu
bar icon. Select text in any app, press `⌃⌥Space`, and a floating panel
explains it with Claude. Tabs translate, summarise or rewrite
the selection, and a text field takes your own question about it.

"Glance" is a working name.

## What it does

- **Explain** (`⌘1`): for a word, a definition, the German translation and a
  short explanation in context; for a passage, a short explanation in plain
  words. This tab loads as the panel opens.
- **Translate** (`⌘2`): into German, or into English if the selection is German.
- **Summarise** (`⌘3`): at most three short sentences.
- **Rewrite** (`⌘4`): a clearer, corrected version to copy. The text in the
  other app is not changed.
- **Ask**: type a question about the selection and press Return.
- `⌘C` copies the answer, `esc` closes the panel. Pressing the hotkey again or
  clicking outside also closes it.

## Requirements

- macOS 14 or later (built and tried on macOS 27)
- Xcode
- An Anthropic API key. API use is billed separately from a Claude
  subscription; a look-up costs a fraction of a cent.

## Setup

### 1. Build and install

```bash
./scripts/install.sh
```

This builds Glance, copies it to `/Applications/Glance.app` and starts it.
Nothing appears on screen: Glance waits in the background for the hotkey.
The first time the installed copy runs, it adds itself to your login items,
so it starts whenever you log in.

To work on the code, open `Glance.xcodeproj` in Xcode and press Run. A copy
started from Xcode never adds itself to the login items.

### Settings

Open Glance again (from Applications or Spotlight) while it is running. A
small window appears with **Set API key…**, **Start Glance when I log in**
and **Quit Glance**.

### 2. Allow Accessibility

Glance reads the text you selected in other apps through the macOS
Accessibility permission. In apps that don't share their selection, it presses
`⌘C` for you, reads the clipboard, and puts the old clipboard contents back.

1. Select some text and press `⌃⌥Space`. The panel explains the permission.
2. Click **Open System Settings**.
3. Switch **Glance** on under Privacy & Security > Accessibility.
4. Press `⌃⌥Space` again.

### 3. Add your API key

Open Glance again to show the settings window, click **Set API key…**, and
paste your key. It is stored in the macOS Keychain, never in a file.

## What is sent to Anthropic

Only when you press the hotkey (or switch tabs, or ask a question): the
selected text, the sentence around a selected word where the app provides it,
and your question. Nothing about your look-ups is saved on your Mac.

## Troubleshooting

**The panel asks for the Accessibility permission again after I rebuilt the app.**
The app is signed for local use only, so macOS treats every new build as a
different app. Reset the entry, then grant it again as in step 2:

```bash
tccutil reset Accessibility local.glance
```

**macOS asks for my login password when Glance fetches an answer.**
After a rebuild, the Keychain asks before it hands the stored key to the new
build. Choose "Always Allow".

**The panel says "Select some text first" although text is selected.**
The app in front neither shares its selection nor reacts to `⌘C` in time.

**The settings window says the hotkey is not available.**
Another app has registered the same hotkey.

**The panel shows the permission message although Glance is allowed.**
A different copy of Glance is running, most likely one from the project's
`build` folder that was opened by accident (Spotlight lists every copy).
Only one copy runs at a time, and the one started last wins. Open
`/Applications/Glance.app` to switch back, or run `./scripts/install.sh`,
which also removes the built copies.

**Glance should no longer start at login.**
Switch it off in the settings window, or under System Settings > General >
Login Items.

## Tests

```bash
xcodebuild -project Glance.xcodeproj -scheme Glance -derivedDataPath build test
```

No test calls the real API.

## Licence

MIT. See `LICENSE`.
