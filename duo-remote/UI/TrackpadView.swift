import UIKit

protocol TrackpadDelegate: AnyObject {
    func trackpadMove(dx: CGFloat, dy: CGFloat)
    func trackpadButton(_ mask: UInt8, down: Bool)
    func trackpadScroll(dx: CGFloat, dy: CGFloat)
    func trackpadPinch(scale: CGFloat)
    func trackpadShortcut(_ keysyms: [UInt32])
}

/// Multi-touch trackpad: move, tap to click, two-finger tap for right click, two-finger scroll,
/// pinch (zooms the screen view), double-tap-and-hold to drag, three-finger swipes
/// (Mission Control, App Exposé, switch desktops) and a four-finger pinch (show desktop).
final class TrackpadView: UIView {
    weak var delegate: TrackpadDelegate?
    var naturalScrolling = true

    private var touchStart: [ObjectIdentifier: CGPoint] = [:]
    private var touchLast: [ObjectIdentifier: CGPoint] = [:]
    private var gestureStart = Date()
    private var maxTouches = 0
    private var moved: CGFloat = 0
    private var lastTapEnd: Date?
    private var dragging = false
    private var swipeFired = false
    private var swipeAccum = CGPoint.zero
    private var startSpread: CGFloat = 0
    private var lastSpread: CGFloat = 0
    private var pinching = false
    private var lastMoveTime = Date()
    private let haptic = UIImpactFeedbackGenerator(style: .rigid)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = UIColor(red: 0.145, green: 0.149, blue: 0.165, alpha: 1)
        layer.cornerRadius = 14
        layer.borderWidth = 1
        layer.borderColor = UIColor(red: 0.204, green: 0.208, blue: 0.231, alpha: 1).cgColor
        isAccessibilityElement = true
        accessibilityLabel = "Trackpad"
    }
    required init?(coder: NSCoder) { fatalError() }

    private func points() -> [CGPoint] { Array(touchLast.values) }

    private func centroid(_ pts: [CGPoint]) -> CGPoint {
        guard !pts.isEmpty else { return .zero }
        let s = pts.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: s.x / CGFloat(pts.count), y: s.y / CGFloat(pts.count))
    }

    private func spread(_ pts: [CGPoint]) -> CGFloat {
        let c = centroid(pts)
        guard pts.count > 1 else { return 0 }
        return pts.reduce(0) { $0 + hypot($1.x - c.x, $1.y - c.y) } / CGFloat(pts.count)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if touchLast.isEmpty {
            gestureStart = Date()
            maxTouches = 0
            moved = 0
            swipeFired = false
            swipeAccum = .zero
            pinching = false
            // Double-tap-and-hold: a touch right after a tap starts a drag.
            if let t = lastTapEnd, Date().timeIntervalSince(t) < 0.3, touches.count == 1 {
                dragging = true
                delegate?.trackpadButton(1, down: true)
            }
        }
        for t in touches {
            let p = t.location(in: self)
            touchStart[ObjectIdentifier(t)] = p
            touchLast[ObjectIdentifier(t)] = p
        }
        maxTouches = max(maxTouches, touchLast.count)
        startSpread = spread(points())
        lastSpread = startSpread
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let before = centroid(points())
        var single = CGPoint.zero
        for t in touches {
            let id = ObjectIdentifier(t)
            guard let last = touchLast[id] else { continue }
            let p = t.location(in: self)
            single = CGPoint(x: p.x - last.x, y: p.y - last.y)
            touchLast[id] = p
        }
        let after = centroid(points())
        let d = CGPoint(x: after.x - before.x, y: after.y - before.y)
        moved += hypot(d.x, d.y)
        let n = touchLast.count

        switch n {
        case 1:
            let now = Date()
            let dt = max(0.004, now.timeIntervalSince(lastMoveTime))
            lastMoveTime = now
            let speed = hypot(single.x, single.y) / CGFloat(dt)        // points per second
            let accel = min(3.2, 1 + speed / 700)
            delegate?.trackpadMove(dx: single.x * accel, dy: single.y * accel)
        case 2:
            let s = spread(points())
            if !pinching && abs(s - startSpread) > 28 && abs(s - startSpread) > moved * 0.8 { pinching = true }
            if pinching {
                if lastSpread > 0 { delegate?.trackpadPinch(scale: s / lastSpread) }
            } else {
                let k: CGFloat = naturalScrolling ? 1 : -1
                delegate?.trackpadScroll(dx: d.x * k, dy: d.y * k)
            }
            lastSpread = s
        case 3:
            guard !swipeFired else { break }
            swipeAccum.x += d.x; swipeAccum.y += d.y
            if abs(swipeAccum.y) > 50 && abs(swipeAccum.y) > abs(swipeAccum.x) {
                fireSwipe(swipeAccum.y < 0 ? [Keysym.control, Keysym.up] : [Keysym.control, Keysym.down])
            } else if abs(swipeAccum.x) > 60 {
                // Swipe left = go to the desktop on the right, like a real trackpad.
                fireSwipe(swipeAccum.x < 0 ? [Keysym.control, Keysym.right] : [Keysym.control, Keysym.left])
            }
        case 4:
            guard !swipeFired, startSpread > 0 else { break }
            if spread(points()) < startSpread * 0.6 { fireSwipe([Keysym.f1 + 10]) } // F11: show desktop
        default: break
        }
    }

    private func fireSwipe(_ keys: [UInt32]) {
        swipeFired = true
        haptic.impactOccurred()
        delegate?.trackpadShortcut(keys)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            touchStart.removeValue(forKey: ObjectIdentifier(t))
            touchLast.removeValue(forKey: ObjectIdentifier(t))
        }
        guard touchLast.isEmpty else { return }

        let quick = Date().timeIntervalSince(gestureStart) < 0.28 && moved < 12
        if dragging {
            delegate?.trackpadButton(1, down: false)
            dragging = false
            lastTapEnd = nil
            return
        }
        if quick && maxTouches == 1 {
            haptic.impactOccurred(intensity: 0.5)
            delegate?.trackpadButton(1, down: true)
            delegate?.trackpadButton(1, down: false)
            lastTapEnd = Date()
        } else if quick && maxTouches == 2 {
            haptic.impactOccurred(intensity: 0.5)
            delegate?.trackpadButton(4, down: true)
            delegate?.trackpadButton(4, down: false)
            lastTapEnd = nil
        } else {
            lastTapEnd = nil
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}
