# How MemoryTap Works - Step by Step

## 🎯 What Happens When You Type and Press Enter

Here's exactly what happens when you type a message and press Enter:

### 1. **You Type in Any App** (Slack, Messages, Browser, etc.)
   - MemoryTap is **continuously watching** the focused text field
   - Every 100ms, it checks: "What text field is focused? What's the text in it?"
   - It tracks changes to the text as you type

### 2. **You Press Enter (or Cmd+Enter)**
   - **If Input Monitoring permission is granted:**
     - The `KeyEventListener` detects the Enter key press globally
     - It immediately tells `AccessibilityWatcher`: "Hey, Enter was pressed!"
     - `AccessibilityWatcher` reads the current text from the focused field
     - **The text is captured and saved!**
   
   - **If Input Monitoring is NOT granted:**
     - The app uses a fallback: when you click away or switch apps
     - If text was edited recently (within 5 seconds), it captures it

### 3. **Text Gets Saved**
   - The captured text is:
     - Trimmed (whitespace removed)
     - Hashed (SHA256) for deduplication
     - Saved to SQLite database at: `~/Library/Application Support/MemoryTap/memories.db`
   - The memory appears in your MemoryTap window

## 🔍 How to Verify It's Working

### Check the Console Logs
Open **Console.app** and filter for "MemoryTap" or "CaptureCoordinator". You should see:
```
[MemoryTap] Application launched
[AccessibilityWatcher] Started watching
[KeyEventListener] Started listening for key events
[CaptureCoordinator] Started capture coordinator
[KeyEventListener] Enter/Send key detected (cmd: false, ctrl: false)
[CaptureCoordinator] Captured memory from Messages via enter_key
[MemoryStore] Saved memory from Messages: Hello, how are you?...
```

### Test It
1. Open **Messages** or **Slack**
2. Type a message: "Test message 123"
3. Press **Enter** (or Cmd+Enter)
4. Click the **MemoryTap icon** in your menu bar
5. Click **"Open Memory"**
6. You should see your message in the list!

### Check Menu Bar Status
- Click the brain icon in menu bar
- Status should show: **"Capturing"** (green dot)
- If it shows "Needs Permission" → grant Accessibility permission
- If it shows "Paused" → toggle "Capture Enabled" ON

## 🛠️ Troubleshooting

### Not Capturing?
1. **Check permissions:**
   - System Settings → Privacy & Security → Accessibility
   - Make sure MemoryTap is enabled ✅

2. **Check if capture is enabled:**
   - Menu bar → Make sure "Capture Enabled" is ON
   - Make sure "Privacy Mode" is OFF

3. **Check console logs:**
   - Look for errors or "Cannot start capture" messages

4. **Some apps don't work:**
   - Electron apps (Discord, Slack desktop) may have limited support
   - Some web apps don't expose text properly
   - Try Messages.app or Notes.app first to test

### Enter Key Not Detected?
- Grant **Input Monitoring** permission:
  - System Settings → Privacy & Security → Input Monitoring
  - Enable MemoryTap ✅
  - The app will automatically restart capture

## 📊 What Gets Captured

✅ **Captured:**
- Text from Messages, Slack, Discord, WhatsApp Web
- Text from Notes, TextEdit, VS Code, Cursor
- Text from browser text fields (Gmail, Twitter, etc.)
- Text when you press Enter, Cmd+Enter, or Ctrl+Enter

❌ **NOT Captured:**
- Password fields (automatically detected and skipped)
- Text shorter than 2 characters
- Duplicate text (same hash from same app within 10 seconds)
- When Privacy Mode is ON
- When Capture is disabled

## 🎮 Controls

**Menu Bar Dropdown:**
- **Capture Enabled** toggle → Turn capture on/off
- **Privacy Mode** toggle → Instantly pause all capture
- **Open Memory** → View all captured memories
- **Clear All Memories** → Delete everything

**Memory Window:**
- Search through your memories
- Click any memory to see full text
- Copy button to clipboard
- Delete individual entries

## 🔄 Automatic Behavior

The app automatically:
- Starts capturing when Accessibility permission is granted
- Restarts capture when you toggle settings
- Detects permission changes every 2 seconds
- Deduplicates identical text within 10 seconds
- Skips password/secure fields

---

**That's it!** The app runs silently in the background. Just type and press Enter anywhere, and your text will be captured. 🚀

