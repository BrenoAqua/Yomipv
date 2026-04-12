# AniList Episode Tracking

Integrates AniList with Yomipv, enabling automatic episode progress updates

## Setup
1. Launch any video in MPV
2. Press `Ctrl+A` (or the custom key defined in `key_anilist_auth` within `yomipv.conf`)
3. Your browser will open the AniList authorization page, and a terminal window will pop up at the same time
4. Click **Approve** in the browser
5. Copy the full URL from the address bar
6. Paste it into the terminal and press Enter
7. The token will be extracted, saved to `yomipv.conf`, and tracking will be enabled
8. Restart MPV so the tracker starts working

## Features
- **Automatic Tracking:** Updates your progress once playback passes `anilist_update_thresh_percent` (default: 80%)
- **Episode Number Conversion:** Automatically converts absolute episode numbers (*Re Zero kara Hajimeru Isekai Seikatsu - 67*) into AniList’s seasonal format (*Season 4 Episode 1*). No manual mapping needed
- **Configurable Notifications:** Toggle on-screen success alerts via the `anilist_show_notifications` setting. Internal checks prevent API spam when seeking through the timeline