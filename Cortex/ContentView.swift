
import SwiftUI
import FirebaseFirestore
import FirebaseCore

struct ContentView: View {
    @StateObject private var logger = KeyLoggerWrapper()
    @StateObject private var floatingModalManager = FloatingModalManager()
    @State private var showSavedMessage: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .imageScale(.large)
                    .foregroundStyle(.blue)
                Text("Cortex - Memory Capture")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            
            // Status indicator
            HStack {
                Circle()
                    .fill(logger.isLogging ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                Text(logger.isLogging ? "Active - Capturing keystrokes" : "Inactive")
                    .font(.caption)
                    .foregroundColor(logger.isLogging ? .green : .red)
            }
            
            // Error message
            if !logger.errorMessage.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(logger.errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Current buffer display
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Input Buffer:")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text(logger.currentBuffer.isEmpty ? "Type something... (Press Enter to save)" : logger.currentBuffer)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .foregroundColor(logger.currentBuffer.isEmpty ? .secondary : .primary)
            }
            
            // Last saved text
            if !logger.lastSavedText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last Saved:")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text(logger.lastSavedText)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                }
            }
            
            // Control buttons
            HStack(spacing: 16) {
                Button(action: {
                    if logger.isLogging {
                        logger.stop()
                    } else {
                        logger.start()
                    }
                }) {
                    HStack {
                        Image(systemName: logger.isLogging ? "stop.circle.fill" : "play.circle.fill")
                        Text(logger.isLogging ? "Stop Capturing" : "Start Capturing")
                    }
                    .padding()
                    .background(logger.isLogging ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
                Button(action: {
                    logger.clearBuffer()
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear Buffer")
                    }
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
            
            // Floating modal control
            HStack(spacing: 16) {
                Button(action: {
                    floatingModalManager.toggleModal()
                }) {
                    HStack {
                        Image(systemName: floatingModalManager.isVisible ? "eye.slash" : "eye")
                        Text(floatingModalManager.isVisible ? "Hide Memories" : "Show Memories")
                    }
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
                Button(action: {
                    testFirebaseConnection()
                }) {
                    HStack {
                        Image(systemName: "wifi")
                        Text("Test Firebase")
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
            
            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("Instructions:")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Click 'Start Capturing' to begin monitoring keystrokes")
                    Text("• Type in any text field across your system")
                    Text("• Press Enter to save the current buffer to Firestore")
                    Text("• All saved text goes to the 'memory' collection")
                    Text("• The app captures keystrokes globally")
                    Text("• Use 'Show Memories' to access your saved memories")
                    Text("• Click any memory to add it to your current input")
                    Text("• Press Escape to dismiss the floating window")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            // Start logging automatically
            logger.start()
        }
    }
    
    private func testFirebaseConnection() {
        print("🔍 Testing Firebase connection...")
        
        if let app = FirebaseApp.app() {
            print("✅ Firebase app found: \(app.name)")
        } else {
            print("❌ Firebase app not found")
        }
        
        let db = Firestore.firestore()
        db.collection("memory").getDocuments { querySnapshot, error in
            if let error = error {
                print("❌ Firebase test failed: \(error.localizedDescription)")
            } else {
                let count = querySnapshot?.documents.count ?? 0
                print("✅ Firebase test successful: Found \(count) documents")
            }
        }
    }
}

#Preview {
    ContentView()
}
