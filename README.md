# MemoryTap

A macOS menu bar application that captures and stores text you send from any application. Built with Swift and SwiftUI.

## Overview

MemoryTap runs in your menu bar and uses macOS Accessibility APIs to detect text you type and send from any application—chat messages, AI prompts, emails, notes, code comments, and more. All captured text is stored locally in a SQLite database on your Mac.

**Version 1.0** focuses on reliable text capture. No AI, no cloud sync—just solid, local memory storage.

## Features

- 🧠 **Universal Capture**: Works across all macOS applications (Slack, Discord, browsers, VS Code, Notion, etc.)
- 🔒 **Privacy First**: All data stored locally on your Mac, never leaves your device
- ⌨️ **Smart Detection**: Captures text when you press Enter, switch apps, or move focus
- 🔐 **Security Aware**: Automatically skips password fields and secure inputs
- 📝 **Memory Browser**: View, search, copy, and manage all your captured text
- 🔕 **Privacy Mode**: One-click toggle to pause all capture

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later (for building)

## Installation

### Building from Source

1. Clone or download this repository
2. Open `Cortex.xcodeproj` in Xcode
3. Select your development team in Signing & Capabilities
4. Build and run (⌘R)

### First Launch

When you first launch MemoryTap, you'll need to grant permissions:

1. **Accessibility Permission** (Required)
   - MemoryTap needs this to read text from any application
   - Go to: System Settings → Privacy & Security → Accessibility
   - Find and enable MemoryTap

2. **Input Monitoring Permission** (Optional but Recommended)
   - Enables detection of Enter key presses for better capture timing
   - Go to: System Settings → Privacy & Security → Input Monitoring
   - Find and enable MemoryTap

## Usage

### Menu Bar

Click the brain icon in your menu bar to:
- Toggle capture on/off
- Enable privacy mode (pauses all capture)
- Open the Memory window
- See capture status and last captured text

### Memory Window

- View all captured memories sorted by time
- Search through your memories
- Click any memory to see full text
- Copy text to clipboard
- Delete individual entries or clear all

### How Capture Works

MemoryTap detects "sent" text through several heuristics:

1. **Enter Key**: When you press Enter or Cmd+Enter (common send shortcuts)
2. **Focus Lost**: When you finish editing and click elsewhere
3. **App Switch**: When you switch to another application after typing

The app continuously monitors the focused UI element and tracks changes to editable text fields.

## Architecture

```
Cortex/
├── CortexApp.swift          # App entry point & AppDelegate
├── Info.plist               # Permissions & menu bar config
├── Models/
│   ├── Memory.swift         # Memory data model
│   └── AppState.swift       # Global app state
├── Core/
│   ├── PermissionsManager.swift    # Permission checking & requests
│   ├── AccessibilityWatcher.swift  # UI element tracking
│   ├── KeyEventListener.swift      # Global key event detection
│   └── CaptureCoordinator.swift    # Capture orchestration
├── Storage/
│   └── MemoryStore.swift    # SQLite database operations
└── Views/
    ├── MenuBarView.swift    # Menu bar dropdown UI
    ├── MemoryWindowView.swift    # Main memory browser
    └── OnboardingView.swift      # Permission setup wizard
```

## Known Limitations

1. **Some Apps Don't Expose Text**
   - Electron apps may have limited accessibility support
   - Some custom text editors don't implement standard accessibility

2. **Web Content Varies**
   - Browser accessibility support depends on the website
   - Some web apps may not expose their text fields properly

3. **Performance**
   - The app polls for focus changes (100ms interval)
   - This is intentional to balance responsiveness with resource usage

4. **Secure Fields**
   - Password fields are intentionally never captured
   - Some apps mark regular fields as secure, which we respect

## Database

Memories are stored in SQLite at:
```
~/Library/Application Support/MemoryTap/memories.db
```

Schema:
```sql
CREATE TABLE memories (
    id TEXT PRIMARY KEY,
    created_at INTEGER,
    app_bundle_id TEXT,
    app_name TEXT,
    window_title TEXT,
    source TEXT,      -- "enter_key", "focus_lost", "app_switch"
    text TEXT,
    text_hash TEXT    -- SHA256 for deduplication
);
```

## Privacy & Security

- **Local Only**: All data stays on your Mac
- **No Network**: The app makes no network requests
- **No Analytics**: No telemetry or tracking
- **Password Safe**: Secure text fields are never captured
- **Privacy Mode**: Instantly pause all capture
- **Easy Deletion**: Delete any or all memories at any time

## Troubleshooting

### App doesn't appear in Accessibility settings
- Make sure you're running the app from `/Applications` or a proper build location
- Try removing and re-adding the app in System Settings

### Text isn't being captured
- Verify Accessibility permission is granted
- Check that capture is enabled (not in privacy mode)
- Some apps may not expose text via accessibility APIs

### Menu bar icon is missing
- Check if the app is running (Activity Monitor)
- The icon appears after initial setup completes

## Future Plans (V2+)

- Memory search with embeddings
- Smart memory surfacing while typing
- Insert memories back into any text field
- Cursor IDE integration
- Privacy-safe AI ranking

## License

This project is for personal use. See LICENSE for details.

---

Built with ❤️ for anyone who wants to remember everything they've said.

