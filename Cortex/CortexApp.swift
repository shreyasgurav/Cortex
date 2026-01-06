//
//  CortexApp.swift
//  Cortex
//
//  A macOS menu bar app that captures and stores text
//  you send from any application.
//

import SwiftUI
import Combine

@main
struct CortexApp: App {
    // Use AppDelegate for menu bar management
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Memory Window
        Window("Cortex", id: "memory-window") {
            MemoryWindowView(appState: AppState.shared)
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            // Remove default New Window command
            CommandGroup(replacing: .newItem) {}
        }
        
        // Settings/Onboarding Window
        Window("Setup", id: "onboarding-window") {
            if let permissionsManager = appDelegate.permissionsManager {
                OnboardingView(permissionsManager: permissionsManager) {
                    appDelegate.dismissOnboarding()
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 560, height: 640)
        .windowResizability(.contentSize)
    }
}

// MARK: - App Delegate

/// AppDelegate handles menu bar setup and application lifecycle
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    /// Status bar item (menu bar icon)
    private var statusItem: NSStatusItem?
    
    /// Popover for menu bar dropdown
    private var popover: NSPopover?
    
    /// Event monitor for clicking outside popover
    private var eventMonitor: Any?
    
    // MARK: - Core Components
    
    private(set) var permissionsManager: PermissionsManager?
    private var accessibilityWatcher: AccessibilityWatcher?
    private var keyEventListener: KeyEventListener?
    private var captureCoordinator: CaptureCoordinator?
    private var memoryStore: MemoryStore?
    
    // MARK: - App Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize core components
        setupComponents()
        
        // Setup menu bar
        setupMenuBar()
        
        // Check if we need to show onboarding
        checkOnboarding()
        
        // Start capturing if permissions are granted
        startCaptureIfPossible()
        
        // Hide dock icon (we're a menu bar app)
        NSApp.setActivationPolicy(.accessory)
        
        print("[Cortex] Application launched")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        captureCoordinator?.stop()
        permissionsManager?.stopMonitoring()
        print("[Cortex] Application terminating")
    }
    
    // MARK: - Setup
    
    private func setupComponents() {
        // Initialize memory store
        do {
            memoryStore = try MemoryStore()
            AppState.shared.setup(memoryStore: memoryStore!)
        } catch {
            print("[Cortex] Failed to initialize memory store: \(error)")
            // Continue without storage - app will still run but won't save
        }
        
        // Initialize managers
        permissionsManager = PermissionsManager()
        accessibilityWatcher = AccessibilityWatcher()
        keyEventListener = KeyEventListener()
        
        // Initialize coordinator
        if let store = memoryStore,
           let permissions = permissionsManager,
           let watcher = accessibilityWatcher,
           let keyListener = keyEventListener {
            captureCoordinator = CaptureCoordinator(
                accessibilityWatcher: watcher,
                keyEventListener: keyListener,
                memoryStore: store,
                permissionsManager: permissions
            )
        }
        
        // Observe state changes
        setupObservers()
    }
    
    private func setupObservers() {
        // Watch for permission changes to auto-start capture (only on actual change)
        permissionsManager?.$accessibilityGranted
            .removeDuplicates() // Only fire when value actually changes
            .dropFirst() // Skip initial value
            .sink { [weak self] granted in
                if granted {
                    print("[Cortex] Accessibility permission granted, starting capture...")
                    self?.startCaptureIfPossible()
                }
            }
            .store(in: &cancellables)
        
        // Watch for capture state changes
        AppState.shared.$captureEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in
                if enabled {
                    self?.startCaptureIfPossible()
                } else {
                    self?.captureCoordinator?.stop()
                }
            }
            .store(in: &cancellables)
        
        AppState.shared.$privacyModeEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in
                if enabled {
                    self?.captureCoordinator?.stop()
                } else {
                    self?.startCaptureIfPossible()
                }
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private func setupMenuBar() {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // Use SF Symbol for menu bar icon
            button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Cortex")
            button.image?.size = NSSize(width: 18, height: 18)
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Create popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 280, height: 400)
        popover?.behavior = .transient
        popover?.animates = true
        
        updatePopoverContent()
        
        // Monitor for clicks outside popover
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }
    
    private func updatePopoverContent() {
        guard let permissions = permissionsManager else { return }
        
        let menuView = MenuBarView(
            appState: AppState.shared,
            permissionsManager: permissions,
            onOpenMemory: { [weak self] in
                self?.openMemoryWindow()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
        
        popover?.contentViewController = NSHostingController(rootView: menuView)
    }
    
    // MARK: - Popover Actions
    
    @objc private func togglePopover() {
        if let popover = popover, popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }
    
    private func showPopover() {
        updatePopoverContent()
        
        if let button = statusItem?.button {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            
            // Activate app to ensure popover gets focus
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func closePopover() {
        popover?.performClose(nil)
    }
    
    // MARK: - Window Management
    
    func openMemoryWindow() {
        closePopover()
        
        // Open the memory window
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "memory-window" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Use SwiftUI's openWindow
            // Try to open window via standard mechanism
            if #available(macOS 13.0, *) {
                // Use environment to open window
            }
        }
        
        // Show app in dock temporarily and activate
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        // Return to accessory mode after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Only go back to accessory if memory window is the only window
            // This allows the window to stay visible
        }
    }
    
    private func checkOnboarding() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        
        if !hasCompletedOnboarding || !(permissionsManager?.accessibilityGranted ?? false) {
            showOnboarding()
        }
    }
    
    func showOnboarding() {
        AppState.shared.showOnboarding = true
        
        // Activate app and show onboarding
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func dismissOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        AppState.shared.showOnboarding = false
        
        // Start capturing now that onboarding is complete
        startCaptureIfPossible()
        
        // Return to menu bar app mode
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Close onboarding window
            for window in NSApp.windows {
                if window.identifier?.rawValue == "onboarding-window" {
                    window.close()
                }
            }
            
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    // MARK: - Capture Management
    
    private func startCaptureIfPossible() {
        guard permissionsManager?.accessibilityGranted == true else {
            print("[Cortex] Cannot start capture - accessibility not granted")
            return
        }
        
        captureCoordinator?.start()
    }
    
    func updateCaptureState() {
        captureCoordinator?.updateCaptureState()
    }
}

// MARK: - Environment Key

private struct AppDelegateKey: EnvironmentKey {
    static let defaultValue: AppDelegate? = nil
}

extension EnvironmentValues {
    var appDelegate: AppDelegate? {
        get { self[AppDelegateKey.self] }
        set { self[AppDelegateKey.self] = newValue }
    }
}
