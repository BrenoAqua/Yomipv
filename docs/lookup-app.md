## Lookup App

The Lookup App is an interactive overlay that displays dictionary definitions, pitch accents, and frequencies for words you select in MPV directly, All data is taken from your installed dictionaries in Yomitan

## How it Works

The lookup window appears when you search for a word. Depending on your configuration, this can happen automatically or manually

- **Automatic Lookup**: Can be disabled in your settings (`selector_lookup_on_hover`)
  - `selector_lookup_on_navigation` can also be enabled to trigger a lookup when navigating through the selector using Left/Right arrow keys
- **Manual Lookup**: Press `Ctrl+c` (default) while hovering over a word in the selector

Right-click anywhere inside the lookup window to open the **Context Menu**

### Context Menu
- **Copy**: Copies the currently selected text to the clipboard (only enabled when text is selected)
- **Inspect Element**: Opens the developer tools (Inspector) for the lookup window.
- **Refresh CSS**: Instantly reloads your custom styles from `yomipv.css` (see [Custom Styling](#custom-styling))

The window stays on top of MPV until the selector is confirmed or cancelled
You can lock the window to prevent accidental changes when the cursor moves over another word in the selector by right-clicking the selected word in the selector

### Result Sorting
By default, the Lookup prioritizes the **longest match** first. This ensures that conjugated forms and compound words are shown before shorter matches (this mimics Yomitan's default behavior)

If you prefer entries that contain Kanji to be prioritized over match length, you can set `prioritize_kanji_match` to `yes` in your `yomipv.conf` file

### Navigating Multiple Results
If a word has multiple entries, you will see a counter (like `1 / 3`) at the top
- Click the Left/Right buttons of the lookup window to cycle through different entries

### Sub-word Lookups
With `selector_lookup_on_hover` (enabled by default) and `selector_lookup_on_navigation`, you can open the lookup for sub-words directly from the subtitle
You can also start a new search directly from the lookup window header:
- **Click any mora** in the headword to begin a new lookup from that position
- **Right-click the header** to go back to the previous word you were looking at

## Working with Definitions

### Selecting Text
- Just like in Yomitan’s popup, you can select any text inside definitions to populate your Selection Text field in Anki when `popup-selection-text` is being used
- **Copy to Clipboard**: Press `Ctrl+c` while text is selected inside the lookup window to copy it to your clipboard. This also clears the current selection

### Choosing a Specific Dictionary
- **Click the Dictionary Title** to select that specific dictionary to populate the Definition field in Anki if `selected-dict` is being used
- When you select a dictionary, `popup-selection-text` is ignored, and you can select text from the definition to be highlighted

## Frequencies
- By default the lookup app will show the frequencies of the word you are looking up
- You can disable this by setting `lookup_show_frequencies` to `no` in your `yomipv.conf` file

## Pitch Accents
- By default, the Lookup App shows the pitch accents (if available) of the word you are looking up and also colors the word according to its pitch accent
- You can disable this by setting `lookup_show_pitch_accents` to `no` in your `yomipv.conf` file

## Custom Styling

You can fully customize the appearance of the lookup window using a local CSS file

1. Open the `yomipv.css` file inside your `script-opts` folder
2. Add your custom CSS variables or overrides to this file
3. Your changes are automatically detected. Use the **Refresh CSS** option in the [Context Menu](#context-menu) to see your styling changes live without restarting MPV

The `yomipv-updater` is designed to preserve this file, ensuring your personal theme isn't lost during project updates

## Developer Tools

- Right-click anywhere in the lookup window and select **Inspect Element**
- This opens a detached Electron DevTools window focused on the **Elements** panel
- While the Inspector is open, the lookup window becomes **movable**, allowing you to reposition it anywhere on your screen
- Closing the Inspector will snap the lookup window back to its original position
- A tray icon appears while the Inspector is active, allowing you to restore the window if it's minimized