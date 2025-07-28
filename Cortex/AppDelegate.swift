//
//  AppDelegate.swift
//  Cortex
//
//  Created by Shreyas Gurav on 26/07/25.
//

import Cocoa
import FirebaseCore

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🔍 AppDelegate: Configuring Firebase")
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            print("✅ Firebase configured successfully in AppDelegate")
        } else {
            print("✅ Firebase already configured")
        }
        
        // Setup notification observers
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        print("🔍 [AppDelegate] Setting up notification observers")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAddMemoryToInput),
            name: NSNotification.Name("AddMemoryToInput"),
            object: nil
        )
        print("✅ [AppDelegate] Notification observer added for AddMemoryToInput")
    }

    @objc private func handleAddMemoryToInput(_ notification: Notification) {
        print("🔍 [AppDelegate] handleAddMemoryToInput called!")
        guard let text = notification.object as? String else { 
            print("❌ [AppDelegate] No text found in notification")
            return 
        }
        print("🔍 [AppDelegate] Memory insertion requested: \(text)")
        
        // Hide floating modal before pasting (if visible)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("HideFloatingModal"), object: nil)
            
            // Give the window system a moment to refocus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                // Use the new TextInjectionService
                TextInjectionService.shared.injectText(text)
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
