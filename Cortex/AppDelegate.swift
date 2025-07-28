//
//  AppDelegate.swift
//  Cortex
//
//  Created by Shreyas Gurav on 26/07/25.
//


import Cocoa
import FirebaseCore

class AppDelegate: NSObject, NSApplicationDelegate {
    var panelController: FloatingPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        panelController = FloatingPanelController()
        panelController?.showWindow(nil)
    }

    @objc private func handleAddMemoryToInput(_ notification: Notification) {
        guard let text = notification.object as? String else { return }
        print("🔍 [AppDelegate] Memory insertion requested: \(text)")
        // Hide floating modal before pasting (if visible)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("HideFloatingModal"), object: nil)
            // Give the window system a moment to refocus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.insertTextIntoActiveField(text)
            }
        }
    }

    private func insertTextIntoActiveField(_ text: String) {
        print("🔍 [AppDelegate] Preparing to insert text into active field")
        // Check Accessibility permissions
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        if !accessibilityEnabled {
            print("❌ [AppDelegate] Accessibility permissions are missing! Paste will not work.")
            let alert = NSAlert()
            alert.messageText = "Cortex needs Accessibility permissions to paste into other apps."
            alert.informativeText = "Go to System Preferences > Privacy & Security > Accessibility and enable Cortex."
            alert.alertStyle = .critical
            alert.runModal()
            return
        }
        // 1. Save current clipboard contents
        let pasteboard = NSPasteboard.general
        let prevClipboard = pasteboard.string(forType: .string)
        print("🔍 [AppDelegate] Saved previous clipboard contents")
        // 2. Set clipboard to memory text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("🔍 [AppDelegate] Clipboard set to memory text")
        // 3. Simulate Cmd+V (paste) using AppleScript
        let appleScript = """
        tell application \"System Events\"
            keystroke \"v\" using command down
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments = ["-e", appleScript]
            do {
                try task.run()
                print("✅ [AppDelegate] Cmd+V simulated via AppleScript")
            } catch {
                print("❌ [AppDelegate] Failed to simulate Cmd+V: \(error.localizedDescription)")
            }
        }
        // 4. Restore clipboard after a longer delay (to avoid interfering with paste)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            if let prev = prevClipboard {
                pasteboard.clearContents()
                pasteboard.setString(prev, forType: .string)
                print("🔍 [AppDelegate] Clipboard restored to previous contents")
            } else {
                print("🔍 [AppDelegate] Clipboard was empty before, cleared after paste")
            }
        }
    }
}
