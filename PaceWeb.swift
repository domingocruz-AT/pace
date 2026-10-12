import AppKit
import WebKit
import SwiftUI

@MainActor final class PaceTitleBar: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override init(frame: NSRect) {
        super.init(frame: frame)
        let title = NSTextField(labelWithString: "Pace")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = .white
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)
        let subtitle = NSTextField(labelWithString: "Usage dashboard")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.45)
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitle)
        let controls = NSStackView()
        controls.orientation = .horizontal; controls.spacing = 6; controls.alignment = .centerY
        controls.translatesAutoresizingMaskIntoConstraints = false
        for (symbol, name, action) in [("minus", "Minimize dashboard", #selector(minimizeWindow)), ("arrow.up.left.and.arrow.down.right", "Zoom dashboard", #selector(zoomWindow)), ("xmark", "Close dashboard", #selector(closeWindow))] {
            let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: name)!, target: self, action: action)
            button.isBordered = false; button.imagePosition = .imageOnly
            button.bezelStyle = .regularSquare
            button.imageScaling = .scaleProportionallyDown
            let icon = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
                guard let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)) else { return false }
                let size = symbolImage.size
                let scale = min(12 / size.width, 12 / size.height)
                let fitted = NSSize(width: size.width * scale, height: size.height * scale)
                symbolImage.draw(in: NSRect(x: (rect.width-fitted.width)/2, y: (rect.height-fitted.height)/2, width: fitted.width, height: fitted.height))
                return true
            }
            icon.isTemplate = true; button.image = icon
            button.setContentHuggingPriority(.required, for: .vertical)
            button.setContentCompressionResistancePriority(.required, for: .vertical)
            button.contentTintColor = NSColor.white.withAlphaComponent(0.65)
            button.toolTip = name; button.setAccessibilityLabel(name)
            button.wantsLayer = true; button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
            button.layer?.cornerRadius = 7
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            controls.addArrangedSubview(button)
        }
        addSubview(controls)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20), title.centerYAnchor.constraint(equalTo: centerYAnchor),
            subtitle.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 12), subtitle.centerYAnchor.constraint(equalTo: centerYAnchor),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), controls.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        NSColor.white.withAlphaComponent(0.09).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.zoom(nil) } else { window?.performDrag(with: event) }
    }
    @objc private func closeWindow() { window?.performClose(nil) }
    @objc private func minimizeWindow() { window?.miniaturize(nil) }
    @objc private func zoomWindow() { window?.zoom(nil) }
}

@MainActor func dashboardContent(web: WKWebView) -> NSView {
    let root = NSView(); root.wantsLayer = true; root.layer?.backgroundColor = NSColor.black.cgColor
    let titleBar = PaceTitleBar(frame: .zero)
    titleBar.translatesAutoresizingMaskIntoConstraints = false
    web.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(web); root.addSubview(titleBar)
    NSLayoutConstraint.activate([
        titleBar.topAnchor.constraint(equalTo: root.topAnchor), titleBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
        titleBar.trailingAnchor.constraint(equalTo: root.trailingAnchor), titleBar.heightAnchor.constraint(equalToConstant: 44),
        web.topAnchor.constraint(equalTo: titleBar.bottomAnchor), web.leadingAnchor.constraint(equalTo: root.leadingAnchor),
        web.trailingAnchor.constraint(equalTo: root.trailingAnchor), web.bottomAnchor.constraint(equalTo: root.bottomAnchor)
    ])
    return root
}

@MainActor final class PaceBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var store: Store?
    let web: WKWebView
    var snapshot = Snapshot(state: "loading", message: "Connecting…")
    var loading = false
    var ready = false
    var version = 0
    var end = ""
    var days = 1
    var checked = Date.distantPast
    var inFlight = ""
    var dashboard: Bool
    var lastPayload = Data()
    init(store: Store, dashboard: Bool = false) {
        self.store = store; self.dashboard = dashboard
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.add(self, name: "pace")
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        let htmlURL = Bundle.main.resourceURL!.appendingPathComponent("pace.html")
        let jsURL = Bundle.main.resourceURL!.appendingPathComponent("pace.js")
        if let html = try? String(contentsOf: htmlURL, encoding: .utf8), let js = try? String(contentsOf: jsURL, encoding: .utf8) {
            let page = html.replacingOccurrences(of: "script-src 'self'", with: "script-src 'nonce-pace-local'")
                .replacingOccurrences(of: "<script src=\"pace.js\"></script>", with: "<script nonce=\"pace-local\">window.paceDashboard = \(dashboard ? "true" : "false");\n" + js + "</script>")
            web.loadHTMLString(page, baseURL: nil)
        }

    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.webView === web,
              let body = message.body as? [String: Any], let action = body["action"] as? String, let store else { return }
        switch action {
        case "ready": ready = true; push()
        case "range":
            guard let end = body["end"] as? String, let days = body["days"] as? Int,
                  (1...90).contains(days), let date = Self.date(end), date <= Dates.calendar.startOfDay(for: Date()) else { return }
            request(end: end, days: days, force: body["force"] as? Bool ?? false)
        case "budget":
            guard let daily = body["dailyLimit"] as? Double, let monthly = body["monthlyLimit"] as? Double,
                  daily.isFinite, monthly.isFinite, (0...1_000_000).contains(daily), (0...1_000_000).contains(monthly) else { return }
            store.dailyLimit = daily; store.monthlyLimit = monthly
            UserDefaults.standard.set(daily, forKey: "paceDailyLimit")
            UserDefaults.standard.set(monthly, forKey: "paceMonthlyLimit")
            store.pace.push(); store.dashboardBridge?.push()
        case "dashboard": store.openDashboard?()
        default: break
        }
    }
    static func date(_ text: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = Dates.calendar.timeZone; f.isLenient = false
        guard let date = f.date(from: text), Dates.key(date) == text else { return nil }; return date
    }
    func request(end: String, days: Int, force: Bool = false) {
        let query = end + "/" + String(days)
        if inFlight == query { return }
        if self.end == end && self.days == days && Date().timeIntervalSince(checked) < 55 && !force { push(); return }
        version += 1; let own = version; self.end = end; self.days = days
        let start = Dates.key(Dates.shift(1-days, Self.date(end)!))
        if snapshot.rangeEnd != end || snapshot.rangeStart != start {
            snapshot = Snapshot(state: "loading", message: "Loading usage…", rangeStart: start, rangeEnd: end)
        }
        loading = true; inFlight = query; push()
        Task {
            // Coalesce quick range navigation before starting a collector.
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard own == version else { return }
            var result = await Store.read(end, days)
            guard own == version else { return }
            result.rangeStart = start; result.rangeEnd = end
            snapshot = Store.merge(snapshot, result)
            loading = false; inFlight = ""; checked = Date(); push(); store?.changed?()
        }
    }
    func refresh() { if !end.isEmpty { request(end: end, days: days) } }
    func push() {
        guard ready, let store else { return }
        struct Payload: Encodable { var current: Snapshot; var history: Snapshot; var loading: Bool; var dailyLimit: Double; var monthlyLimit: Double }
        let p = Payload(current: store.current, history: snapshot, loading: loading, dailyLimit: store.dailyLimit, monthlyLimit: store.monthlyLimit)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let raw = try? encoder.encode(p), raw != lastPayload,
              let object = try? JSONSerialization.jsonObject(with: raw) else { return }
        lastPayload = raw
        Task { _ = try? await web.callAsyncJavaScript("window.receive(payload)", arguments: ["payload":object], in: nil, contentWorld: .page) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        decisionHandler(url?.absoluteString == "about:blank" ? .allow : .cancel)
    }
}
struct PaceWeb: NSViewRepresentable {
    let bridge: PaceBridge
    func makeNSView(context: Context) -> WKWebView { bridge.web }
    func updateNSView(_ nsView: WKWebView, context: Context) { bridge.push() }
}
