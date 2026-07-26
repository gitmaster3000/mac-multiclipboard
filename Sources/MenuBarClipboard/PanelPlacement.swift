import Foundation

/// Places the picker at the pointer the way Windows' Win+V does.
///
/// Pure so the edge and corner cases can be tested without a window or a real
/// screen. All coordinates are in AppKit's bottom-left origin space, which is
/// what `NSEvent.mouseLocation` and `NSScreen.visibleFrame` already use.
enum PanelPlacement {
    /// Gap between the pointer and the panel, so the panel does not open
    /// directly under the cursor.
    static let cursorGap: CGFloat = 4

    static func origin(
        cursor: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        // Preferred position: below and to the right of the pointer.
        var x = cursor.x + cursorGap
        var y = cursor.y - cursorGap - panelSize.height

        // Not enough room to the right: flip to the left of the pointer.
        if x + panelSize.width > visibleFrame.maxX {
            x = cursor.x - cursorGap - panelSize.width
        }

        // Not enough room below: flip above the pointer.
        if y < visibleFrame.minY {
            y = cursor.y + cursorGap
        }

        // Flipping can overshoot the opposite edge on a small screen, so clamp
        // last. Clamping runs even when the panel is larger than the frame, in
        // which case the top-left corner wins and the overflow falls off the
        // far edge.
        x = min(max(x, visibleFrame.minX), max(visibleFrame.maxX - panelSize.width, visibleFrame.minX))
        y = min(max(y, visibleFrame.minY), max(visibleFrame.maxY - panelSize.height, visibleFrame.minY))

        return CGPoint(x: x, y: y)
    }
}
