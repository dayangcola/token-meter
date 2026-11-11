import AppKit
import SwiftUI
import QuotaCore

@MainActor
final class HoverHostingView: NSHostingView<OverviewView> {
    var entered: (() -> Void)?
    var exited: (() -> Void)?
    private var hoverArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { entered?() }
    override func mouseExited(with event: NSEvent) { exited?() }
}

@MainActor
final class QuotaPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var store: QuotaStore!
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store = QuotaStore(demo: CommandLine.arguments.contains("--demo"))
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = statusImage()
            button.imagePosition = .imageOnly
            button.target = self; button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "AI 额度栏 · 悬停查看所有额度"
            button.setAccessibilityLabel("AI 额度栏")
            button.addTrackingArea(NSTrackingArea(rect: button.bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
        let quotaPanel = QuotaPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 300), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        quotaPanel.onEscape = { [weak self] in self?.hidePanel() }
        panel = quotaPanel
        panel.level = .statusBar
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        let hosting = HoverHostingView(rootView: OverviewView(store: store))
        hosting.entered = { [weak self] in self?.closeWork?.cancel() }
        hosting.exited = { [weak self] in self?.scheduleClose() }
        panel.contentView = hosting
        store.onPin = { [weak self] in self?.togglePin() }
        store.onClose = { [weak self] in self?.hidePanel() }
        store.onStatusChanged = { [weak self] in
            self?.updateStatus()
            // Cards grow or shrink when a reading arrives; keep the panel fitted while it is open.
            DispatchQueue.main.async { if self?.panel.isVisible == true { self?.showPanel() } }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown && event.keyCode == 53 && self.panel.isVisible { self.hidePanel(); return nil }
            if event.type != .keyDown && !self.store.isPinned && event.window != self.panel && event.window != self.statusItem.button?.window { self.hidePanel() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in guard let self, !self.store.isPinned else { return }; self.hidePanel() }
        }
        updateStatus()
        if CommandLine.arguments.contains("--show") { store.isPinned = true; showPanel() }
        store.refreshIfNeeded()
    }

    @objc(mouseEntered:) func statusMouseEntered(_ event: NSEvent) {
        closeWork?.cancel(); openWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.showPanel() }
        openWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    @objc(mouseExited:) func statusMouseExited(_ event: NSEvent) { openWork?.cancel(); scheduleClose() }

    @objc private func togglePanel() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let refresh = menu.addItem(withTitle: "刷新全部额度", action: #selector(refresh), keyEquivalent: "r"); refresh.target = self
            menu.addItem(.separator())
            let quit = menu.addItem(withTitle: "退出 AI 额度栏", action: #selector(quit), keyEquivalent: "q"); quit.target = self
            statusItem.menu = menu; statusItem.button?.performClick(nil); statusItem.menu = nil
            return
        }
        if panel.isVisible && store.isPinned { hidePanel() }
        else { store.isPinned = true; showPanel() }
    }
    @objc private func refresh() { store.refreshAll() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func togglePin() {
        store.isPinned.toggle()
        if !store.isPinned { scheduleClose() }
    }
    private func showPanel() {
        closeWork?.cancel()
        guard let button = statusItem.button, let window = button.window else { return }
        var anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        // The menu bar can hide the icon (notch, crowded bar); then its frame is off-screen and the panel falls back to the top-right corner.
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if screen == nil || !(screen!.frame.intersects(anchor)) || anchor.minY < visible.maxY - 1 {
            if CommandLine.arguments.contains("--diagnose") { FileHandle.standardError.write(Data("status item frame off-screen: \(anchor)\n".utf8)) }
            anchor = NSRect(x: visible.maxX - 60, y: visible.maxY, width: 43, height: 24)
        }
        // The panel is as tall as its cards, so everything shows without scrolling.
        let height = min(max(panel.contentView?.fittingSize.height ?? 300, 80), visible.height - 20)
        let x = min(max(anchor.maxX - 350 + 8, visible.minX + 10), visible.maxX - 360)
        panel.setFrame(NSRect(x: x, y: anchor.minY - height - 6, width: 350, height: height), display: true)
        panel.orderFrontRegardless()
        if store.isPinned && !panel.isKeyWindow { panel.makeKey() }
        store.refreshIfNeeded()
    }
    private func scheduleClose() {
        closeWork?.cancel()
        guard !store.isPinned else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.store.isPinned else { return }
            let point = NSEvent.mouseLocation
            if self.panel.frame.insetBy(dx: -4, dy: -8).contains(point) { return }
            self.hidePanel()
        }
        closeWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    private func hidePanel() { openWork?.cancel(); closeWork?.cancel(); store.isPinned = false; panel.orderOut(nil) }
    private func updateStatus() {
        statusItem.button?.image = statusImage()
        statusItem.button?.toolTip = "AI 额度栏 · \(store.connectedCount)/4 已连接\(store.lowCount > 0 ? " · 额度偏低" : "")"
    }
    /// The panel in miniature: four horizontal meters, top to bottom in panel order, each filled to that
    /// provider's tightest remaining window. No reading shows an empty track; under 20% orange, under 10% red.
    private func statusImage() -> NSImage {
        let now = Date()
        let levels: [Double?] = Provider.allCases.map { provider in
            store.states[provider]?.snapshot?.windows.filter { !$0.needsResetConfirmation(at: now) }.map(\.remaining).min()
        }
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: false) { _ in
            for (index, level) in levels.enumerated() {
                let y = 12.25 - CGFloat(index) * 3.75
                NSColor.labelColor.withAlphaComponent(0.25).setFill()
                NSBezierPath(roundedRect: NSRect(x: 0.5, y: y, width: 17, height: 2.5), xRadius: 1.25, yRadius: 1.25).fill()
                guard let level else { continue }
                (level < 10 ? NSColor.systemRed : level < 20 ? NSColor.systemOrange : NSColor.labelColor).setFill()
                let width = max(2.5, 17 * CGFloat(level) / 100)
                NSBezierPath(roundedRect: NSRect(x: 0.5, y: y, width: width, height: 2.5), xRadius: 1.25, yRadius: 1.25).fill()
            }
            return true
        }
        image.accessibilityDescription = "AI 额度栏"
        return image
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
