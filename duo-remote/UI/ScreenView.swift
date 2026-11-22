import UIKit

/// Shows the Mac's screen. Pinch to zoom and pan; tap to move the pointer there.
final class ScreenView: UIScrollView, UIScrollViewDelegate {
    let content = UIView()
    private let cursorLayer = CALayer()
    private var fbSize = CGSize(width: 1, height: 1)
    private var cursorHot = CGPoint.zero
    var onTapAt: ((CGPoint) -> Void)?   // framebuffer pixel coordinates

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = .black
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        bouncesZoom = true
        content.layer.contentsGravity = .resize
        content.layer.magnificationFilter = .linear
        content.layer.minificationFilter = .trilinear
        content.layer.backgroundColor = UIColor(white: 0.12, alpha: 1).cgColor
        addSubview(content)
        cursorLayer.anchorPoint = .zero
        cursorLayer.magnificationFilter = .nearest
        cursorLayer.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull()]
        content.layer.addSublayer(cursorLayer)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        addGestureRecognizer(tap)
        isAccessibilityElement = true
        accessibilityLabel = "Mac screen"
    }
    required init?(coder: NSCoder) { fatalError() }

    func setFramebufferSize(_ size: CGSize) {
        fbSize = size
        zoomScale = 1
        content.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        updateZoomLimits(reset: true)
    }

    func show(_ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.layer.contents = image
        CATransaction.commit()
    }

    func setCursor(_ image: CGImage, hot: CGPoint) {
        cursorHot = hot
        cursorLayer.contents = image
        cursorLayer.bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    }

    func moveCursor(to p: CGPoint) {
        cursorLayer.position = CGPoint(x: p.x - cursorHot.x, y: p.y - cursorHot.y)
        // Keep the pointer visible when zoomed in.
        if zoomScale > minimumZoomScale * 1.05 {
            let r = CGRect(x: p.x - 60, y: p.y - 60, width: 120, height: 120)
            scrollRectToVisible(r.applying(CGAffineTransform(scaleX: zoomScale, y: zoomScale)), animated: false)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateZoomLimits(reset: false)
        centerContent()
    }

    private func updateZoomLimits(reset: Bool) {
        guard bounds.width > 0, fbSize.width > 0 else { return }
        let fit = min(bounds.width / fbSize.width, bounds.height / fbSize.height)
        let wasAtMin = zoomScale <= minimumZoomScale + 0.0001
        minimumZoomScale = fit
        maximumZoomScale = max(fit * 6, 2)
        if reset || wasAtMin || zoomScale < fit { zoomScale = fit }
        centerContent()
    }

    private func centerContent() {
        let w = content.frame.width, h = content.frame.height
        let insetX = max(0, (bounds.width - w) / 2)
        let insetY = max(0, (bounds.height - h) / 2)
        contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

    func zoom(by scale: CGFloat) {
        let s = max(minimumZoomScale, min(maximumZoomScale, zoomScale * scale))
        setZoomScale(s, animated: false)
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        let p = g.location(in: content)
        guard p.x >= 0, p.y >= 0, p.x < fbSize.width, p.y < fbSize.height else { return }
        onTapAt?(p)
    }
}
