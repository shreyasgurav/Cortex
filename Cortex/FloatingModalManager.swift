import SwiftUI
import AppKit

class FloatingModalManager: NSObject, ObservableObject {
    private var floatingWindow: NSWindow?
    @Published var isVisible = false
    
    override init() {
        super.init()
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        // Remove existing observers first
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("ShowFloatingModal"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("HideFloatingModal"), object: nil)
        
        // Add observers for automatic show/hide
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showModalAutomatically),
            name: NSNotification.Name("ShowFloatingModal"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hideModalAutomatically),
            name: NSNotification.Name("HideFloatingModal"),
            object: nil
        )
    }
    
    @objc private func showModalAutomatically() {
        print("🔍 Auto-showing floating modal (typing detected)")
        showModal()
    }
    
    @objc private func hideModalAutomatically() {
        print("🔍 Auto-hiding floating modal (typing stopped)")
        hideModal()
    }
    
    func showModal() {
        if floatingWindow == nil {
            createFloatingWindow()
        }
        
        print("🔍 Showing floating modal")
        floatingWindow?.orderFront(nil)
        // Keep it floating by not making it key
        isVisible = true
    }
    
    func hideModal() {
        print("🔍 Hiding floating modal")
        floatingWindow?.orderOut(nil)
        isVisible = false
    }
    
    func toggleModal() {
        if isVisible {
            hideModal()
        } else {
            showModal()
        }
    }
    
    private func createFloatingWindow() {
        print("🔍 Creating floating window")
        let contentView = FloatingModalView()
        let hostingView = NSHostingView(rootView: contentView)
        
        // Get screen dimensions for flexible positioning
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        
        // Calculate flexible initial position (top-right corner with padding)
        let windowWidth: CGFloat = 320
        let windowHeight: CGFloat = 400
        let padding: CGFloat = 20
        
        let initialX = screenFrame.maxX - windowWidth - padding
        let initialY = screenFrame.maxY - windowHeight - padding
        
        floatingWindow = NonActivatingPanel(
            contentRect: NSRect(x: initialX, y: initialY, width: windowWidth, height: windowHeight),
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
        
        // Set window delegate to prevent activation
        floatingWindow?.delegate = self
        
        // Make the entire window draggable
        let dragView = NSView()
        dragView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.addSubview(dragView)
        
        NSLayoutConstraint.activate([
            dragView.topAnchor.constraint(equalTo: hostingView.topAnchor),
            dragView.leadingAnchor.constraint(equalTo: hostingView.leadingAnchor),
            dragView.trailingAnchor.constraint(equalTo: hostingView.trailingAnchor),
            dragView.heightAnchor.constraint(equalToConstant: 60) // Increased height for better dragging
        ])
        
        let panGesture = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        dragView.addGestureRecognizer(panGesture)
        
        // Add keyboard monitoring for Escape key
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                self?.hideModal()
                return nil
            }
            return event
        }
    }
    
    @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
        guard let window = floatingWindow else { return }
        
        let translation = gesture.translation(in: window.contentView)
        
        switch gesture.state {
        case .began:
            print("🔍 Started dragging window")
        case .changed:
            let newOrigin = NSPoint(
                x: window.frame.origin.x + translation.x,
                y: window.frame.origin.y - translation.y
            )
            window.setFrameOrigin(newOrigin)
            gesture.setTranslation(.zero, in: window.contentView)
        case .ended:
            print("🔍 Finished dragging window")
            // Keep window within screen bounds with flexible positioning
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
            let windowFrame = window.frame
            
            var newOrigin = windowFrame.origin
            let padding: CGFloat = 10
            
            // Flexible bounds checking - allow window to be partially off-screen but not completely
            if newOrigin.x < screenFrame.minX - windowFrame.width + padding {
                newOrigin.x = screenFrame.minX - windowFrame.width + padding
            }
            if newOrigin.y < screenFrame.minY - windowFrame.height + padding {
                newOrigin.y = screenFrame.minY - windowFrame.height + padding
            }
            if newOrigin.x > screenFrame.maxX - padding {
                newOrigin.x = screenFrame.maxX - padding
            }
            if newOrigin.y > screenFrame.maxY - padding {
                newOrigin.y = screenFrame.maxY - padding
            }
            
            window.setFrameOrigin(newOrigin)
        default:
            break
        }
    }

    deinit {
        print("🔍 FloatingModalManager deinit")
        NotificationCenter.default.removeObserver(self)
        floatingWindow?.close()
        floatingWindow = nil
    }
}

// MARK: - NSWindowDelegate
extension FloatingModalManager: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return true
    }
    
    func windowWillClose(_ notification: Notification) {
        isVisible = false
    }
    
    func windowDidResignKey(_ notification: Notification) {
        // Keep window floating even when it loses focus
        if let window = notification.object as? NSWindow, window == floatingWindow {
            print("🔍 Window resigned key, keeping it floating")
        }
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        // Prevent window from becoming key
        if let window = notification.object as? NSWindow, window == floatingWindow {
            print("🔍 Window became key, preventing activation")
            // Immediately resign key to keep it floating
            DispatchQueue.main.async {
                window.resignKey()
            }
        }
    }
} 
