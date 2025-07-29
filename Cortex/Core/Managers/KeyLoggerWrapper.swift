import Foundation
import SwiftUI

class KeyLoggerWrapper: ObservableObject {
    private let keyLogger = KeyLogger()
    @Published var currentBuffer = ""
    @Published var lastSavedText = ""
    @Published var errorMessage: String?
    @Published var isLogging = false
    private var typingDebounceTimer: Timer?
    
    init() {
        setupCallbacks()
    }
    
    private func setupCallbacks() {
        keyLogger.onBufferUpdate = { [weak self] buffer in
            DispatchQueue.main.async {
                self?.currentBuffer = buffer
            }
        }
        
        keyLogger.onTextSaved = { [weak self] text in
            DispatchQueue.main.async {
                self?.lastSavedText = text
            }
        }
        
        keyLogger.onError = { [weak self] error in
            DispatchQueue.main.async {
                self?.errorMessage = error
            }
        }
        
        keyLogger.onTypingStarted = { [weak self] in
            // Add a small delay to prevent rapid show/hide cycles
            self?.typingDebounceTimer?.invalidate()
            self?.typingDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                DispatchQueue.main.async {
                    print("🔍 [KeyLoggerWrapper] Showing floating modal after delay")
                    NotificationCenter.default.post(name: NSNotification.Name("ShowFloatingModal"), object: nil)
                }
            }
        }
        
        keyLogger.onTypingStopped = { [weak self] in
            // Add a small delay to prevent rapid show/hide cycles
            self?.typingDebounceTimer?.invalidate()
            self?.typingDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                DispatchQueue.main.async {
                    print("🔍 [KeyLoggerWrapper] Hiding floating modal after delay")
                    NotificationCenter.default.post(name: NSNotification.Name("HideFloatingModal"), object: nil)
                }
            }
        }
    }
    
    func start() {
        keyLogger.startLogging()
        isLogging = true
        print("🔍 KeyLoggerWrapper: Started logging")
    }
    
    func stop() {
        keyLogger.stopLogging()
        isLogging = false
        print("🔍 KeyLoggerWrapper: Stopped logging")
    }
    
    func clearBuffer() {
        keyLogger.clearBuffer()
    }
    
    deinit {
        typingDebounceTimer?.invalidate()
    }
}

