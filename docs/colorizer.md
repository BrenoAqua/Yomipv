# Subtitle Colorizer

The Subtitle Colorizer enhances the word selector by applying colors to tokens based on their current status in your Anki collection. This provides immediate visual feedback on which words are new, being learned, or already known

### Status Colors

The colorizer uses a dynamic color palette to represent different card states:

- **Suspended** (Dark Red): Suspended terms
- **New** (Red): Unstudied terms
- **Learning** (Orange to Yellow): Terms in the learning phase (up to 21 days)
- **Review** (Green to Cyan): Mature/known terms (up to 2000 days)

<img width="600" alt="gradient" src="https://github.com/user-attachments/assets/9df40f0d-3e16-4d4b-8282-748b0e08de81" />

## Configuration

To enable and customize the colorizer, modify your `script-opts/yomipv.conf` file:

### Settings

```ini
# Enable the colorizer
colorizer_enabled=yes

# Colorize the words
selector_colorize_words=yes

# Add an underline and colorize it instead of the text
selector_colorize_underline=no
```

### Synchronization

The colorizer relies on a local snapshot of your Anki database (`anki_words.json`) for performance. You must manually trigger a rebuild of this database to sync your latest Anki progress

- **Default Key**: `B` (Shift + b)

Pressing this key will fetch your current card intervals and statuses from Anki via AnkiConnect and update the local database

## Prerequisites

1. **AnkiConnect**: Ensure Anki is open with the AnkiConnect add-on installed and configured
2. **Database Build**: You must press the `B` key at least once to generate the initial database
3. **Fields**: Ensure `ankidb_fields` in your configuration correctly maps to the fields in your Anki note types that contain the Japanese expression

```ini
# Example field mapping for database building
ankidb_fields=word Word expression Expression
```
