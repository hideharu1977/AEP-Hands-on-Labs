import UIKit

/*
 * Doom key codes (from doomkeys.h in doomgeneric)
 * Using raw values so we don't need to import the C header directly.
 */
private enum DoomKey: UInt8 {
    case escape    = 0x1B
    case space     = 0x20
    case left      = 0xAC
    case up        = 0xAD
    case right     = 0xAE
    case down      = 0xAF
    case fire      = 0x80   // KEY_RCTRL
    case run       = 0x82   // KEY_RSHIFT
    case strafe    = 0x38   // KEY_ALT (0x38)
    case enter     = 0x0D
}

/// A transparent overlay view providing virtual gamepad controls for Doom.
/// Left side: D-pad. Right side: action buttons. Center-top: start/escape.
///
/// Each button tracks active touches and injects key-down / key-up events
/// into the C engine via dg_ios_push_key().
class TouchControlsView: UIView {

    // MARK: - Button descriptors

    private struct Button {
        let frame: CGRect
        let key: DoomKey
        let label: String
        var isPressed: Bool = false
    }

    private var buttons: [Button] = []
    private var touchButtonMap: [UITouch: Int] = [:]  // touch → button index

    // MARK: - Layout constants (relative to view bounds)

    private let buttonSize: CGFloat = 60
    private let dpadSpacing: CGFloat = 64   // centre-to-centre of adjacent d-pad buttons
    private let buttonAlpha: CGFloat = 0.35

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        buildButtons()
        setNeedsDisplay()
    }

    private func buildButtons() {
        let w = bounds.width
        let h = bounds.height
        let s = buttonSize
        let sp = dpadSpacing

        // D-pad centre anchor (bottom-left quadrant)
        let dpadCX = w * 0.15 + s
        let dpadCY = h - s * 2.5

        // Action buttons centre anchor (bottom-right quadrant)
        let actCX = w - w * 0.15 - s
        let actCY = h - s * 2.5

        buttons = [
            // D-pad
            Button(frame: centredRect(dpadCX,         dpadCY - sp, s, s), key: .up,    label: "▲"),
            Button(frame: centredRect(dpadCX,         dpadCY + sp, s, s), key: .down,  label: "▼"),
            Button(frame: centredRect(dpadCX - sp,    dpadCY,      s, s), key: .left,  label: "◀"),
            Button(frame: centredRect(dpadCX + sp,    dpadCY,      s, s), key: .right, label: "▶"),
            // Action buttons (right side)
            Button(frame: centredRect(actCX,          actCY - sp * 0.6, s, s), key: .fire,  label: "A"),
            Button(frame: centredRect(actCX - sp * 0.7, actCY,          s, s), key: .space, label: "B"),
            Button(frame: centredRect(actCX + sp * 0.7, actCY,          s, s), key: .run,   label: "Y"),
            // Start / escape (top-centre)
            Button(frame: centredRect(w / 2,          s * 1.2,     s * 1.2, s * 0.7), key: .escape, label: "⏸"),
        ]
    }

    private func centredRect(_ cx: CGFloat, _ cy: CGFloat,
                              _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        for button in buttons {
            let color: UIColor = button.isPressed ? .white : .lightGray
            ctx.setFillColor(color.withAlphaComponent(buttonAlpha).cgColor)
            ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.5).cgColor)
            ctx.setLineWidth(1.5)
            let path = UIBezierPath(roundedRect: button.frame, cornerRadius: 8)
            ctx.addPath(path.cgPath)
            ctx.drawPath(using: .fillStroke)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9)
            ]
            let str = button.label as NSString
            let strSize = str.size(withAttributes: attrs)
            let strOrigin = CGPoint(
                x: button.frame.midX - strSize.width / 2,
                y: button.frame.midY - strSize.height / 2
            )
            str.draw(at: strOrigin, withAttributes: attrs)
        }
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let pt = touch.location(in: self)
            if let idx = buttonIndex(for: pt) {
                touchButtonMap[touch] = idx
                pressButton(idx, pressed: true)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let pt = touch.location(in: self)
            let newIdx = buttonIndex(for: pt)
            let oldIdx = touchButtonMap[touch]

            if newIdx != oldIdx {
                if let old = oldIdx { pressButton(old, pressed: false) }
                if let new = newIdx {
                    touchButtonMap[touch] = new
                    pressButton(new, pressed: true)
                } else {
                    touchButtonMap.removeValue(forKey: touch)
                }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let idx = touchButtonMap.removeValue(forKey: touch) {
                pressButton(idx, pressed: false)
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    // MARK: - Helpers

    private func buttonIndex(for point: CGPoint) -> Int? {
        for (i, btn) in buttons.enumerated() {
            if btn.frame.contains(point) { return i }
        }
        return nil
    }

    private func pressButton(_ index: Int, pressed: Bool) {
        guard index < buttons.count else { return }
        let wasPressed = buttons[index].isPressed
        guard wasPressed != pressed else { return }

        buttons[index].isPressed = pressed
        let key = buttons[index].key.rawValue
        dg_ios_push_key(pressed ? 1 : 0, key)

        // Redraw only the changed button region
        setNeedsDisplay(buttons[index].frame.insetBy(dx: -4, dy: -4))
    }
}
