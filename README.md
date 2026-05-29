<p align="center">
    <img src="https://github.com/BrenoAqua/Yomipv/blob/main/scripts/yomipv/lookup-app/build/lookup-app.png?raw=true" width="128" height="128" alt="yomipv" />
</p>

<h1 align="center">Yomipv</h1>

<p align="center">An immersion-focused workflow for looking up and mining words without leaving MPV</p>

<p align="center">
  <img src="https://img.shields.io/github/v/release/BrenoAqua/Yomipv?color=blue" alt="Version">
  <a href="https://github.com/sponsors/BrenoAqua"><img src="https://img.shields.io/badge/Sponsor-GitHub-EA4AAA?style=flat&logo=github-sponsors" alt="Sponsor"></a>
  <img src="https://img.shields.io/github/downloads/BrenoAqua/Yomipv/total?color=orange" alt="Downloads">
  <img src="https://img.shields.io/badge/License-GPLv3-blue.svg" alt="License">
</p>

<p align="center">
  <a href="#requirements">Requirements</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#advanced-features">Advanced Features</a> •
  <a href="#troubleshooting">Troubleshooting</a>
</p>

---

### See it in Action

https://github.com/user-attachments/assets/8ff6f71a-c961-4da1-bf9f-b1b2c00143f8

---

## Requirements

- **[MPV](https://mpv.io/)** (0.33.0 or higher)
- **[FFmpeg](https://ffmpeg.org/)**
- **[Anki](https://apps.ankiweb.net/)** with **[AnkiConnect](https://ankiweb.net/shared/info/2055492159)**
- **[Yomitan](https://yomitan.wiki/)** and **[Yomitan Api](https://github.com/yomidevs/yomitan-api)**
- **curl** (Pre-installed on most systems, used for API requests)
- **[Node.js](https://nodejs.org/)** (Only required if installing from source or contributing)

## Installation

### Recommended
1. Download the [Windows Zip](https://github.com/BrenoAqua/Yomipv/releases/download/v1.1.0/win-yomipv-v1.1.0.zip), [Linux Zip](https://github.com/BrenoAqua/Yomipv/releases/download/v1.1.0/linux-yomipv-v1.1.0.zip), or [macOS Zip](https://github.com/BrenoAqua/Yomipv/releases/download/v1.1.0/mac-yomipv-v1.1.0.zip)
2. Extract the contents directly into your MPV directory:
    - Windows: `%APPDATA%/mpv/`
    - Linux/macOS: `~/.config/mpv/`

### Alternative (Requires Node.js)
1. **Clone the repository** to your MPV directory and install dependencies **(make sure you have Node.js installed)**:
   - Windows: `%APPDATA%/mpv/`
     ```
     git clone https://github.com/BrenoAqua/Yomipv && xcopy /e /i /y Yomipv . && rd /s /q Yomipv && cd scripts\yomipv\lookup-app && npm install
     ```
   
   - Linux/macOS: `~/.config/mpv/`
     ```
     git clone https://github.com/BrenoAqua/Yomipv && cp -rn Yomipv/* . && rm -rf Yomipv && cd scripts/yomipv/lookup-app && npm install
     ```

---

## Usage

**Configure Settings**:
   - Open `script-opts/yomipv.conf` and update your Anki deck/note type names and field mappings

**External Services**:
   - Ensure Anki is running with AnkiConnect enabled
   - Ensure Yomitan Api is running and the browser where the Yomitan extension is installed is open, and you have dictionaries installed

### Basic Workflow

1. Open a video with Japanese subtitles in MPV
2. Press **`c`** or **move your mouse after an idle period** (if `selector_trigger_on_mouse_move` is enabled) to activate the word selector
3. Navigate with **mouse hover** or **arrow keys** to select a word
   - **`Shift+LEFT`** / **`Shift+RIGHT`**: Expand the current selection to include the previous/next subtitle line
4. Press **`Enter`**, **`c`**, or **left-click** to create an Anki card



## Advanced Features

### **Selector**

- **Append Mode**: Select multiple subtitle lines before exporting
  - Press **`Shift+C`** to enter append mode, **`c`** to start the word selector, or **`Shift+C`** again to cancel

- **Mora-level Navigation**
  - When `selector_mora_hover` is enabled, hovering over a word narrows the lookup to start from mora under your cursor instead of the full word
  - **`s`**: Toggle mora-level keyboard navigation (left/right moves by mora instead of word)

- **Auto-Trigger Selector**
  - Automatically open the selector by moving the mouse after it has been idle
  - **`z`**: Toggle this behavior on/off
  - Enable `selector_trigger_on_mouse_move` and customize `selector_trigger_mouse_idle_time` in `yomipv.conf`

- **Persistent Mode**
  - Toggle persistent mode to export multiple words from a single subtitle selection without closing the selector
  - Press **`v`** to toggle the selection color changes to indicate it's active
  - Confirming a selection exports the card but keeps the selector open for the next pick

### **Media and Extraction**

  - **Manual Timings**
    - **`q`** / **`w`**: Set a custom start/end time for audio and picture extraction
    - Unset start or end times default to the subtitle boundaries when opening the selector
    - **`e`**: Clear manual timings
  - Press **`g`** to switch the extraction mode between screenshots and animated clips

### **History Panel**
  - Press **`a`** to toggle the history panel
  - Seek to a specific subtitle's timestamp by clicking on it (when selector is closed)
  - Click on previous/next lines to expand the subtitle lines (when selector is open)
  - **`Alt+LEFT`** / **`Alt+RIGHT`**: Seek to the previous/next subtitle
  - **`r`**: Replay the current subtitle line from the beginning and pause at the last frame
  - Press **`x`** to clear subtitle history (when the history panel is open)
  - Includes buttons to toggle picture animation and clear subtitle history

### **Lookup App**

Opens a popup window powered by your Yomitan dictionaries, showing definitions, pitch accents, and frequencies

  - Press **`Ctrl+c`**: after selecting a word to open the lookup app manually. It opens automatically on hover by default
  - **Right-click** on the word in the selector to lock the lookup
  - **Click any mora** in the header to narrow the lookup to a sub-word
  - **Right-click the header** to go back to the previous word
  - **Pitch Accents**: Toggle `lookup_show_pitch_accents` in `yomipv.conf`
  - **Frequencies**: Toggle `lookup_show_frequencies` in `yomipv.conf`
  - See [docs/lookup-app.md](docs/lookup-app.md) for full details

### **Subtitle Tools**

- **Subtitle Substitution & Colorization based on anki card states**
  - Press **`Shift+S`** to toggle between native MPV subtitles and Yomipv's colorized tokens
  - Enable `substitute_mpv_subtitles` in `yomipv.conf` to start with it enabled
  - Words are colorized based on their Anki card metadata:
    - **Status**: New, Learning, Review, Suspended
    - **Intervals**: Reflects how well a word is known (affects color shades)
    - **Requirement**: Press **`Shift+B`** to build/sync the local Anki database first before these statuses can be displayed for your existing collection
  - **Instant Feedback**: When you create a card, the word is immediately added to the local database and highlighted (red) in the current subtitle
  - See [docs/colorizer.md](docs/colorizer.md) for full details

- **Subtitle Replay**
  - **`r`**: Replay the current subtitle line from the beginning and pause at the last frame, useful for re-listening to a line for practice

- **Subtitle Sync**
  - Align primary Japanese subtitles to secondary translation timings to fix desynced tracks
  - *Note: Since it only matches initial timings, tracks can desync later on*
  - **`Ctrl+s`**: Manually trigger the synchronization. Pressing it again undoes the sync and restores the previous timing
  - Enable `auto_sync_subtitles` in `yomipv.conf` to automatically trigger sync when tracks change

- **Subtitle Management**
  - Automatically select and cycle through secondary subtitles based on preferred languages
  - Configure `primary_sub_lang` and `secondary_sub_lang` in `yomipv.conf` (defaults to `ja,jpn` and `en,eng` respectively)
  - Scans the video directory for matching external subtitle files (`.ass`, `.srt`)
  - **`Ctrl+j`** / **`Ctrl+Shift+J`**: Cycle through available secondary subtitle tracks
  - Secondary subtitles are shown only on hover. Set `secondary_on_hover=no` to keep them always visible

- **Subtitle Filtering**
  - Automatically filters non-dialogue text (signs, drawings, and formatting tags) from the OSD display
  - Can be toggled with `subtitle_filter_enabled` in `yomipv.conf`

### **AniList Tracking**

Integrates AniList with Yomipv, enabling automatic episode progress updates

  - **`Ctrl+a`**: Trigger the authentication and setup flow (opens a terminal to capture your token)
  - See [docs/anilist_tracking.md](docs/anilist_tracking.md) for full details

### **Auto-Updater**

Keeps Yomipv updated to the latest version

  - Press **`shift+U`** in MPV to trigger the update, or:
    - On Windows: Run **`yomipv-updater.bat`** directly
    - On Linux / macOS: Run **`yomipv-updater.sh`** directly
  - Choose between latest official releases or latest source (main branch)
  - Automatically preserves user configuration in `script-opts/yomipv.conf`
  - Downloads platform-specific binaries for the Lookup App
  - (Source mode only) Updates dependencies for the Lookup App (requires Node.js)
  - Requires administrator privileges to run the PowerShell script on Windows

---

## Troubleshooting

### Windows
- Ensure PowerShell execution policy allows scripts
- Check that curl is available at `C:\Windows\System32\curl.exe`

### Linux
- Ensure `curl`, `unzip`, `grep`, and `sed` are installed
- Ensure the updater script has execute permissions: `chmod +x yomipv-updater.sh`
- For the lookup app, ensure the binary in `scripts/yomipv/` has execution permissions

### macOS
- Ensure `curl`, `unzip`, `grep`, and `sed` are installed
- Ensure the updater script has execute permissions: `chmod +x yomipv-updater.sh`
- If macOS blocks the Lookup App with a Gatekeeper warning, run: `xattr -cr scripts/yomipv/YomipvLookup.app`
- MPV config directory: `~/.config/mpv/` (create it if it does not exist)
