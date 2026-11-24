import AppKit
import SwiftUI

/// Keeps one borderless desktop window per widget in step with the settings.
@MainActor
final class WidgetManager {
    weak var model: AppModel?
    private var panels: [UUID: WidgetPanel] = [:]

    func sync() {
        guard let model else { return }
        let configs = model.settings.widgets
        let ids = Set(configs.map(\.id))
        for (id, panel) in panels where !ids.contains(id) {
            panel.orderOut(nil)
            panels[id] = nil
        }
        for config in configs {
            let panel = panels[config.id] ?? {
                let panel = WidgetPanel(widgetID: config.id, model: model)
                panels[config.id] = panel
                return panel
            }()
            panel.apply(config, arranging: model.arranging)
        }
    }

    /// Transparent windows take their shadow from their content, which just changed.
    func imagesChanged() {
        for panel in panels.values { panel.invalidateShadow() }
    }
}

/// A borderless, transparent window that shows one widget. Normally it sits on the
/// desktop below your windows (and desktop icons), on every Space, and ignores the
/// mouse. While arranging it floats on top and can be dragged and resized.
final class WidgetPanel: NSPanel, NSWindowDelegate {
    let widgetID: UUID
    private weak var model: AppModel?
    private let overlay = ArrangeOverlayView()
    private var applying = false

    @MainActor
    init(widgetID: UUID, model: AppModel) {
        self.widgetID = widgetID
        self.model = model
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        minSize = WidgetConfig.minimumSize

        let host = NSHostingView(rootView: WidgetView(widgetID: widgetID).environment(model))
        let container = NSView()
        for view in [host, overlay] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = true
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        contentView = container
        delegate = self
    }

    override var canBecomeKey: Bool { false }

    @MainActor
    func apply(_ config: WidgetConfig, arranging: Bool) {
        applying = true
        defer { applying = false }
        if !frame.equalTo(config.frame) { setFrame(config.frame, display: true) }
        for view in contentView?.subviews ?? [] { view.frame = contentView?.bounds ?? .zero }
        level = arranging ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        ignoresMouseEvents = !arranging
        overlay.isHidden = !arranging
        hasShadow = config.shadow
        alphaValue = config.opacity
        orderFront(nil)
    }

    func windowDidMove(_ notification: Notification) { frameChanged() }
    func windowDidResize(_ notification: Notification) { frameChanged() }

    private func frameChanged() {
        guard !applying else { return }
        let frame = frame
        let id = widgetID
        MainActor.assumeIsolated { self.model?.widgetFrameChanged(id, frame: frame) }
    }
}

/// Covers a widget while arranging: drag to move, drag the bottom-right corner to resize.
final class ArrangeOverlayView: NSView {
    private static let grip: CGFloat = 22
    private var resizing = false
    private var startFrame = CGRect.zero
    private var startMouse = CGPoint.zero

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let point = convert(event.locationInWindow, from: nil)
        resizing = point.x > bounds.maxX - Self.grip && point.y < bounds.minY + Self.grip
        if resizing {
            startFrame = window.frame
            startMouse = NSEvent.mouseLocation
        } else {
            window.performDrag(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard resizing, let window else { return }
        let mouse = NSEvent.mouseLocation
        let width = max(WidgetConfig.minimumSize.width, startFrame.width + mouse.x - startMouse.x)
        let height = max(WidgetConfig.minimumSize.height, startFrame.height - (mouse.y - startMouse.y))
        // Keep the top-left corner where it is (AppKit's origin is bottom-left).
        window.setFrame(CGRect(x: startFrame.minX, y: startFrame.maxY - height, width: width, height: height), display: true)
    }

    override func mouseUp(with event: NSEvent) { resizing = false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
        addCursorRect(CGRect(x: bounds.maxX - Self.grip, y: bounds.minY, width: Self.grip, height: Self.grip), cursor: .crosshair)
    }
}

/// The widget's content: the screen's latest image, plus guides while arranging.
struct WidgetView: View {
    let widgetID: UUID
    @Environment(AppModel.self) private var model

    var body: some View {
        let config = model.settings.widgets.first { $0.id == widgetID }
        let radius = config?.cornerRadius ?? 12
        ZStack {
            if let config, let image = model.images[config.screenID] {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: config.fit == .fill ? .fill : .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "rectangle.dashed")
                            Text(placeholder(config)).font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
            }
            if model.arranging, let config {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                VStack {
                    Spacer()
                    HStack {
                        Text("\(config.screenID) · \(Int(config.width))×\(Int(config.height))")
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.thickMaterial, in: Capsule())
                        Spacer()
                        Image(systemName: "arrow.down.right")
                            .font(.caption.bold())
                            .padding(6)
                            .background(Color.accentColor, in: Circle())
                            .foregroundStyle(.white)
                    }
                    .padding(6)
                }
            }
        }
    }

    private func placeholder(_ config: WidgetConfig?) -> String {
        guard let config else { return "" }
        if !model.signedIn { return "Sign in to Surfaces" }
        if !model.screens.isEmpty, model.screen(config.screenID) == nil { return "“\(config.screenID)” no longer exists" }
        return "Loading “\(config.screenID)”…"
    }
}
