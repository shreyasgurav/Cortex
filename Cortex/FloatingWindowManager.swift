import SwiftUI
import AppKit

class FloatingWindowManager: ObservableObject {
    private var floatingWindow: NSWindow?
    @Published var isFloatingWindowVisible = false
    
    func showFloatingWindow() {
        if floatingWindow == nil {
            createFloatingWindow()
        }
        
        floatingWindow?.makeKeyAndOrderFront(nil)
        isFloatingWindowVisible = true
    }
    
    func hideFloatingWindow() {
        floatingWindow?.orderOut(nil)
        isFloatingWindowVisible = false
    }
    
    func toggleFloatingWindow() {
        if isFloatingWindowVisible {
            hideFloatingWindow()
        } else {
            showFloatingWindow()
        }
    }
    
    private func createFloatingWindow() {
        let contentView = FloatingMemoryView()
        let hostingView = NSHostingView(rootView: contentView)
        
        floatingWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 300, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        floatingWindow?.contentView = hostingView
        floatingWindow?.backgroundColor = NSColor.clear
        floatingWindow?.isOpaque = false
        floatingWindow?.hasShadow = true
        floatingWindow?.level = .floating
        floatingWindow?.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        
        // Make the entire window draggable
        let dragView = NSView()
        dragView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.addSubview(dragView)
        
        NSLayoutConstraint.activate([
            dragView.topAnchor.constraint(equalTo: hostingView.topAnchor),
            dragView.leadingAnchor.constraint(equalTo: hostingView.leadingAnchor),
            dragView.trailingAnchor.constraint(equalTo: hostingView.trailingAnchor),
            dragView.heightAnchor.constraint(equalToConstant: 50) // Increased height for better dragging
        ])
        
        let panGesture = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        dragView.addGestureRecognizer(panGesture)
    }
    
    @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
        guard let window = floatingWindow else { return }
        
        let translation = gesture.translation(in: window.contentView)
        
        switch gesture.state {
        case .began:
            // Start dragging
            break
        case .changed:
            let newOrigin = NSPoint(
                x: window.frame.origin.x + translation.x,
                y: window.frame.origin.y - translation.y
            )
            window.setFrameOrigin(newOrigin)
            gesture.setTranslation(.zero, in: window.contentView)
        case .ended:
            // Ensure window stays within screen bounds
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
            let windowFrame = window.frame
            
            var newOrigin = windowFrame.origin
            
            // Keep window within screen bounds
            if newOrigin.x < screenFrame.minX {
                newOrigin.x = screenFrame.minX
            }
            if newOrigin.y < screenFrame.minY {
                newOrigin.y = screenFrame.minY
            }
            if newOrigin.x + windowFrame.width > screenFrame.maxX {
                newOrigin.x = screenFrame.maxX - windowFrame.width
            }
            if newOrigin.y + windowFrame.height > screenFrame.maxY {
                newOrigin.y = screenFrame.maxY - windowFrame.height
            }
            
            window.setFrameOrigin(newOrigin)
        default:
            break
        }
    }
    
    deinit {
        floatingWindow?.close()
        floatingWindow = nil
    }
} 