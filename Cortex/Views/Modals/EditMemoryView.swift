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
            .ignoresSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                headerSection
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Memory Text Input
                        memoryTextSection
                        
                        // Tags Section
                        tagsSection
                        
                        // Action Buttons
                        actionButtonsSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
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
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Spacer()
            
            Text("Edit Memory")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            
            Spacer()
            
            // Placeholder for alignment
            Color.clear
                .frame(width: 28, height: 28)
        }
    }
    
    // MARK: - Memory Text Section
    private var memoryTextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Memory Text")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .frame(minHeight: 140)
                
                TextEditor(text: $memoryText)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                    .background(Color.clear)
            }
        }
    }
    
    // MARK: - Tags Section
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tags (Optional)")
                .font(.system(size: 18, weight: .semibold))
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
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
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
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
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
        VStack(spacing: 16) {
            // Save Button
            Button(action: saveMemory) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                    Text("Save Changes")
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .disabled(memoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(memoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
            
            // Cancel Button
            Button(action: { dismiss() }) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                    Text("Cancel")
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
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