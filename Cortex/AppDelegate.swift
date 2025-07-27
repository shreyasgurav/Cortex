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
        
        // Check if Firebase is already configured
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            print("✅ Firebase configured successfully in AppDelegate")
        } else {
            print("✅ Firebase already configured")
        }
    }
}

