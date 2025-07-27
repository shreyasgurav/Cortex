import Cocoa
import FirebaseFirestore
import FirebaseCore

class KeyLogger: ObservableObject {
    private var eventMonitor: Any?
    private var db: Firestore?
    private var currentBuffer = ""
    
    // Callbacks for UI updates
    var onBufferUpdate: ((String) -> Void)?
    var onTextSaved: ((String) -> Void)?
    var onError: ((String) -> Void)?

    func startLogging() {
        // Ensure Firebase is configured
        guard FirebaseApp.app() != nil else {
            print("❌ Firebase not configured")
            DispatchQueue.main.async {
                self.onError?("Firebase not configured. Please restart the app.")
            }
            return
        }
        
        // Initialize Firestore
        db = Firestore.firestore()
        
        // Remove any existing observer first
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("AddMemoryToInput"), object: nil)
        
        // Listen for memory insertion notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(addMemoryToBuffer),
            name: NSNotification.Name("AddMemoryToInput"),
            object: nil
        )
        
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let characters = event.characters else { return }

            for character in characters {
                if character == "\r" || character == "\n" { // Enter key
                    self.saveBuffer()
                } else if character == "\u{8}" { // Backspace
                    if !self.currentBuffer.isEmpty {
                        self.currentBuffer.removeLast()
                    }
                } else {
                    self.currentBuffer.append(character)
                }
            }
            
            // Update UI with current buffer
            DispatchQueue.main.async { [weak self] in
                self?.onBufferUpdate?(self?.currentBuffer ?? "")
            }
        }
    }
    
    @objc private func addMemoryToBuffer(_ notification: Notification) {
        guard let text = notification.object as? String else { return }
        
        // Add the memory text to current buffer with a newline
        if !currentBuffer.isEmpty {
            currentBuffer += "\n" + text
        } else {
            currentBuffer += text
        }
        
        // Update UI
        DispatchQueue.main.async { [weak self] in
            self?.onBufferUpdate?(self?.currentBuffer ?? "")
        }
    }
    
    func stopLogging() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        
        // Remove notification observer
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("AddMemoryToInput"), object: nil)
    }

    private func saveBuffer() {
        guard let db = db else {
            print("❌ Firestore not initialized")
            DispatchQueue.main.async {
                self.onError?("Firestore not initialized")
            }
            return
        }
        
        let trimmed = currentBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let data: [String: Any] = [
            "text": trimmed,
            "timestamp": FieldValue.serverTimestamp(),
            "appName": getCurrentAppName(),
            "windowTitle": getCurrentWindowTitle()
        ]

        db.collection("memory").addDocument(data: data) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Firestore Error: \(error.localizedDescription)")
                    self?.onError?("Failed to save: \(error.localizedDescription)")
                } else {
                    print("✅ Saved memory: \(trimmed)")
                    self?.onTextSaved?(trimmed)
                }
            }
        }

        currentBuffer = ""
        DispatchQueue.main.async { [weak self] in
            self?.onBufferUpdate?("")
        }
    }
    
    private func getCurrentAppName() -> String {
        let workspace = NSWorkspace.shared
        if let frontmostApp = workspace.frontmostApplication {
            return frontmostApp.localizedName ?? "Unknown"
        }
        return "Unknown"
    }
    
    private func getCurrentWindowTitle() -> String {
        // This is a simplified version - in a real app you might want more sophisticated window detection
        return "Active Window"
    }

    deinit {
        stopLogging()
    }
}
