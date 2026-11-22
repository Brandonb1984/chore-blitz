import UIKit
import Network

/// The connected screen. Two layouts:
/// - Laptop: Mac screen on the top half, keyboard + trackpad on the bottom half (Duo half-folded).
/// - Full: Mac screen fills the display, with a small floating trackpad and a keyboard button.
final class RemoteViewController: UIViewController, TrackpadDelegate {
    enum Mode { case laptop, full }

    let client = RFBClient()
    private let endpoint: NWEndpoint
    private let credentials: RFBClient.Credentials
    private let title_: String
    var onClose: ((String?) -> Void)?

    private let screen = ScreenView()
    private let bottomPanel = UIView()
    private let keyboard = KeyboardView()
    private let trackpad = TrackpadView()
    private let hinge = UIView()
    private let pill = UIStackView()
    private let statusDot = UIView()
    private let statusLabel = UILabel()
    private let modeButton = UIButton(type: .system)
    private let keyboardButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .large)

    private var forcedMode: Mode?
    private var showKeyboardInFull = false
    private var floatingTrackpadOrigin: CGPoint?
    private var pointer = CGPoint(x: 100, y: 100)
    private var buttons: UInt8 = 0
    private var scrollAccum = CGPoint.zero
    private var dirty = false
    private var displayLink: CADisplayLink?
    private var frames = 0
    private var fpsStamp = Date()

    init(endpoint: NWEndpoint, credentials: RFBClient.Credentials, title: String) {
        self.endpoint = endpoint
        self.credentials = credentials
        self.title_ = title
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError() }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    // MARK: Setup

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.047, green: 0.051, blue: 0.059, alpha: 1)

        view.addSubview(screen)
        hinge.backgroundColor = UIColor(red: 0.02, green: 0.02, blue: 0.024, alpha: 1)
        view.addSubview(hinge)
        bottomPanel.backgroundColor = UIColor(red: 0.110, green: 0.114, blue: 0.129, alpha: 1)
        bottomPanel.layer.cornerRadius = 18
        view.addSubview(bottomPanel)
        bottomPanel.addSubview(keyboard)
        view.addSubview(trackpad)

        keyboard.client = client
        trackpad.delegate = self
        let drag = UIPanGestureRecognizer(target: self, action: #selector(dragFloatingTrackpad(_:)))
        drag.minimumNumberOfTouches = 1
        drag.maximumNumberOfTouches = 1
        trackpadHandle.addGestureRecognizer(drag)
        trackpad.addSubview(trackpadHandle)

        screen.onTapAt = { [weak self] p in
            guard let self else { return }
            self.pointer = p
            self.sendPointer()
        }

        setupPill()
        spinner.color = .white
        spinner.startAnimating()
        view.addSubview(spinner)

        client.onConnected = { [weak self] w, h, name in
            guard let self else { return }
            self.spinner.stopAnimating()
            self.screen.setFramebufferSize(CGSize(width: w, height: h))
            self.pointer = CGPoint(x: w / 2, y: h / 2)
            self.statusLabel.text = name.isEmpty ? self.title_ : name
        }
        client.onResize = { [weak self] w, h in
            self?.screen.setFramebufferSize(CGSize(width: w, height: h))
        }
        client.onFrame = { [weak self] in self?.dirty = true }
        client.onCursor = { [weak self] c in
            guard let self else { return }
            self.screen.setCursor(c.image, hot: CGPoint(x: c.hotX, y: c.hotY))
            self.screen.moveCursor(to: self.pointer)
        }
        client.onClipboard = { text in UIPasteboard.general.string = text }
        client.onDisconnect = { [weak self] err in
            self?.displayLink?.invalidate()
            self?.onClose?(err?.localizedDescription)
        }
        client.connect(endpoint: endpoint, credentials: credentials)

        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private let trackpadHandle: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(white: 1, alpha: 0.25)
        v.layer.cornerRadius = 2.5
        return v
    }()

    private func setupPill() {
        pill.axis = .horizontal
        pill.alignment = .center
        pill.spacing = 6
        pill.backgroundColor = UIColor(red: 0.047, green: 0.051, blue: 0.059, alpha: 0.82)
        pill.layer.cornerRadius = 22
        pill.isLayoutMarginsRelativeArrangement = true
        pill.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 4)

        statusDot.backgroundColor = UIColor(red: 0.29, green: 0.87, blue: 0.5, alpha: 1)
        statusDot.layer.cornerRadius = 4
        statusDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        statusLabel.textColor = UIColor(white: 0.95, alpha: 1)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.text = "Connecting to \(title_)…"

        func style(_ b: UIButton, _ symbol: String, _ label: String, _ action: Selector) {
            b.setImage(UIImage(systemName: symbol), for: .normal)
            b.tintColor = UIColor(white: 0.95, alpha: 1)
            b.backgroundColor = UIColor(red: 0.165, green: 0.173, blue: 0.192, alpha: 1)
            b.layer.cornerRadius = 18
            b.accessibilityLabel = label
            b.widthAnchor.constraint(equalToConstant: 36).isActive = true
            b.heightAnchor.constraint(equalToConstant: 36).isActive = true
            b.addTarget(self, action: action, for: .touchUpInside)
        }
        style(modeButton, "laptopcomputer", "Switch layout", #selector(toggleMode))
        style(keyboardButton, "keyboard", "Show keyboard", #selector(toggleKeyboard))
        style(closeButton, "xmark", "Disconnect", #selector(close))

        for v in [statusDot, statusLabel, keyboardButton, modeButton, closeButton] { pill.addArrangedSubview(v) }
        pill.setCustomSpacing(12, after: statusLabel)
        view.addSubview(pill)
    }

    // MARK: Layout

    /// Laptop when the display is wider than tall (Duo held sideways and half-folded),
    /// unless the person picked a layout with the button.
    /// TODO: if the iOS SDK exposes the Duo's fold posture, use it here instead of the shape.
    private var mode: Mode {
        if let f = forcedMode { return f }
        return view.bounds.width > view.bounds.height * 1.05 ? .laptop : .full
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        let safe = view.safeAreaInsets
        spinner.center = CGPoint(x: b.midX, y: mode == .laptop ? b.height * 0.25 : b.midY)

        switch mode {
        case .laptop:
            let fold = b.height / 2
            let hingeH: CGFloat = 12
            screen.frame = CGRect(x: 0, y: 0, width: b.width, height: fold - hingeH / 2)
            hinge.frame = CGRect(x: 0, y: fold - hingeH / 2, width: b.width, height: hingeH)
            hinge.isHidden = false
            let panel = CGRect(x: max(safe.left, 8), y: fold + hingeH / 2 + 4,
                               width: b.width - max(safe.left, 8) - max(safe.right, 8),
                               height: b.height - fold - hingeH / 2 - max(safe.bottom, 8) - 4)
            layoutKeyboardPanel(in: panel, trackpadFloating: false)
            keyboardButton.isHidden = true
            modeButton.setImage(UIImage(systemName: "rectangle.inset.filled"), for: .normal)
        case .full:
            screen.frame = b
            hinge.isHidden = true
            keyboardButton.isHidden = false
            modeButton.setImage(UIImage(systemName: "laptopcomputer"), for: .normal)
            if showKeyboardInFull {
                let h = min(b.height * 0.5, b.width * 0.62)
                let panel = CGRect(x: 8, y: b.height - h - max(safe.bottom, 8), width: b.width - 16, height: h)
                layoutKeyboardPanel(in: panel, trackpadFloating: false)
            } else {
                bottomPanel.isHidden = true
                let size = CGSize(width: min(260, b.width * 0.55), height: min(170, b.width * 0.36))
                let origin = floatingTrackpadOrigin ?? CGPoint(x: b.width - size.width - 16,
                                                               y: b.height - size.height - max(safe.bottom, 16))
                trackpad.frame = CGRect(origin: clampOrigin(origin, size: size), size: size)
                trackpad.alpha = 0.92
                trackpadHandle.isHidden = false
                trackpadHandle.frame = CGRect(x: size.width / 2 - 20, y: 6, width: 40, height: 5)
            }
        }

        pill.sizeToFit()
        let ps = pill.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        pill.frame = CGRect(x: screen.frame.maxX - ps.width - max(safe.right, 16),
                            y: max(safe.top, 12), width: ps.width, height: ps.height)
    }

    private func layoutKeyboardPanel(in panel: CGRect, trackpadFloating: Bool) {
        bottomPanel.isHidden = false
        bottomPanel.frame = panel
        let inset: CGFloat = 12
        let kbH = (panel.height - inset * 2) * 0.62
        keyboard.frame = CGRect(x: inset, y: inset, width: panel.width - inset * 2, height: kbH)
        let tpTop = panel.minY + inset + kbH + 12
        let tpH = panel.maxY - inset - tpTop
        let tpW = min(panel.width * 0.5, tpH * 2.25)
        trackpad.frame = CGRect(x: panel.midX - tpW / 2, y: tpTop, width: tpW, height: tpH)
        trackpad.alpha = 1
        trackpadHandle.isHidden = true
    }

    private func clampOrigin(_ o: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: max(8, min(view.bounds.width - size.width - 8, o.x)),
                y: max(8, min(view.bounds.height - size.height - 8, o.y)))
    }

    @objc private func dragFloatingTrackpad(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: view)
        g.setTranslation(.zero, in: view)
        floatingTrackpadOrigin = clampOrigin(CGPoint(x: trackpad.frame.minX + t.x, y: trackpad.frame.minY + t.y),
                                             size: trackpad.frame.size)
        view.setNeedsLayout()
    }

    @objc private func toggleMode() {
        forcedMode = (mode == .laptop) ? .full : .laptop
        UIView.animate(withDuration: 0.25) { self.view.setNeedsLayout(); self.view.layoutIfNeeded() }
    }

    @objc private func toggleKeyboard() {
        showKeyboardInFull.toggle()
        UIView.animate(withDuration: 0.25) { self.view.setNeedsLayout(); self.view.layoutIfNeeded() }
    }

    @objc private func close() {
        client.disconnect()
    }

    // MARK: Drawing

    @objc private func tick() {
        guard dirty else { return }
        dirty = false
        screen.show(client.framebuffer.makeImage())
        frames += 1
        let elapsed = Date().timeIntervalSince(fpsStamp)
        if elapsed > 2 {
            fpsStamp = Date()
            frames = 0
        }
    }

    // MARK: Trackpad

    private var gain: CGFloat {
        // ~1 pt of finger travel ≈ 1/1100 of the Mac's screen width
        max(1, CGFloat(client.framebuffer.width) / 1100)
    }

    private func sendPointer() {
        client.sendPointer(x: Int(pointer.x), y: Int(pointer.y), buttons: buttons)
        screen.moveCursor(to: pointer)
    }

    func trackpadMove(dx: CGFloat, dy: CGFloat) {
        let fb = client.framebuffer
        pointer.x = max(0, min(CGFloat(fb.width - 1), pointer.x + dx * gain))
        pointer.y = max(0, min(CGFloat(fb.height - 1), pointer.y + dy * gain))
        sendPointer()
    }

    func trackpadButton(_ mask: UInt8, down: Bool) {
        if down { buttons |= mask } else { buttons &= ~mask }
        sendPointer()
        if !down { keyboard.releaseOneShots() }
    }

    func trackpadScroll(dx: CGFloat, dy: CGFloat) {
        scrollAccum.x += dx
        scrollAccum.y += dy
        let step: CGFloat = 9
        func wheel(_ mask: UInt8) {
            client.sendPointer(x: Int(pointer.x), y: Int(pointer.y), buttons: buttons | mask)
            client.sendPointer(x: Int(pointer.x), y: Int(pointer.y), buttons: buttons)
        }
        while scrollAccum.y >= step { wheel(8); scrollAccum.y -= step }    // fingers down: scroll up
        while scrollAccum.y <= -step { wheel(16); scrollAccum.y += step }  // fingers up: scroll down
        while scrollAccum.x >= step { wheel(32); scrollAccum.x -= step }
        while scrollAccum.x <= -step { wheel(64); scrollAccum.x += step }
    }

    func trackpadPinch(scale: CGFloat) {
        screen.zoom(by: scale)
        screen.moveCursor(to: pointer)
    }

    func trackpadShortcut(_ keysyms: [UInt32]) {
        for k in keysyms { client.sendKey(k, down: true) }
        for k in keysyms.reversed() { client.sendKey(k, down: false) }
    }
}
