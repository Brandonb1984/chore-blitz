import UIKit

/// A MacBook-style keyboard drawn in one view so several fingers can press keys at once
/// (hold ⌘ with one finger, tap Tab with another).
///
/// Modifiers: hold to use with another key; tap once to latch for the next key (or click);
/// tap twice to lock; tap again to release.
final class KeyboardView: UIView {
    weak var client: RFBClient?

    private struct Hit: Equatable {
        var row: Int
        var col: Int
        var arrow: Int = -1   // 0 left, 1 up, 2 down, 3 right
    }

    private enum ModState { case off, held, latched, locked }

    private var keyRects: [[CGRect]] = []
    private var arrowRects: [CGRect] = []
    private var active: [ObjectIdentifier: (hit: Hit, keysym: UInt32?)] = [:]
    private var modState: [Modifier: ModState] = [:]
    private var modUsedWhileHeld: Set<Modifier> = []
    private var fnState: ModState = .off
    private var fnUsed = false
    private var lastModTap: [Modifier: Date] = [:]
    private var repeatTimer: Timer?
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private let keyColor = UIColor(red: 0.176, green: 0.180, blue: 0.200, alpha: 1)
    private let modColor = UIColor(red: 0.149, green: 0.153, blue: 0.169, alpha: 1)
    private let pressedColor = UIColor(red: 0.29, green: 0.30, blue: 0.33, alpha: 1)
    private let accent = UIColor(red: 0.62, green: 0.77, blue: 1.0, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let gap: CGFloat = max(3, bounds.width * 0.006)
        let weights: [CGFloat] = [0.65, 1, 1, 1, 1, 1]
        let unitH = (bounds.height - gap * CGFloat(weights.count - 1)) / weights.reduce(0, +)
        var y: CGFloat = 0
        keyRects = []
        for (r, row) in MacLayout.rows.enumerated() {
            let h = unitH * weights[r]
            let totalUnits = row.reduce(0) { $0 + $1.units }
            let unitW = (bounds.width - gap * CGFloat(row.count - 1)) / totalUnits
            var x: CGFloat = 0
            var rects: [CGRect] = []
            for key in row {
                let w = unitW * key.units + gap * (key.units - 1)
                rects.append(CGRect(x: x, y: y, width: w, height: h))
                x += w + gap
            }
            keyRects.append(rects)
            y += h + gap
        }
        // Inverted-T arrow cluster inside the last key of the bottom row.
        if let a = keyRects.last?.last {
            let w = (a.width - gap * 2) / 3
            let half = (a.height - gap) / 2
            arrowRects = [
                CGRect(x: a.minX, y: a.minY + half + gap, width: w, height: half),
                CGRect(x: a.minX + w + gap, y: a.minY, width: w, height: half),
                CGRect(x: a.minX + w + gap, y: a.minY + half + gap, width: w, height: half),
                CGRect(x: a.minX + 2 * (w + gap), y: a.minY + half + gap, width: w, height: half),
            ]
        }
        setNeedsDisplay()
    }

    private func hit(at p: CGPoint) -> Hit? {
        for (r, rects) in keyRects.enumerated() {
            for (c, rect) in rects.enumerated() where rect.insetBy(dx: -2, dy: -2).contains(p) {
                if case .arrows = MacLayout.rows[r][c].kind {
                    // nearest arrow
                    let i = arrowRects.indices.min { dist(arrowRects[$0], p) < dist(arrowRects[$1], p) } ?? 0
                    return Hit(row: r, col: c, arrow: i)
                }
                return Hit(row: r, col: c)
            }
        }
        return nil
    }

    private func dist(_ r: CGRect, _ p: CGPoint) -> CGFloat {
        hypot(r.midX - p.x, r.midY - p.y)
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        let pressed = Set(active.values.map { "\($0.hit.row),\($0.hit.col),\($0.hit.arrow)" })
        for (r, row) in MacLayout.rows.enumerated() where r < keyRects.count {
            for (c, key) in row.enumerated() {
                let kr = keyRects[r][c]
                if case .arrows = key.kind {
                    let glyphs = ["◀", "▲", "▼", "▶"]
                    for (i, ar) in arrowRects.enumerated() {
                        let isDown = pressed.contains("\(r),\(c),\(i)")
                        drawKey(ar, fill: isDown ? pressedColor : keyColor, label: glyphs[i], top: "", small: false, size: 10)
                    }
                    continue
                }
                var fill = key.small ? modColor : keyColor
                var labelColor = UIColor(white: 0.92, alpha: 1)
                if pressed.contains("\(r),\(c),-1") { fill = pressedColor }
                if case .modifier(let m) = key.kind {
                    switch modState[m] ?? .off {
                    case .latched: labelColor = accent
                    case .locked: fill = accent.withAlphaComponent(0.35); labelColor = accent
                    case .held: fill = pressedColor
                    case .off: break
                    }
                }
                if case .fn = key.kind {
                    if fnState == .latched { labelColor = accent }
                    if fnState == .locked { fill = accent.withAlphaComponent(0.35); labelColor = accent }
                }
                drawKey(kr, fill: fill, label: key.label, top: key.top, small: key.small,
                        size: key.small ? 11 : 16, labelColor: labelColor, alignLeft: key.small && key.units > 1.1)
            }
        }
    }

    private func drawKey(_ r: CGRect, fill: UIColor, label: String, top: String, small: Bool, size: CGFloat,
                         labelColor: UIColor = UIColor(white: 0.92, alpha: 1), alignLeft: Bool = false) {
        fill.setFill()
        UIBezierPath(roundedRect: r, cornerRadius: min(7, r.height * 0.16)).fill()
        let para = NSMutableParagraphStyle()
        para.alignment = alignLeft ? .left : .center
        let fontSize = min(size, r.height * 0.36)
        let main: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: fontSize, weight: .regular),
                                                    .foregroundColor: labelColor, .paragraphStyle: para]
        let sub: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: min(10, r.height * 0.24)),
                                                   .foregroundColor: UIColor(white: 0.64, alpha: 1), .paragraphStyle: para]
        let inner = r.insetBy(dx: 7, dy: 4)
        if top.isEmpty {
            let s = NSAttributedString(string: label, attributes: main)
            let h = s.size().height
            let y = small && alignLeft ? inner.maxY - h : inner.midY - h / 2
            s.draw(in: CGRect(x: inner.minX, y: y, width: inner.width, height: h))
        } else {
            let t = NSAttributedString(string: top, attributes: sub)
            let s = NSAttributedString(string: label, attributes: main)
            let total = t.size().height + s.size().height
            var y = inner.midY - total / 2
            t.draw(in: CGRect(x: inner.minX, y: y, width: inner.width, height: t.size().height))
            y += t.size().height
            s.draw(in: CGRect(x: inner.minX, y: y, width: inner.width, height: s.size().height))
        }
    }

    // MARK: Touches

    private var anyShift: Bool { (modState[.shift] ?? .off) != .off }
    private var fnActive: Bool { fnState != .off }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let h = hit(at: t.location(in: self)) else { continue }
            let key = MacLayout.rows[h.row][h.col]
            haptic.impactOccurred(intensity: 0.6)
            var sym: UInt32?
            switch key.kind {
            case .modifier(let m):
                modifierDown(m)
            case .fn:
                if fnState == .off { fnState = .held; fnUsed = false }
                else if fnState == .latched { fnState = .locked }
                else if fnState == .locked { fnState = .off }
            case .lockScreen:
                for k in [Keysym.control, Keysym.command] { client?.sendKey(k, down: true) }
                client?.sendKey(0x71, down: true); client?.sendKey(0x71, down: false)
                for k in [Keysym.command, Keysym.control] { client?.sendKey(k, down: false) }
            case .char(let lower, let upper):
                sym = MacLayout.keysym(for: anyShift ? upper : lower)
            case .special(let s):
                sym = (fnActive && s == Keysym.backspace) ? Keysym.forwardDelete : s
            case .arrows:
                let plain = [Keysym.left, Keysym.up, Keysym.down, Keysym.right]
                let fn = [Keysym.home, Keysym.pageUp, Keysym.pageDown, Keysym.end]
                sym = (fnActive ? fn : plain)[max(0, h.arrow)]
            }
            if let s = sym {
                markModifiersUsed()
                client?.sendKey(s, down: true)
                startRepeat(s)
            }
            active[ObjectIdentifier(t)] = (h, sym)
        }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        var releasedNormalKey = false
        for t in touches {
            guard let entry = active.removeValue(forKey: ObjectIdentifier(t)) else { continue }
            let key = MacLayout.rows[entry.hit.row][entry.hit.col]
            if let s = entry.keysym {
                client?.sendKey(s, down: false)
                releasedNormalKey = true
                stopRepeat()
            }
            if case .modifier(let m) = key.kind { modifierUp(m) }
            if case .fn = key.kind, fnState == .held { fnState = fnUsed ? .off : .latched }
        }
        if releasedNormalKey { releaseOneShots() }
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    // MARK: Modifiers

    private func modifierDown(_ m: Modifier) {
        switch modState[m] ?? .off {
        case .off:
            modState[m] = .held
            modUsedWhileHeld.remove(m)
            client?.sendKey(m.keysym, down: true)
        case .latched:
            modState[m] = .locked
        case .locked:
            modState[m] = .off
            client?.sendKey(m.keysym, down: false)
        case .held:
            break // second finger on the other shift key
        }
    }

    private func modifierUp(_ m: Modifier) {
        guard modState[m] == .held else { return }
        if modUsedWhileHeld.contains(m) {
            modState[m] = .off
            client?.sendKey(m.keysym, down: false)
        } else {
            modState[m] = .latched   // tapped alone: stays down for the next key or click
        }
    }

    private func markModifiersUsed() {
        for (m, s) in modState where s == .held { modUsedWhileHeld.insert(m) }
        if fnState == .held { fnUsed = true }
    }

    /// Called after a key or a trackpad click: drop one-shot (latched) modifiers.
    func releaseOneShots() {
        for (m, s) in modState where s == .latched {
            modState[m] = .off
            client?.sendKey(m.keysym, down: false)
        }
        if fnState == .latched { fnState = .off }
        for (m, s) in modState where s == .held { modUsedWhileHeld.insert(m) }
        setNeedsDisplay()
    }

    // MARK: Repeat

    private func startRepeat(_ sym: UInt32) {
        stopRepeat()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
                self?.client?.sendKey(sym, down: true)
            }
        }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}
