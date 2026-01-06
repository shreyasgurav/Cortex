//
//  MemoryOverlayButtonView.swift
//  Cortex
//
//  Small floating button that triggers memory search.
//

import SwiftUI

struct MemoryOverlayButtonView: View {
    @ObservedObject var manager: MemoryOverlayManager
    @State private var isHovering = false
    
    var body: some View {
        Group {
            switch manager.overlayState {
            case .idle, .empty:
                // Idle scanning state
                Image(systemName: "brain")
                    .opacity(0.6) // Boost opacity slightly
                    
            case .loading:
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
                    
            case .available(let count):
                HStack(spacing: 0) {
                    // Start simple: just the number
                    Text("\(count)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.7)) // White with low opacity
                        .fixedSize()
                }
                
            case .inserting:
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            }
        }
        .frame(width: 28, height: 28) // Force fixed square frame
        .background(
            Circle() // Perfect circle
                .fill(Color.black.opacity(0.7))
                .shadow(radius: 2)
        )
        .opacity(isHovering ? 1.0 : 0.8)
        .scaleEffect(isHovering ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onTapGesture {
            Task {
                await manager.insertRelatedMemories()
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}


