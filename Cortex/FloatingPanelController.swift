import AppKit

class FloatingPanelController: NSWindowController {
    let memoryListView = MemoryListView()
    let fetcher = MemoryFetcher()

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 800, y: 400, width: 340, height: 400),
            styleMask: [.titled, .nonactivatingPanel, .closable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.97)
        panel.hasShadow = true
        panel.title = "Cortex Memories"
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        super.init(window: panel)
        panel.contentView = memoryListView

        fetcher.onUpdate = { [weak self] in
            self?.memoryListView.update(with: self?.fetcher.memories ?? [])
        }
        memoryListView.onMemoryClick = { memory in
            panel.orderOut(nil) // Hide before injecting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                TextInjector.insert(memory.text)
            }
        }
        fetcher.fetchMemories()
    }

    required init?(coder: NSCoder) { fatalError() }
}
