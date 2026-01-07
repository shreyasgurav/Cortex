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
                ZStack {
                    Image(systemName: "brain")
                        .opacity(isHovering ? 0 : 0.6)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .opacity(isHovering ? 1.0 : 0)
                }
                
            case .loading:
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
                    
            case .available(let count):
                if count > 0 {
                    HStack(spacing: 0) {
                        Text("\(count)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .fixedSize()
                    }
                } else {
                    // 0 results - show plus icon to allow manual add
                    Image(systemName: isHovering ? "plus" : "brain")
                        .font(.system(size: 14, weight: isHovering ? .bold : .medium))
                        .opacity(0.6)
                }
                
            case .inserting:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
            }
        }
        .frame(width: 28, height: 28)
        .background(
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.7))
                if isHovering {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                }
            }
            .shadow(radius: 2)
        )
        .opacity(isHovering ? 1.0 : 0.8)
        .scaleEffect(isHovering ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
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


