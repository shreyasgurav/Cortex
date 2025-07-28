import SwiftUI
import FirebaseCore

@main
struct CortexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    init() {
        // Initialize Firebase at app startup
        print("🔍 CortexApp: Initializing Firebase")
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            print("✅ Firebase configured successfully in CortexApp")
        } else {
            print("✅ Firebase already configured")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
