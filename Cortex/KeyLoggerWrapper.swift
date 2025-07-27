import Foundation
import SwiftUI

class KeyLoggerWrapper: ObservableObject {
    private let logger = KeyLogger()
    
    @Published var currentBuffer: String = ""
    @Published var lastSavedText: String = ""
    @Published var errorMessage: String = ""
    @Published var isLogging: Bool = false

    func start() {
        logger.onBufferUpdate = { [weak self] buffer in
            DispatchQueue.main.async {
                self?.currentBuffer = buffer
            }
        }
        
        logger.onTextSaved = { [weak self] savedText in
            DispatchQueue.main.async {
                self?.lastSavedText = savedText
            }
        }
        
        logger.onError = { [weak self] error in
            DispatchQueue.main.async {
                self?.errorMessage = error
            }
        }
        
        logger.startLogging()
        isLogging = true
    }
    
    func stop() {
        logger.stopLogging()
        isLogging = false
    }
    
    func clearBuffer() {
        currentBuffer = ""
    }
}

