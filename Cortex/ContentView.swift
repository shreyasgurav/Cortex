
import SwiftUI
import FirebaseFirestore
import FirebaseCore

struct ContentView: View {
    @StateObject private var logger = KeyLoggerWrapper()
    @StateObject private var floatingModalManager = FloatingModalManager()
    @State private var showSavedMessage: Bool = false
    
    var body: some View {
        ZStack {
            // Modern gradient background
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
            
            // Animated background particles
            GeometryReader { geometry in
                ForEach(0..<20, id: \.self) { index in
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: CGFloat.random(in: 2...6))
                        .position(
                            x: CGFloat.random(in: 0...geometry.size.width),
                            y: CGFloat.random(in: 0...geometry.size.height)
                        )
                        .animation(
                            Animation.easeInOut(duration: Double.random(in: 3...8))
                                .repeatForever(autoreverses: true),
                            value: index
                        )
                }
            }

            VStack(spacing: 32) {
                // Modern Header
                headerSection
                
                // Status Card
                statusCard
                
                // Error Card (if needed)
                if let errorMessage = logger.errorMessage, !errorMessage.isEmpty {
                    errorCard(message: errorMessage)
                }
                
                // Last Saved Text Card (if available)
                if !logger.lastSavedText.isEmpty {
                    savedTextCard
                }
                
                // Control Buttons
                controlButtonsSection
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
        }
        .onAppear { logger.start() }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        HStack(spacing: 16) {
            // Animated logo
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [Color.blue, Color.purple]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 48, height: 48)
                    .shadow(color: .blue.opacity(0.3), radius: 12, x: 0, y: 6)
                
                Image("Image")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundColor(.white)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Cortex")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(
                        gradient: Gradient(colors: [Color.white, Color.blue.opacity(0.8)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                
                Text("AI-Powered Memory Assistant")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.top, 20)
    }
    
    // MARK: - Status Card
    private var statusCard: some View {
        HStack(spacing: 12) {
            // Animated status indicator
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                    .frame(width: 20, height: 20)
                
                Circle()
                    .fill(logger.isLogging ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                    .scaleEffect(logger.isLogging ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: logger.isLogging)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(logger.isLogging ? "Active" : "Inactive")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(logger.isLogging ? .green : .red)
                
                Text(logger.isLogging ? "Capturing keystrokes globally" : "Ready to start monitoring")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
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
    
    // MARK: - Saved Text Card
    private var savedTextCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
                
                Text("Last Saved")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            Text(logger.lastSavedText)
                .font(.system(.body, design: .monospaced))
                .padding(16)
                .frame(minHeight: 80, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.green.opacity(0.2), lineWidth: 1)
                        )
                )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Control Buttons Section
    private var controlButtonsSection: some View {
        VStack(spacing: 16) {
            // Start/Stop Button
            Button(action: {
                if logger.isLogging {
                    logger.stop()
                } else {
                    logger.start()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: logger.isLogging ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 16))
                    Text(logger.isLogging ? "Stop Capturing" : "Start Capturing")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: logger.isLogging ? [Color.red, Color.red.opacity(0.8)] : [Color.green, Color.green.opacity(0.8)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(color: (logger.isLogging ? Color.red : Color.green).opacity(0.3), radius: 8, x: 0, y: 4)
            }
            
            // Floating Modal Toggle
            Button(action: { floatingModalManager.toggleModal() }) {
                HStack(spacing: 8) {
                    Image(systemName: floatingModalManager.isVisible ? "eye.slash" : "eye")
                        .font(.system(size: 16))
                    Text(floatingModalManager.isVisible ? "Hide Memories" : "Show Memories")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.purple, Color.purple.opacity(0.8)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(color: Color.purple.opacity(0.3), radius: 8, x: 0, y: 4)
            }
        }
    }
}

#Preview {
    ContentView()
}
