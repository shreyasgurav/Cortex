
import SwiftUI
import FirebaseFirestore
import FirebaseCore

struct ContentView: View {
    @StateObject private var logger = KeyLoggerWrapper()
    @StateObject private var memoryManager = MemoryManager()
    @StateObject private var floatingModalManager: FloatingModalManager
    @State private var showSavedMessage: Bool = false
    @State private var showAddMemorySheet: Bool = false
    @State private var memorySearchText: String = ""
    @State private var editingMemory: Memory?
    @State private var showingDeleteAlert = false
    @State private var memoryToDelete: Memory?
    
    init() {
        let memoryManager = MemoryManager()
        self._memoryManager = StateObject(wrappedValue: memoryManager)
        self._floatingModalManager = StateObject(wrappedValue: FloatingModalManager(memoryManager: memoryManager))
    }
    
    var body: some View {
        ZStack {
            // Premium gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.02, green: 0.02, blue: 0.08),
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.08, green: 0.08, blue: 0.20),
                    Color(red: 0.12, green: 0.12, blue: 0.25)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Animated gradient orbs
            GeometryReader { geometry in
                ForEach(0..<8, id: \.self) { index in
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    [Color.blue, Color.purple, Color.cyan, Color.pink][index % 4].opacity(0.1),
                                    Color.clear
                                ]),
                                center: .center,
                                startRadius: 10,
                                endRadius: 100
                            )
                        )
                        .frame(width: CGFloat.random(in: 120...200))
                        .position(
                            x: CGFloat.random(in: 0...geometry.size.width),
                            y: CGFloat.random(in: 0...geometry.size.height)
                        )
                        .animation(
                            Animation.easeInOut(duration: Double.random(in: 4...8))
                                .repeatForever(autoreverses: true),
                            value: index
                        )
                        .blur(radius: 30)
                }
            }

            ScrollView {
                VStack(spacing: 40) {
                    // Hero Header
                    heroHeaderSection
                    
                    // Status Dashboard
                    statusDashboard
                    
                    // Error Card (if needed)
                    if let errorMessage = logger.errorMessage, !errorMessage.isEmpty {
                        errorCard(message: errorMessage)
                    }
                    
                    // Main Controls
                    mainControlsSection
                    
                    // Memory Management
                    memoryDashboardSection
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 40)
            }
        }
        .onAppear { 
            print("🔍 [ContentView] View appeared")
            logger.start()
            print("🔍 [ContentView] Logger started")
            memoryManager.loadMemories()
            print("🔍 [ContentView] MemoryManager loadMemories called")
            
            // Show floating modal immediately for testing
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                print("🔍 [ContentView] Auto-showing floating modal for immediate access")
                floatingModalManager.showModal()
            }
        }
        .sheet(isPresented: $showAddMemorySheet) {
            AddMemoryView(memoryManager: memoryManager)
        }
        .sheet(item: $editingMemory) { memory in
            EditMemoryView(memory: memory, memoryManager: memoryManager)
        }
        .alert("Delete Memory", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let memory = memoryToDelete {
                    memoryManager.deleteMemory(memory)
                }
            }
        } message: {
            Text("Are you sure you want to delete this memory? This action cannot be undone.")
        }
    }
    
    // MARK: - Hero Header Section
    private var heroHeaderSection: some View {
        VStack(spacing: 24) {
            // Logo and branding
            HStack {
                // Premium logo design
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.cyan.opacity(0.8),
                                    Color.blue.opacity(0.9),
                                    Color.purple.opacity(0.8)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                        .shadow(color: Color.blue.opacity(0.5), radius: 15, x: 0, y: 8)
                    
                    Image("Image")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Status indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(logger.isLogging ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.5), value: logger.isLogging)
                    
                    Text(logger.isLogging ? "Active" : "Inactive")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.1))
                .cornerRadius(20)
            }
            
            // Main title and description
            VStack(spacing: 12) {
                Text("Cortex")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white,
                                Color.cyan.opacity(0.8),
                                Color.blue.opacity(0.7)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
                
                Text("AI-Powered Memory Assistant")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text("Intelligently captures and suggests your memories as you type")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
    }
    

    
    // MARK: - Error Card
    private func errorCard(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 18))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Error")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)
                
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
    

    
    // MARK: - Status Dashboard
    private var statusDashboard: some View {
        HStack(spacing: 20) {
            // Keylogging Status
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(logger.isLogging ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: logger.isLogging ? "keyboard" : "keyboard.slash")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(logger.isLogging ? .green : .gray)
                }
                
                Text("Keylogging")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text(logger.isLogging ? "Active" : "Inactive")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(logger.isLogging ? .green : .gray)
            }
            
            // Memory Count
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.blue)
                }
                
                Text("Memories")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text("\(memoryManager.memories.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.blue)
            }
            
            // Floating Modal Status
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(floatingModalManager.isVisible ? Color.purple.opacity(0.2) : Color.gray.opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: floatingModalManager.isVisible ? "eye" : "eye.slash")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(floatingModalManager.isVisible ? .purple : .gray)
                }
                
                Text("Float Modal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text(floatingModalManager.isVisible ? "Visible" : "Hidden")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(floatingModalManager.isVisible ? .purple : .gray)
            }
        }
        .padding(24)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.05))
                
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.05)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
    
    // MARK: - Main Controls Section
    private var mainControlsSection: some View {
        VStack(spacing: 20) {
            // Primary Action Button
            Button(action: {
                if logger.isLogging {
                    logger.stop()
                } else {
                    logger.start()
                }
            }) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: logger.isLogging ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(logger.isLogging ? "Stop Capturing" : "Start Capturing")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text(logger.isLogging ? "Click to pause memory collection" : "Begin capturing your keystrokes")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Spacer()
                }
                .padding(20)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: logger.isLogging ? [
                                        Color.red.opacity(0.8),
                                        Color.red.opacity(0.6)
                                    ] : [
                                        Color.green.opacity(0.8),
                                        Color.green.opacity(0.6)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    }
                )
                .shadow(color: (logger.isLogging ? Color.red : Color.green).opacity(0.3), radius: 15, x: 0, y: 8)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Secondary Controls
            HStack(spacing: 16) {
                // Floating Modal Toggle
                Button(action: { floatingModalManager.toggleModal() }) {
                    HStack(spacing: 8) {
                        Image(systemName: floatingModalManager.isVisible ? "eye.slash" : "eye")
                            .font(.system(size: 14, weight: .semibold))
                        Text(floatingModalManager.isVisible ? "Hide" : "Show")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.purple.opacity(0.2))
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.purple.opacity(0.4), lineWidth: 1)
                        }
                    )
                    .foregroundColor(.purple)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Add Memory Button
                Button(action: { showAddMemorySheet = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Add")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.2))
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                        }
                    )
                    .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    // MARK: - Memory Dashboard Section
    private var memoryDashboardSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with stats
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Memory Collection")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("\(memoryManager.memories.count) memories stored")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Quick action button
                Button(action: { showAddMemorySheet = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("New")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.8))
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Enhanced Search Bar
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                    
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        TextField("Search memories...", text: $memorySearchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .medium))
                        
                        if !memorySearchText.isEmpty {
                            Button(action: { memorySearchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                
                // Full management button
                Button(action: { 
                    // Could open a dedicated management view
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 12, weight: .medium))
                        Text("Manage")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    )
                    .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Content Preview
            VStack(alignment: .leading, spacing: 12) {
                if memoryManager.isLoading {
                    loadingView
                } else if filteredMemories.isEmpty {
                    emptyStateView
                } else {
                    // Recent memories preview (first 3)
                    ForEach(Array(filteredMemories.prefix(3))) { memory in
                        memoryPreviewCard(memory: memory)
                    }
                    
                    if filteredMemories.count > 3 {
                        Button(action: { 
                            // Could open full memory list
                        }) {
                            HStack {
                                Text("View all \(filteredMemories.count) memories")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.blue)
                                
                                Spacer()
                                
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.blue)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.blue.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding(24)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.05))
                
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.05)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.black.opacity(0.1), radius: 15, x: 0, y: 8)
    }
    
    // MARK: - Memory Management Helper Views
    private var filteredMemories: [Memory] {
        memoryManager.searchMemories(query: memorySearchText)
    }
    
    private var loadingView: some View {
        HStack {
            ProgressView()
                .scaleEffect(1.0)
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
            
            Text("Loading memories...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 32))
                .foregroundColor(.blue.opacity(0.6))
            
            Text(memorySearchText.isEmpty ? "No memories yet" : "No memories found")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            
            Text(memorySearchText.isEmpty ? "Start capturing or add memories manually" : "Try adjusting your search terms")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    private var memoriesListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredMemories) { memory in
                    MemoryCardView(
                        memory: memory,
                        onEdit: { editingMemory = memory },
                        onDelete: {
                            memoryToDelete = memory
                            showingDeleteAlert = true
                        }
                    )
                }
            }
        }
        .frame(maxHeight: 300)
    }
    
    private func memoryPreviewCard(memory: Memory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            memoryCardHeader(memory: memory)
            memoryCardFooter(memory: memory)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(memoryCardBackground)
    }
    
    private func memoryCardHeader(memory: Memory) -> some View {
        HStack {
            memoryTextContent(memory: memory)
            Spacer()
            memoryActionButtons(memory: memory)
        }
    }
    
    private func memoryTextContent(memory: Memory) -> some View {
        Text(memory.text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }
    
    private func memoryActionButtons(memory: Memory) -> some View {
        HStack(spacing: 8) {
            Button(action: { editingMemory = memory }) {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: { 
                memoryToDelete = memory
                showingDeleteAlert = true
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private func memoryCardFooter(memory: Memory) -> some View {
        HStack {
            memoryTagsView(memory: memory)
            Spacer()
            memoryTimestamp(memory: memory)
        }
    }
    
    private func memoryTagsView(memory: Memory) -> some View {
        Group {
            if !memory.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(memory.tags.prefix(3), id: \.self) { tag in
                            memoryTag(tag: tag)
                        }
                    }
                }
            }
        }
    }
    
    private func memoryTag(tag: String) -> some View {
        Text(tag)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.blue)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.blue.opacity(0.15))
            )
    }
    
    private func memoryTimestamp(memory: Memory) -> some View {
        Text(memory.timestamp, style: .relative)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.secondary)
    }
    
    private var memoryCardBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}

#Preview {
    ContentView()
}
