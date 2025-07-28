
import SwiftUI
import FirebaseFirestore
import FirebaseCore

struct ContentView: View {
    @StateObject private var logger = KeyLoggerWrapper()
    @StateObject private var floatingModalManager = FloatingModalManager()
    @State private var showSavedMessage: Bool = false
    
    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color(NSColor.windowBackgroundColor), Color.white]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

// MARK: - BlurView for macOS (wraps NSVisualEffectView)
// If you wish to use BlurView in this file, uncomment below or move to a shared file.
// struct BlurView: NSViewRepresentable {
//     var style: NSVisualEffectView.Material = .contentBackground
//     func makeNSView(context: Context) -> NSVisualEffectView {
//         let view = NSVisualEffectView()
//         view.material = style
//         view.blendingMode = .withinWindow
//         view.state = .active
//         return view
//     }
//     func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
//         nsView.material = style
//     }
// }

            VStack(spacing: 28) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .resizable()
                        .frame(width: 34, height: 34)
                        .foregroundColor(.blue)
                        .shadow(color: .blue.opacity(0.2), radius: 8, x: 0, y: 4)
                    Text("Cortex")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.top, 18)
                .padding(.bottom, 4)
                .padding(.horizontal, 8)

                // Status indicator
                HStack(spacing: 10) {
                    Circle()
                        .fill(logger.isLogging ? Color.green : Color.red)
                        .frame(width: 14, height: 14)
                        .shadow(color: (logger.isLogging ? Color.green : Color.red).opacity(0.2), radius: 4, x: 0, y: 2)
                    Text(logger.isLogging ? "Active - Capturing keystrokes" : "Inactive")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(logger.isLogging ? .green : .red)
                }

                // Error message
                if let errorMessage = logger.errorMessage, !errorMessage.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    .padding()
                    .background(Color.red.opacity(0.12))
                    .cornerRadius(10)
                    .shadow(color: .red.opacity(0.08), radius: 6, x: 0, y: 2)
                }

                // Buffer and last saved cards
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Current Input Buffer")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(logger.currentBuffer.isEmpty ? "Type something... (Press Enter to save)" : logger.currentBuffer)
                            .font(.system(.body, design: .monospaced))
                            .padding(12)
                            .frame(minHeight: 90, alignment: .topLeading)
                            .background(Color.white)
                            .cornerRadius(10)
                            .foregroundColor(logger.currentBuffer.isEmpty ? .secondary : .primary)
                            .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
                    }
                    if !logger.lastSavedText.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Last Saved")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(logger.lastSavedText)
                                .font(.system(.body, design: .monospaced))
                                .padding(12)
                                .frame(minHeight: 60, alignment: .topLeading)
                                .background(Color.white)
                                .cornerRadius(10)
                                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
                        }
                    }
                }
                .padding(.horizontal, 2)

                // Control buttons
                HStack(spacing: 18) {
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
                        .font(.system(size: 15, weight: .medium))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                        .background(logger.isLogging ? Color.red : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .shadow(color: (logger.isLogging ? Color.red : Color.green).opacity(0.10), radius: 6, x: 0, y: 2)
                    }
                    Button(action: { logger.clearBuffer() }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear Buffer")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .shadow(color: Color.orange.opacity(0.10), radius: 6, x: 0, y: 2)
                    }
                }

                // Floating modal control
                HStack(spacing: 18) {
                    Button(action: { floatingModalManager.toggleModal() }) {
                        HStack {
                            Image(systemName: floatingModalManager.isVisible ? "eye.slash" : "eye")
                            Text(floatingModalManager.isVisible ? "Hide Memories" : "Show Memories")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .shadow(color: Color.purple.opacity(0.10), radius: 6, x: 0, y: 2)
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
                    
                    Button(action: {
                        TextInjectionService.shared.testPermissions()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.shield")
                            Text("Test Permissions")
                        }
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }

                // Instructions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Instructions")
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
                .background(Color.white.opacity(0.85))
                .cornerRadius(10)
                .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 2)
                .padding(.top, 6)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 18)
        }
        .onAppear { logger.start() }
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
