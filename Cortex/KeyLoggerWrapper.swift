import Foundation
import SwiftUI

class KeyLoggerWrapper: ObservableObject {
    private let keyLogger = KeyLogger()
    @Published var currentBuffer = ""
    @Published var lastSavedText = ""
    @Published var errorMessage: String?
    @Published var isLogging = false
    
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
        
        keyLogger.onTypingStarted = {
            DispatchQueue.main.async {
                // Show floating modal when typing starts
                NotificationCenter.default.post(name: NSNotification.Name("ShowFloatingModal"), object: nil)
            }
        }
        
        keyLogger.onTypingStopped = {
            DispatchQueue.main.async {
                // Hide floating modal when typing stops
                NotificationCenter.default.post(name: NSNotification.Name("HideFloatingModal"), object: nil)
            }
        }
    }
    
    func start() {
        keyLogger.startLogging()
        isLogging = true
    }
    
    func stop() {
        keyLogger.stopLogging()
        isLogging = false
    }
    
    func clearBuffer() {
        keyLogger.clearBuffer()
    }
}

