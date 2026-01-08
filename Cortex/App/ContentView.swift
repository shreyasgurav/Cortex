//
//  ContentView.swift
//  Cortex
//
//  This file is kept for compatibility but the main UI
//  is now in MemoryWindowView.swift
//

import SwiftUI

/// Legacy content view - redirects to MemoryWindowView
struct ContentView: View {
    var body: some View {
        MemoryWindowView(appState: AppState.shared)
    }
}

#Preview {
    ContentView()
}
