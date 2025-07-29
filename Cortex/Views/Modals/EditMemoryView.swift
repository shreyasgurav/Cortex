import SwiftUI

struct EditMemoryView: View {
    let memory: Memory
    @ObservedObject var memoryManager: MemoryManager
    @Environment(\.dismiss) private var dismiss
    @State private var memoryText: String
    @State private var tags: [String]
    @State private var newTag = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    
    init(memory: Memory, memoryManager: MemoryManager) {
        self.memory = memory
        self.memoryManager = memoryManager
        self._memoryText = State(initialValue: memory.text)
        self._tags = State(initialValue: memory.tags)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.12),
                        Color(red: 0.08, green: 0.08, blue: 0.18),
                        Color(red: 0.12, green: 0.12, blue: 0.25)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Memory Text Input
                    memoryTextSection
                    
                    // Tags Section
                    tagsSection
                    
                    Spacer()
                    
                    // Action Buttons
                    actionButtonsSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }

        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            Text("Edit Memory")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            
            Spacer()
            
            // Placeholder for alignment
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(.clear)
        }
    }
    
    // MARK: - Memory Text Section
    private var memoryTextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Memory Text")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            
            TextEditor(text: $memoryText)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .padding(16)
                .frame(minHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
        }
    }
    
    // MARK: - Tags Section
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tags (Optional)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            
            // Add Tag Input
            HStack {
                TextField("Add tag...", text: $newTag)
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(.white)
                    .onSubmit {
                        addTag()
                    }
                
                Button(action: addTag) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            
            // Tags Display
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 6) {
                                Text(tag)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.blue)
                                
                                Button(action: { removeTag(tag) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.blue.opacity(0.2))
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }
    
    // MARK: - Action Buttons Section
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            // Save Button
            Button(action: saveMemory) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                    Text("Save Changes")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue)
                )
            }
            .disabled(memoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(memoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
            
            // Cancel Button
            Button(action: { dismiss() }) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
            }
        }
    }
    
    // MARK: - Helper Methods
    private func addTag() {
        let trimmedTag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTag.isEmpty else { return }
        
        if !tags.contains(trimmedTag) {
            tags.append(trimmedTag)
        }
        
        newTag = ""
    }
    
    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
    
    private func saveMemory() {
        let trimmedText = memoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedText.isEmpty else {
            errorMessage = "Memory text cannot be empty"
            showingError = true
            return
        }
        
        // Create updated memory
        var updatedMemory = memory
        updatedMemory.text = trimmedText
        updatedMemory.tags = tags
        
        memoryManager.updateMemory(updatedMemory)
        
        // Check for errors
        if let error = memoryManager.errorMessage {
            errorMessage = error
            showingError = true
        } else {
            dismiss()
        }
    }
} 