import AppKit
import SwiftUI
import Charts

struct Day: Codable, Identifiable, Sendable, Equatable { var date: String; var credits: Double; var models: [String: Double]?; var tokens: [String: Double]?; var estimatedUSD: Double?; var id: String { date } }
struct Snapshot: Codable, Sendable, Equatable {
    var state: String; var message: String
    var fetchedAt: String?; var dataAsOf: String?
    var credits: Double?; var estimatedUSD: Double?; var todayCredits: Double?; var dayEstimatedUSD: Double?
    var daily: [Day]?; var rangeStart: String?; var rangeEnd: String?
    var usdPerCredit: Double?; var tokensAvailable: Bool?; var tokenDataAsOf: String?
}
enum Dates {
    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    static func key(_ d: Date) -> String { let f = DateFormatter(); f.timeZone = calendar.timeZone; f.dateFormat = "yyyy-MM-dd"; return f.string(from: d) }
    static func shift(_ n: Int, _ d: Date) -> Date { calendar.date(byAdding: .day, value: n, to: d)! }
}
@MainActor final class Store: ObservableObject {
    @Published var current = Snapshot(state: "loading", message: "Connecting…")
    @Published var history = Snapshot(state: "loading", message: "Loading…")
    @Published var selected = Dates.calendar.startOfDay(for: Date())
    @Published var expanded = false
    @Published var contentMounted = false
    @Published var reveal: Double = 0
    @Published var liquidRadius: CGFloat = 10
    @Published var notchInset: CGFloat = 0
    @Published var busy = false
    @Published var loading = false
    @Published var edge = DockEdge.top
    @Published var bubble = false
    @Published var dragging = false
    @Published var dailyLimit = UserDefaults.standard.double(forKey: "paceDailyLimit")
    @Published var monthlyLimit = UserDefaults.standard.double(forKey: "paceMonthlyLimit")
    lazy var pace = PaceBridge(store: self)
    var dashboardBridge: PaceBridge?
    var openDashboard: (() -> Void)?
    var pointerPressed = false
    var fetchOnExpand = true
    var landing = false
    var dragMoved: ((NSPoint) -> Void)?
    var dragEnded: ((NSPoint) -> Void)?
    var resize: (() -> Void)?; var changed: (() -> Void)?
    private var generation = 0
    private var timer: Timer?
    private var hoverTask: Task<Void, Never>?
    var ringProgress: Double {
        guard let value = current.dayEstimatedUSD, dailyLimit > 0 else { return 0 }
        return min(1, max(0, value / dailyLimit))
    }

    func hover(_ inside: Bool) {
        hoverTask?.cancel()
        guard !pointerPressed && !landing && !dragging && !bubble else { return }
        hoverTask = Task {
            do { try await Task.sleep(nanoseconds: inside ? 400_000_000 : 220_000_000) } catch { return }
            guard !pointerPressed && !landing && !dragging && !bubble && expanded != inside else { return }
            setExpanded(inside)
        }
    }
    var isToday: Bool { Dates.key(selected) == Dates.key(Date()) }
    func start() { refresh(); timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } } }
    func toggle() { setExpanded(!expanded) }
    func setExpanded(_ value: Bool) {
        guard !landing else { return }
        expanded = value
        liquidRadius = value ? 20 : 10
        contentMounted = false
        if value && fetchOnExpand { pace.refresh() }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduced ? .linear(duration: 0.1) : .spring(response: value ? 0.30 : 0.18, dampingFraction: 0.85).delay(value ? 0.06 : 0)) { reveal = value ? 1 : 0 }
        resize?()
    }
    func select(_ d: Date) { selected = min(Dates.calendar.startOfDay(for: d), Dates.calendar.startOfDay(for: Date())); loadHistory() }
    func shift(_ n: Int) { select(Dates.shift(n, selected)) }
    func refresh() {
        guard !busy else { return }; busy = true
        Task { current = Self.merge(current, await Self.read(Dates.key(Date()), 1)); busy = false; pace.push(); dashboardBridge?.push(); changed?() }
        if expanded { pace.refresh() }; if dashboardBridge?.web.window?.isVisible == true { dashboardBridge?.refresh() }
    }
    private func loadHistory() {
        generation += 1; let version = generation; let end = Dates.key(selected); loading = true
        if history.rangeEnd != end { history = Snapshot(state: "loading", message: "Loading selected day…") }
        Task { try? await Task.sleep(nanoseconds: 250_000_000); guard version == generation else { return }; let result = await Self.read(end, 30); guard version == generation else { return }; history = Self.merge(history, result); loading = false; changed?() }
    }
    static func merge(_ old: Snapshot, _ new: Snapshot) -> Snapshot {
        guard new.state != "ok", old.credits != nil else { return new }
        var result = old; result.state = new.state; result.message = new.message; result.fetchedAt = new.fetchedAt; return result
    }
    nonisolated static func read(_ end: String, _ days: Int) async -> Snapshot {
        await UsageCache.shared.get(end, days)
    }
    nonisolated static func readUncached(_ end: String, _ days: Int) async -> Snapshot {
        let script = Bundle.main.resourceURL!.appendingPathComponent("collector.py").path
        return await Task.detached {
            let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/python3"); task.arguments = [script, "--end", end, "--days", String(days)]
            let pipe = Pipe(); task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                let timeout = DispatchWorkItem { if task.isRunning { task.terminate() } }; DispatchQueue.global().asyncAfter(deadline: .now() + 210, execute: timeout)
                let data = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit(); timeout.cancel()
                if task.terminationStatus == 0 { return try JSONDecoder().decode(Snapshot.self, from: data) }
            } catch { }
            return Snapshot(state: "error", message: "Refresh failed. Check your connection and try again.")
        }.value
    }
}
actor UsageCache {
    static let shared = UsageCache()
    var values: [String: (Date, Snapshot)] = [:]
    var requests: [String: Task<Snapshot, Never>] = [:]
    func get(_ end: String, _ days: Int) async -> Snapshot {
        let key = end + "/" + String(days)
        if let cached = values[key], Date().timeIntervalSince(cached.0) < 55 { return cached.1 }
        if let existing = requests[key] { return await existing.value }
        let task = Task { await Store.readUncached(end, days) }; requests[key] = task
        let result = await task.value; requests[key] = nil
        if result.state == "ok" {
            if values.count >= 24, let oldest = values.min(by: { $0.value.0 < $1.value.0 })?.key { values[oldest] = nil }
            values[key] = (Date(), result)
        }
        return result
    }
}
let mint = Color(red: 0.71, green: 0.65, blue: 0.93)
func number(_ n: Double?) -> String { n?.formatted(.number.notation(.compactName).precision(.fractionLength(0...1))) ?? "—" }
func dollars(_ n: Double?) -> String { n?.formatted(.currency(code: "USD")) ?? "—" }
func time(_ s: String?) -> String {
    guard let s else { return "Unavailable" }; let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var d = f.date(from: s); if d == nil { f.formatOptions = [.withInternetDateTime]; d = f.date(from: s) }
    guard let d else { return s }; let out = DateFormatter(); out.timeZone = TimeZone(identifier: "America/Chicago"); out.dateFormat = "MMM d, h:mm a z"; return out.string(from: d)
}
struct Island: View {
    @ObservedObject var store: Store
    var smallVertical: Bool { store.bubble || store.edge == .left || store.edge == .right }
    func radii(_ size: CGSize) -> UnevenRoundedRectangle {
        let floating = store.bubble || store.landing
        let roundness = floating ? min(size.width, size.height) / 2 : min(22, min(size.width, size.height) / 2)
        let attach: CGFloat = store.landing ? max(0, min(1, (max(size.width, size.height) - 44) / ((store.edge == .left || store.edge == .right) ? 20 : 116))) : store.bubble ? 0 : 1
        return UnevenRoundedRectangle(topLeadingRadius: roundness * ((store.edge == .top || store.edge == .left) ? 1-attach : 1), bottomLeadingRadius: roundness * ((store.edge == .bottom || store.edge == .left) ? 1-attach : 1), bottomTrailingRadius: roundness * ((store.edge == .bottom || store.edge == .right) ? 1-attach : 1), topTrailingRadius: roundness * ((store.edge == .top || store.edge == .right) ? 1-attach : 1))
    }
    var body: some View {
        let _ = Perf.rootBuilds += 1
        GeometryReader { area in
            ZStack(alignment: .top) {
                Color.black
                if store.contentMounted {
                    PaceWeb(bridge: store.pace).frame(width: 420, height: 460)
                        .transition(.opacity.animation(.easeOut(duration: 0.10)))
                        .padding(.top, store.notchInset)
                    Capsule().fill(.white.opacity(0.22)).frame(width: 26, height: 3).padding(.top, store.notchInset + 3)
                } else {
                    HStack(spacing: 9) {
                        ZStack {
                            if store.dailyLimit > 0 {
                                Circle().stroke(.white.opacity(0.2), lineWidth: 2.5)
                                Circle().trim(from: 0, to: store.ringProgress).stroke(store.current.state == "ok" ? mint : .orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
                            } else {
                                Circle().fill(store.current.state == "ok" ? mint : .orange)
                                Circle().fill(.white.opacity(0.3)).frame(width: 5, height: 5).offset(x: -3, y: -3)
                            }
                        }.frame(width: store.bubble ? 20 : 16, height: store.bubble ? 20 : 16)
                        if !smallVertical { Text(dollars(store.current.dayEstimatedUSD)).font(.system(size: 13, weight: .medium)).monospacedDigit() }
                    }.frame(width: area.size.width, height: store.bubble ? area.size.height : smallVertical ? 64 : 32)
                        .padding(.top, store.bubble ? 0 : store.notchInset)
                }
            }
            .frame(width: area.size.width, height: area.size.height, alignment: .top)
            .clipShape(radii(area.size))
            .contentShape(Rectangle())
        }
        .onHover { store.hover($0) }.preferredColorScheme(.dark)
        .help(store.dailyLimit > 0 ? "Personal daily budget usage. Drag to move." : "Usage connected. Set a daily budget in the dashboard to enable the progress ring. Drag to move.")
    }
}
final class IslandPanel: NSPanel {
    weak var interactionStore: Store?
    private var captured = false
    private var moved = false
    private var origin = NSPoint.zero
    static func draggable(_ point: NSPoint, expanded: Bool, mounted: Bool, notch: CGFloat) -> Bool {
        // Header controls remain clickable. Brand and the full top strip are grab zones.
        !expanded || !mounted || point.y < notch + 16 || (point.y < notch + 64 && point.x < 104)
    }
    override func sendEvent(_ event: NSEvent) {
        guard let store = interactionStore else { super.sendEvent(event); return }
        switch event.type {
        case .leftMouseDown:
            let p = NSPoint(x: event.locationInWindow.x, y: frame.height-event.locationInWindow.y)
            if Self.draggable(p, expanded: store.expanded, mounted: store.contentMounted, notch: store.notchInset) {
                captured = true; moved = false; origin = NSEvent.mouseLocation
                store.pointerPressed = true; store.hover(false)
                return
            }
        case .leftMouseDragged where captured:
            let p = NSEvent.mouseLocation
            if moved || hypot(p.x-origin.x, p.y-origin.y) >= 3 {
                moved = true; store.dragMoved?(p)
            }
            return
        case .leftMouseUp where captured:
            captured = false
            if moved { store.dragEnded?(NSEvent.mouseLocation) }
            store.pointerPressed = false
            if !moved && !store.expanded { store.toggle() }
            moved = false
            return
        default: break
        }
        super.sendEvent(event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
func islandFrame(visible: NSRect, old: NSRect, expanded: Bool, initial: Bool) -> NSRect {
    let w = min(expanded ? 360.0 : 112.0, visible.width - 24)
    let h = min(expanded ? 382.0 : 24.0, visible.height - 12)
    return NSRect(x: visible.midX - w / 2, y: visible.maxY - h, width: w, height: h)
}
@MainActor final class Delegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var panel: IslandPanel!; var item: NSStatusItem!; let store = Store(); var resizing = false
    var motionTimer: Timer?
    var motionTarget = NSRect.zero
    var widthSpring = LiquidSpring(position: 112)
    var heightSpring = LiquidSpring(position: 24)
    var lastFrameTime = 0.0
    var motionStarted = 0.0
    var morphWidth = LiquidSpring(position: 160)
    var morphHeight = LiquidSpring(position: 32)
    var morphTargetSize = NSSize.zero
    var fraction = 0.5
    var activeScreen: NSScreen?
    var centerXSpring = LiquidSpring(position: 0)
    var centerYSpring = LiquidSpring(position: 0)
    var dashboardWindow: NSWindow?
    var dropping = false
    var landingStart = 0.0
    var landingFrom = NSRect.zero
    var lastLandingMS = 0.0
    func applicationDidFinishLaunching(_ notification: Notification) {
        for old in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!) where old.processIdentifier != ProcessInfo.processInfo.processIdentifier { old.terminate() }
        NSApplication.shared.setActivationPolicy(.accessory)
        panel = IslandPanel(contentRect: NSRect(x: 0, y: 0, width: 310, height: 52), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.interactionStore = store
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1); panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.isMovableByWindowBackground = false; panel.delegate = self
        panel.contentView = NSHostingView(rootView: Island(store: store))
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength); item.button?.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Show usage island"); item.button?.target = self; item.button?.action = #selector(show)
        store.resize = { [weak self] in self?.resize() }; store.changed = { [weak self] in self?.receipt() }
        store.edge = DockEdge(rawValue: UserDefaults.standard.string(forKey: "dockEdge") ?? "top") ?? .top
        if UserDefaults.standard.object(forKey: "dockFraction") != nil { fraction = UserDefaults.standard.double(forKey: "dockFraction") }
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Pace", action: #selector(show), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Refresh", action: #selector(refreshUsage), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Pace", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        store.openDashboard = { [weak self] in self?.openDashboard() }
        activeScreen = NSScreen.main
        store.dragMoved = { [weak self] point in self?.drag(point) }
        store.dragEnded = { [weak self] point in self?.drop(point) }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.resize() } }
        resize(initial: true); panel.orderFrontRegardless(); store.start()
        if CommandLine.arguments.contains("--show") { store.toggle() }
        if CommandLine.arguments.contains("--dashboard") { openDashboard() }
    }
    @objc func refreshUsage() { store.refresh(); store.pace.refresh(); store.dashboardBridge?.refresh() }
    @objc func quit() { NSApplication.shared.terminate(nil) }
    @objc func openDashboard() {
        if dashboardWindow == nil {
            let bridge = PaceBridge(store: store, dashboard: true); store.dashboardBridge = bridge
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Pace · Usage dashboard"
            window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
            window.backgroundColor = .black
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(button)?.isHidden = true }
            window.contentView = dashboardContent(web: bridge.web)
            window.minSize = NSSize(width: 780, height: 650); window.isReleasedWhenClosed = false
            window.center(); dashboardWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); dashboardWindow?.makeKeyAndOrderFront(nil)
        store.dashboardBridge?.refresh()
    }
    @objc func show() { panel.orderFrontRegardless(); if !store.expanded { store.toggle() } }
    func drag(_ point: NSPoint) {
        if !store.dragging {
            store.dragging = true; store.hover(false); store.expanded = false; store.contentMounted = false; store.reveal = 0; dropping = false; store.landing = false
        }
        activeScreen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? activeScreen ?? panel.screen
        let screen = activeScreen ?? NSScreen.main!
        let edge = DockEdge.nearest(point, in: screen.frame)
        let detached = edge.distance(point, in: screen.frame) > 34
        let shapeChanged = store.bubble != detached || store.edge != edge
        if store.bubble != detached { store.bubble = detached }
        if store.edge != edge { store.edge = edge }
        fraction = edge.fraction(point, in: screen.frame)
        if store.notchInset != 0 { store.notchInset = 0 }
        if detached {
            motionTarget = NSRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
            // Pointer motion is direct; only shape changes and release use springs.
            let size = shapeChanged || motionTimer != nil ? panel.frame.size : NSSize(width: 44, height: 44)
            panel.setFrame(NSRect(x: point.x-size.width/2, y: point.y-size.height/2, width: size.width, height: size.height), display: false)
            if shapeChanged { motionStarted = ProcessInfo.processInfo.systemUptime; startMotion() }
        } else { resize() }
    }
    func drop(_ point: NSPoint) {
        guard store.dragging else { return }
        let screen = activeScreen ?? panel.screen ?? NSScreen.main!
        store.edge = DockEdge.nearest(point, in: screen.frame)
        fraction = store.edge.fraction(point, in: screen.frame)
        store.dragging = false
        UserDefaults.standard.set(store.edge.rawValue, forKey: "dockEdge")
        UserDefaults.standard.set(fraction, forKey: "dockFraction")
        if store.bubble {
            motionTimer?.invalidate(); motionTimer = nil
            dropping = true; store.landing = true
            landingFrom = panel.frame
            landingStart = ProcessInfo.processInfo.systemUptime
            let notch = store.edge == .top && abs(fraction - 0.5) * screen.frame.width < 180 ? screen.safeAreaInsets.top : 0
            let vertical = store.edge == .left || store.edge == .right
            motionTarget = dockFrame(screen: screen.frame, edge: store.edge, fraction: fraction,
                size: NSSize(width: vertical ? 28 : 160, height: (vertical ? 64 : 32) + notch))
            startMotion()
        } else { resize() }
    }
    func startMotion() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(motionTarget, display: true)
            if dropping { dropping = false; store.landing = false; store.bubble = false; resize(initial: true) }
            receipt(); return
        }
        if !dropping && morphTargetSize != motionTarget.size {
            morphWidth = LiquidSpring(position: panel.frame.width, velocity: widthSpring.velocity)
            morphHeight = LiquidSpring(position: panel.frame.height, velocity: heightSpring.velocity)
            morphTargetSize = motionTarget.size
            motionStarted = ProcessInfo.processInfo.systemUptime
        }
        guard motionTimer == nil else { return }
        Perf.reset()
        widthSpring.position = panel.frame.width; heightSpring.position = panel.frame.height
        centerXSpring.position = panel.frame.midX; centerYSpring.position = panel.frame.midY
        lastFrameTime = ProcessInfo.processInfo.systemUptime
        motionStarted = lastFrameTime
        morphWidth = LiquidSpring(position: panel.frame.width, velocity: widthSpring.velocity)
        morphHeight = LiquidSpring(position: panel.frame.height, velocity: heightSpring.velocity)
        morphTargetSize = motionTarget.size
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.stepMotion() } }
        motionTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func resize(initial: Bool = false) {
        guard !resizing else { return }; resizing = true; defer { resizing = false }
        let screen = activeScreen.flatMap { old in NSScreen.screens.first(where: { $0 == old }) } ?? panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
        activeScreen = screen
        let notch = store.edge == .top && abs(fraction - 0.5) * screen.frame.width < 180 ? screen.safeAreaInsets.top : 0
        if store.notchInset != notch { store.notchInset = notch }
        let vertical = store.edge == .left || store.edge == .right
        let size = NSSize(width: store.expanded ? 420 : vertical ? 28 : 160, height: (store.expanded ? 460 : vertical ? 64 : 32) + store.notchInset)
        let frame = dockFrame(screen: screen.frame, edge: store.edge, fraction: fraction, size: size)
        motionTarget = frame
        if store.dragging && abs(panel.frame.width-frame.width) < 0.5 && abs(panel.frame.height-frame.height) < 0.5 {
            panel.setFrame(frame, display: false); return
        }
        if initial || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            motionTimer?.invalidate(); motionTimer = nil
            widthSpring = LiquidSpring(position: frame.width); heightSpring = LiquidSpring(position: frame.height)
            centerXSpring = LiquidSpring(position: frame.midX); centerYSpring = LiquidSpring(position: frame.midY)
            panel.setFrame(frame, display: true)
            store.liquidRadius = store.expanded ? 20 : 10
            store.contentMounted = store.expanded
            receipt(); return
        }
        startMotion()
    }
    func stepMotion() {
        let began = ProcessInfo.processInfo.systemUptime
        defer { Perf.frameCount += 1; Perf.frameMS += (ProcessInfo.processInfo.systemUptime - began) * 1000 }
        let now = ProcessInfo.processInfo.systemUptime
        Perf.maxGapMS = max(Perf.maxGapMS, (now - lastFrameTime) * 1000)
        let dt = min(1.0 / 20, max(1.0 / 240, now - lastFrameTime)); lastFrameTime = now
        if dropping {
            let elapsed = now - landingStart
            let screen = activeScreen ?? panel.screen ?? NSScreen.main!
            // Arrival and spreading overlap; completion never waits for a spring tail.
            resizing = true
            panel.setFrame(splatFrame(from: landingFrom, to: motionTarget, screen: screen.frame, edge: store.edge, elapsed: elapsed), display: false)
            resizing = false
            if elapsed >= splatDuration {
                motionTimer?.invalidate(); motionTimer = nil
                dropping = false; store.landing = false; store.bubble = false
                store.notchInset = store.edge == .top ? max(0, motionTarget.height - 32) : 0
                lastLandingMS = elapsed * 1000
                receipt()
            }
            return
        }
        // Finite C1-continuous morph: reaches its destination with zero velocity,
        // rather than cutting off a moving spring at a deadline.
        let elapsed = now - motionStarted
        widthSpring = finiteMorph(from: morphWidth, to: motionTarget.width, elapsed: elapsed, duration: store.dragging ? 0.20 : 0.32)
        heightSpring = finiteMorph(from: morphHeight, to: motionTarget.height, elapsed: elapsed, duration: store.dragging ? 0.20 : 0.32)
        let screen = activeScreen ?? panel.screen ?? NSScreen.main!
        let w = min(screen.frame.width - 12, max(19, widthSpring.position))
        let h = min(screen.frame.height - 12, max(19, heightSpring.position))
        if store.dragging {
            centerXSpring = LiquidSpring(position: motionTarget.midX)
            centerYSpring = LiquidSpring(position: motionTarget.midY)
        } else {
            centerXSpring.step(target: motionTarget.midX, dt: dt, stiffness: 340, damping: 0.8)
            centerYSpring.step(target: motionTarget.midY, dt: dt, stiffness: 340, damping: 0.8)
        }
        // Keep per-frame geometry out of ObservableObject: it invalidates the full SwiftUI tree.
        resizing = true
        let animated: NSRect
        if store.bubble {
            animated = NSRect(x: centerXSpring.position - w / 2, y: centerYSpring.position - h / 2, width: w, height: h)
        } else {
            animated = dockFrame(screen: screen.frame, edge: store.edge, fraction: fraction, size: NSSize(width: w, height: h))
        }
        panel.setFrame(animated, display: false)
        resizing = false
        if widthSpring.settled(at: motionTarget.width) && heightSpring.settled(at: motionTarget.height) && (!store.bubble || (centerXSpring.settled(at: motionTarget.midX) && centerYSpring.settled(at: motionTarget.midY))) {
            motionTimer?.invalidate(); motionTimer = nil
            resizing = true; panel.setFrame(motionTarget, display: true); resizing = false
            store.liquidRadius = store.expanded ? 20 : 10
            store.contentMounted = store.expanded
            receipt()
        }
    }
    func windowDidMove(_ notification: Notification) { }
    func receipt() {
        guard panel != nil else { return }; let frame = panel.frame; let visible = (panel.screen ?? NSScreen.main)!.frame
        let data: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier, "inScreen": visible.contains(frame), "edge": store.edge.rawValue, "bubble": store.bubble, "dragging": store.dragging, "fraction": fraction, "expanded": store.expanded, "state": store.current.state, "historyState": store.history.state, "width": frame.width, "height": frame.height]
        var output = data
        output["paceState"] = store.pace.snapshot.state
        output["paceReady"] = store.pace.ready
        output["paceTokensAvailable"] = store.pace.snapshot.tokensAvailable ?? false
        output["lastLandingMS"] = lastLandingMS
        output["motionFrames"] = Perf.frameCount; output["rootBuilds"] = Perf.rootBuilds; output["detailBuilds"] = Perf.detailBuilds
        output["averageFrameWorkMS"] = Perf.frameMS / Double(max(1, Perf.frameCount)); output["maxFrameGapMS"] = Perf.maxGapMS
        if ProcessInfo.processInfo.arguments.contains("--diagnostics"), let raw = try? JSONSerialization.data(withJSONObject: output) { try? raw.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("island-health.json"), options: .atomic) }
    }
}
@MainActor enum Perf {
    static var rootBuilds = 0; static var detailBuilds = 0; static var frameCount = 0
    static var frameMS = 0.0; static var maxGapMS = 0.0
    static func reset() { rootBuilds = 0; detailBuilds = 0; frameCount = 0; frameMS = 0; maxGapMS = 0 }
}
enum DockEdge: String, CaseIterable {
    case top, bottom, left, right
    func distance(_ p: NSPoint, in r: NSRect) -> Double {
        switch self { case .top: return abs(r.maxY-p.y); case .bottom: return abs(p.y-r.minY); case .left: return abs(p.x-r.minX); case .right: return abs(r.maxX-p.x) }
    }
    static func nearest(_ p: NSPoint, in r: NSRect) -> DockEdge { allCases.min { $0.distance(p, in: r) < $1.distance(p, in: r) }! }
    func fraction(_ p: NSPoint, in r: NSRect) -> Double {
        min(1, max(0, self == .top || self == .bottom ? (p.x-r.minX)/r.width : (p.y-r.minY)/r.height))
    }
}
func dockFrame(screen r: NSRect, edge: DockEdge, fraction: Double, size: NSSize) -> NSRect {
    let w = min(size.width, r.width - 12); let h = min(size.height, r.height - 12)
    let f = min(1, max(0, fraction))
    let x = max(r.minX, min(r.minX+r.width*f-w/2, r.maxX-w))
    let y = max(r.minY, min(r.minY+r.height*f-h/2, r.maxY-h))
    switch edge {
    case .top: return NSRect(x: x, y: r.maxY-h, width: w, height: h)
    case .bottom: return NSRect(x: x, y: r.minY, width: w, height: h)
    case .left: return NSRect(x: r.minX, y: y, width: w, height: h)
    case .right: return NSRect(x: r.maxX-w, y: y, width: w, height: h)
    }
}
// One bounded landing: approach in 140 ms, overlapping spread, done at 240 ms.
let splatDuration = 0.24
func splatFrame(from: NSRect, to: NSRect, screen: NSRect, edge: DockEdge, elapsed: Double) -> NSRect {
    if elapsed <= 0 { return from }
    if elapsed >= splatDuration { return to }
    let travel = min(1, elapsed / 0.14)
    let approach = 1 - pow(1 - travel, 3)
    let spread = min(1, max(0, (elapsed - 0.07) / 0.17))
    let ease = 1 - pow(1 - spread, 3)
    let impact = sin(Double.pi * spread) * (1 - spread)
    let vertical = edge == .left || edge == .right
    let w = from.width + (to.width - from.width) * ease + (vertical ? -5 : 20) * impact
    let h = from.height + (to.height - from.height) * ease + (vertical ? 12 : -5) * impact
    // Position follows the size-aware edge contact, so the splat stays attached.
    let contactX = edge == .left ? screen.minX + w/2 : edge == .right ? screen.maxX - w/2 : to.midX
    let contactY = edge == .bottom ? screen.minY + h/2 : edge == .top ? screen.maxY - h/2 : to.midY
    let x = from.midX + (contactX - from.midX) * approach - w/2
    let y = from.midY + (contactY - from.midY) * approach - h/2
    return NSRect(x: max(screen.minX, min(x, screen.maxX-w)),
                  y: max(screen.minY, min(y, screen.maxY-h)), width: w, height: h)
}
func finiteMorph(from start: LiquidSpring, to target: Double, elapsed: Double, duration: Double) -> LiquidSpring {
    let t = min(1, max(0, elapsed / duration))
    if t >= 1 { return LiquidSpring(position: target) }
    let delta = target - start.position
    // Quintic endpoint easing with a bounded initial-velocity term for reversal.
    let ease = t*t*t*(10 + t*(-15 + 6*t))
    let derivative = 30*t*t*(1-t)*(1-t)
    let initial = min(600, max(-600, start.velocity)) * duration
    let carry = t * pow(1-t, 3)
    let carryDerivative = pow(1-t, 2) * (1-4*t)
    return LiquidSpring(position: start.position + delta*ease + initial*carry,
                        velocity: (delta*derivative + initial*carryDerivative)/duration)
}
struct LiquidSpring {
    var position: Double
    var velocity = 0.0
    mutating func step(target: Double, dt: Double, stiffness: Double, damping: Double) {
        let step = dt / 4
        for _ in 0..<4 {
            velocity += (stiffness * (target - position) - 2 * damping * sqrt(stiffness) * velocity) * step
            position += velocity * step
        }
    }
    func settled(at target: Double) -> Bool { abs(position - target) < 0.35 && abs(velocity) < 3 }
}
@main struct Main {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--hover-self-test") {
            Task { @MainActor in
                let store = Store(); store.fetchOnExpand = false
                store.hover(true)
                try? await Task.sleep(nanoseconds: 550_000_000)
                precondition(store.expanded)
                store.hover(false); store.hover(true)
                try? await Task.sleep(nanoseconds: 450_000_000)
                precondition(store.expanded)
                store.hover(false)
                try? await Task.sleep(nanoseconds: 450_000_000)
                precondition(!store.expanded)
                print("Passed: hover expansion, exit cancellation, delayed collapse")
                exit(0)
            }
            RunLoop.main.run()
            return
        }
        if CommandLine.arguments.contains("--self-test") {
            for screen in [NSRect(x: 0, y: 0, width: 1440, height: 900), NSRect(x: -1000, y: 200, width: 1000, height: 700)] {
                for edge in DockEdge.allCases {
                    for fraction in [0.0, 0.1, 0.5, 0.9, 1.0] {
                        for size in [NSSize(width: 112, height: 24), NSSize(width: 24, height: 64), NSSize(width: 44, height: 44), NSSize(width: 360, height: 382)] {
                            let frame = dockFrame(screen: screen, edge: edge, fraction: fraction, size: size)
                            precondition(screen.contains(frame))
                            switch edge {
                            case .top: precondition(frame.maxY == screen.maxY)
                            case .bottom: precondition(frame.minY == screen.minY)
                            case .left: precondition(frame.minX == screen.minX)
                            case .right: precondition(frame.maxX == screen.maxX)
                            }
                        }
                    }
                }
                precondition(DockEdge.nearest(NSPoint(x: screen.midX, y: screen.maxY-80), in: screen) == .top)
                precondition(DockEdge.nearest(NSPoint(x: screen.midX, y: screen.minY+80), in: screen) == .bottom)
                precondition(DockEdge.nearest(NSPoint(x: screen.minX+80, y: screen.midY), in: screen) == .left)
                precondition(DockEdge.nearest(NSPoint(x: screen.maxX-80, y: screen.midY), in: screen) == .right)
            }
            let landingScreen = NSRect(x: -1000, y: 200, width: 1000, height: 700)
            let source = NSRect(x: -522, y: 528, width: 44, height: 44)
            for edge in DockEdge.allCases {
                for fraction in [0.0, 0.5, 1.0] {
                    let vertical = edge == .left || edge == .right
                    let target = dockFrame(screen: landingScreen, edge: edge, fraction: fraction, size: NSSize(width: vertical ? 24 : 112, height: vertical ? 64 : 24))
                    precondition(splatFrame(from: source, to: target, screen: landingScreen, edge: edge, elapsed: 0) == source)
                    for tick in 1...24 {
                        let frame = splatFrame(from: source, to: target, screen: landingScreen, edge: edge, elapsed: Double(tick)/100)
                        precondition(landingScreen.contains(frame))
                    }
                    precondition(splatFrame(from: source, to: target, screen: landingScreen, edge: edge, elapsed: 0.24) == target)
                    precondition(splatFrame(from: source, to: target, screen: landingScreen, edge: edge, elapsed: 2) == target)
                }
            }
            print("Passed: bounded 240 ms splat on all edges, corners, and delayed frames")
            for target in [44.0, 160.0, 420.0] {
                let start = LiquidSpring(position: 112, velocity: 80)
                let first = finiteMorph(from: start, to: target, elapsed: 0, duration: 0.32)
                let last = finiteMorph(from: start, to: target, elapsed: 0.32, duration: 0.32)
                let nearEnd = finiteMorph(from: start, to: target, elapsed: 0.3199, duration: 0.32)
                precondition(first.position == 112 && abs(first.velocity - 80) < 0.001)
                precondition(last.position == target && last.velocity == 0)
                precondition(abs(nearEnd.position - target) < 0.001 && abs(nearEnd.velocity) < 0.1)
            }
            print("Passed: morph position and velocity continuity, smooth endpoint settlement")
            precondition(IslandPanel.draggable(NSPoint(x: 150, y: 28), expanded: false, mounted: false, notch: 0))
            precondition(IslandPanel.draggable(NSPoint(x: 60, y: 45), expanded: true, mounted: true, notch: 0))
            precondition(IslandPanel.draggable(NSPoint(x: 390, y: 10), expanded: true, mounted: true, notch: 0))
            precondition(!IslandPanel.draggable(NSPoint(x: 145, y: 35), expanded: true, mounted: true, notch: 0))
            precondition(!IslandPanel.draggable(NSPoint(x: 280, y: 35), expanded: true, mounted: true, notch: 0))
            precondition(!IslandPanel.draggable(NSPoint(x: 60, y: 190), expanded: true, mounted: true, notch: 0))
            print("Passed: whole-tab capture, expanded header grab zones, controls excluded")
            var spring = LiquidSpring(position: 112)
            var peak = 0.0
            for _ in 0..<240 { spring.step(target: 360, dt: 1.0/120, stiffness: 260, damping: 0.68); peak = max(peak, spring.position) }
            precondition(spring.settled(at: 360)); precondition(peak > 360 && peak < 385)
            for _ in 0..<15 { spring.step(target: 112, dt: 1.0/120, stiffness: 170, damping: 0.68) }
            let previousPosition = spring.position
            spring.step(target: 360, dt: 1.0/120, stiffness: 260, damping: 0.68)
            precondition(abs(spring.position - previousPosition) < 30)
            for _ in 0..<300 { spring.step(target: 112, dt: 1.0/120, stiffness: 170, damping: 0.68) }
            precondition(spring.settled(at: 112))
            for screen in [NSRect(x: 0, y: 0, width: 1280, height: 700), NSRect(x: -800, y: 200, width: 800, height: 400), NSRect(x: 0, y: 0, width: 360, height: 300)] {
                for expanded in [false, true] {
                    for old in [NSRect(x: -2000, y: 2000, width: 310, height: 52), NSRect(x: 3000, y: -1000, width: 460, height: 640)] {
                        let frame = islandFrame(visible: screen, old: old, expanded: expanded, initial: false)
                        precondition(screen.contains(frame)); precondition(frame.maxY == screen.maxY)
                    }
                }
            }
            let old = Snapshot(state: "ok", message: "", credits: 10)
            let compact = islandFrame(visible: NSRect(x: 0, y: 0, width: 1280, height: 800), old: .zero, expanded: false, initial: true)
            precondition(compact.width == 112 && compact.height == 24)
            let failed = Store.merge(old, Snapshot(state: "error", message: "Offline"))
            precondition(failed.credits == 10 && failed.state == "error")
            let date = ISO8601DateFormatter().date(from: "2026-03-08T00:00:00Z")!
            precondition(Dates.key(Dates.shift(-1, date)) == "2026-03-07")
            print("Passed: 160 docking cases, all nearest edges, springs, screen bounds, stale data, UTC dates")
            return
        }
        let app = NSApplication.shared; let delegate = Delegate(); app.delegate = delegate; withExtendedLifetime(delegate) { app.run() }
    }
}
