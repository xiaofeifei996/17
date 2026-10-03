import Foundation
import CoreGraphics

func PXAppRailX(base: CGFloat, bow: CGFloat, progress: CGFloat) -> CGFloat {
    base - bow * CGFloat(sin(Double(min(1, max(0, progress))) * Double.pi))
}

func PXAppGridCell(count: Int, width: CGFloat, height: CGFloat) -> CGFloat {
    min(max(0, width) / 3, max(0, height) / CGFloat(max(1, (count + 2) / 3)))
}

struct PXAppRailSelection {
    private(set) var index: Int?
    private(set) var locked = false
    private var anchor: CGPoint?

    mutating func update(point: CGPoint, rail: CGRect, railX: CGFloat, count: Int) -> Int? {
        guard count > 0, rail.height > 0 else { return nil }
        let nearRail = abs(point.x - railX) <= (locked ? 10 : 26) &&
            point.y >= rail.minY && point.y <= rail.maxY
        if locked {
            guard nearRail else { return nil }
            locked = false
            anchor = point
        }
        if let anchor = anchor, anchor.x - point.x >= 12,
           anchor.x - point.x > abs(point.y - anchor.y) {
            locked = true
            return nil
        }
        guard nearRail else { return nil }
        let step = rail.height / CGFloat(count)
        var next = min(count - 1, max(0, Int((point.y - rail.minY) / step)))
        if let index = index,
           point.y >= rail.minY + CGFloat(index) * step - 5,
           point.y <= rail.minY + CGFloat(index + 1) * step + 5 {
            next = index
        }
        let movingVertically = anchor.map {
            abs(point.y - $0.y) >= 6 && abs(point.y - $0.y) > abs(point.x - $0.x)
        } ?? true
        if next != index || movingVertically {
            anchor = point
        }
        index = next
        return next
    }
}

// Shared by the selector and its Foundation-only check.
func PXAppInitial(_ name: String) -> String {
    let latin = (name.applyingTransform(.toLatin, reverse: false) ?? name)
        .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard let first = latin.unicodeScalars.first, (65...90).contains(first.value) else { return "#" }
    return String(first)
}
