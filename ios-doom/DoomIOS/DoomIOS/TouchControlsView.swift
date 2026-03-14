import UIKit

/*
 * Doom key codes — must match doomkeys.h and the default bindings
 * in m_controls.c (key_fire, key_use, key_speed, etc.).
 */
private enum DoomKey: UInt8 {
    case escape    = 0x1B   // KEY_ESCAPE
    case enter     = 0x0D   // KEY_ENTER  (menu select)
    case left      = 0xAC   // KEY_LEFTARROW
    case up        = 0xAD   // KEY_UPARROW
    case right     = 0xAE   // KEY_RIGHTARROW
    case down      = 0xAF   // KEY_DOWNARROW
    case fire      = 0xA3   // KEY_FIRE   (default key_fire binding)
    case use       = 0xA2   // KEY_USE    (default key_use binding)
    case run       = 0xB6   // KEY_RSHIFT (default key_speed binding)
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
    private let buttonAlpha: CGFloat = 0.12

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
        print("[TouchControls] buildButtons: bounds=\(bounds)")
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
            Button(frame: centredRect(actCX - sp * 0.7, actCY,          s, s), key: .use,   label: "B"),
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
            // When pressed show a brighter fill; otherwise just a faint outline
            let alpha: CGFloat = button.isPressed ? buttonAlpha * 3 : buttonAlpha
            ctx.setFillColor(UIColor.white.withAlphaComponent(alpha).cgColor)
            ctx.setStrokeColor(UIColor.white.withAlphaComponent(alpha * 2).cgColor)
            ctx.setLineWidth(1)
            let path = UIBezierPath(roundedRect: button.frame, cornerRadius: 8)
            ctx.addPath(path.cgPath)
            ctx.drawPath(using: .fillStroke)
        }
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let pt = touch.location(in: self)
            let idx = buttonIndex(for: pt)
            print("[TouchControls] touchesBegan pt=\(pt) buttonIdx=\(String(describing: idx)) buttons=\(buttons.count)")
            if let idx = idx {
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
        let p: Int32 = pressed ? 1 : 0
        let key = buttons[index].key
        print("[TouchControls] pressButton[\(index)] label=\(buttons[index].label) key=0x\(String(key.rawValue, radix: 16)) pressed=\(pressed)")
        dg_ios_push_key(p, key.rawValue)

        // A (fire) also sends Enter so it doubles as menu-select.
        // KEY_FIRE is ignored in menus; KEY_ENTER is ignored in gameplay.
        if key == .fire {
            dg_ios_push_key(p, DoomKey.enter.rawValue)
        }

        // Redraw only the changed button region
        setNeedsDisplay(buttons[index].frame.insetBy(dx: -4, dy: -4))
    }
}
