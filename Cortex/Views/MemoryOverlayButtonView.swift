//
//  MemoryOverlayButtonView.swift
//  Cortex
//
//  Small floating button that triggers memory search.
//

import SwiftUI

struct MemoryOverlayButtonView: View {
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Image(systemName: "memorychip")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(6)
                .background(
                    Circle()
                        .fill(Color.accentColor)
                        .shadow(radius: 3)
                )
        }
        .buttonStyle(.plain)
    }
}


