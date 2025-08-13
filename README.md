## Cortex

An AI-powered memory assistant for macOS that captures what you type, stores it as searchable "memories" in Firebase, and shows a floating, context-aware panel that suggests relevant snippets you can instantly insert into any app.

### Highlights
- **Real-time capture**: Global key logging with sensible filtering and debouncing
- **Floating suggestions**: Non-activating panel that auto-appears while typing and filters memories by context
- **One-click insertion**: Paste suggested memory into the frontmost app via Accessibility/Automation APIs
- **Memory management**: Add, edit, search, and delete memories with tags
- **Firebase-backed**: Uses Firestore for storage; includes live listeners for updates

## Requirements
- **macOS**: 15.5+ (Sequoia)
- **Xcode**: 15+
- **Swift**: 5.9+
- **Firebase**: Firestore enabled and `GoogleService-Info.plist` configured

## Getting Started

### 1) Clone
```bash
git clone https://github.com/<your-org-or-user>/cortex.git
cd cortex
```

### 2) Firebase setup
- Create a Firebase project and enable Firestore.
- Download `GoogleService-Info.plist` for your macOS app and place it in `Cortex/`.
  - Ensure the file is added to the `Cortex` target (Target Membership in Xcode).
- Default collection used is `memory`.

### 3) Open and configure signing
1. Open `Cortex.xcodeproj` in Xcode.
2. Select the `Cortex` target → Signing & Capabilities.
3. Set your Team and change Bundle Identifier if needed (`com.cortexagent.Cortex` by default).

### 4) System permissions (must-do)
Cortex injects text and listens to global keystrokes, which requires:
- **Accessibility**: System Settings → Privacy & Security → Accessibility → add and enable `Cortex.app`.
- **Automation (Apple Events)**: System Settings → Privacy & Security → Automation → enable "System Events" for Cortex.

Helper script: `./add_permissions.sh` prints exact manual steps and opens Accessibility settings. You may need to rebuild/relaunch after granting.

### 5) Build & run
- In Xcode: select `Cortex` scheme → Run.
- Or via script:
```bash
./build_and_test.sh
```
This script builds Release, copies `Cortex.app` to your Desktop, and launches it.

## Usage
- On launch, Cortex initializes Firebase and starts the key logger.
- Start/Stop capture from the main window.
- The floating modal will appear while you type and hide shortly after you stop.
- Click a suggested memory to insert it into the currently focused text field of the frontmost app.
- Use the UI to add, search, edit, or delete memories; tags improve relevance.

## Features in Code
- App entry: `Cortex/CortexApp.swift`, `Cortex/AppDelegate.swift`
- Key logging: `Cortex/Core/Services/KeyLogger.swift` with `KeyLoggerWrapper` for UI bindings
- Floating panel: `Cortex/Core/Managers/FloatingModalManager.swift`, view in `Cortex/Views/Modals/FloatingMemoryView.swift`
- Memory CRUD: `Cortex/Core/Managers/MemoryManager.swift` (+ models in `Core/Models`)
- Text injection: `Cortex/Core/Services/TextInjectionService.swift` (Accessibility, AppleScript, pasteboard fallbacks)
- Utilities: `Cortex/Utils/NonActivatingPanel.swift`

## Architecture Overview
- **Capture loop**: Global `.keyDown` monitor buffers printable characters. Enter or length threshold triggers save to Firestore (`memory` collection) along with `appName` and a window title placeholder.
- **Context engine**: The last ~20 typed words are broadcast. The floating view scores memories by exact/substring similarity, simple word-similarity, tags, and recency, then shows the top results.
- **Insertion flow**: Selecting a memory posts `AddMemoryToInput` which the app delegate handles by calling `TextInjectionService` to insert text into the focused field.

## Privacy & Security
- Key capture is done locally via macOS accessibility and event APIs.
- Saved memories are uploaded to your Firestore project. Review and secure your Firestore rules.
- Insertion requires Accessibility and Automation permissions; you control granting/revoking via System Settings.

## Troubleshooting
- **Firebase not configured**: Ensure `GoogleService-Info.plist` is present in `Cortex/` and included in the `Cortex` target.
- **Cannot save/fetch memories**: Verify Firestore is enabled and network is reachable; check Xcode console for logs. Ensure rules allow reads/writes for your user/test.
- **Permissions fail**: Remove Cortex from Accessibility and Automation, re-add, then restart the app. You can also run `tccutil reset Accessibility com.cortexagent.Cortex` and re-grant.
- **Floating panel not showing**: Confirm the app is running and you’re typing in another app. See console logs for `ShowFloatingModal/HideFloatingModal` events.
- **Text not inserted**: Make sure the target app’s text field is focused and Automation permissions allow controlling System Events.

## Scripts
- `add_permissions.sh`: Guides granting Accessibility permissions (and opens settings).
- `build_and_test.sh`: Builds Release, copies `Cortex.app` to Desktop, and launches it.

## Project Structure
```
Cortex/
  Core/
    Managers/         # Floating modal + memory management
    Models/           # Memory models
    Services/         # Key logging, Firestore fetcher, text injection
  Views/
    Modals/           # Floating memory UI and add/edit dialogs
    Screens/          # Main window content
  Utils/              # Non-activating panel util
  Assets.xcassets/    # App icons and images
```

## Testing
- Use the `CortexTests` and `CortexUITests` targets in Xcode.
- You can run unit tests via Product → Test or `xcodebuild -scheme Cortex test` after configuring a simulator/runner that supports macOS unit tests.

## Configuration Notes
- Bundle Identifier: `com.cortexagent.Cortex` (change as needed for signing).
- Deployment target: macOS 15.5 (can be lowered if you adapt APIs accordingly).
- Firestore collection: `memory`.

## Roadmap ideas
- Richer semantic ranking with embeddings
- Real window title and app context enhancement
- Configurable shortcuts for showing/hiding the panel
- End-to-end encryption options for stored memories

## Disclaimer
This app uses macOS Accessibility and Automation capabilities to assist your typing workflow. Only grant permissions if you trust the binary you built/sign. Review the source and adjust Firebase security rules before distributing.



