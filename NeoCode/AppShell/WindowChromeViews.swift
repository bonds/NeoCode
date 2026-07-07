import AppKit
import SwiftUI

struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragRegionView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DragRegionView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let view = super.hitTest(point) { return view }
        return bounds.contains(point) ? self : nil
    }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount >= 2 {
            window?.zoom(nil)
            return
        }
        super.mouseUp(with: event)
    }
}

struct WindowChromeConfigurator: NSViewRepresentable {
    let updateService: AppUpdateService

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView)
        }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.styleMask.insert(.fullSizeContentView)
        if NeoCodeTheme.isSidebarTranslucent {
            window.isOpaque = false
            window.backgroundColor = .clear
        } else {
            window.isOpaque = true
            window.backgroundColor = NeoCodeTheme.canvasColor
        }
        window.minSize = NSSize(width: 980, height: 600)
        updateService.attach(to: window)
    }
}
