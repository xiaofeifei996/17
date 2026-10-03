import Foundation
import CoreGraphics

for (name, expected) in [("微信", "W"), ("支付宝", "Z"), ("百度网盘", "B"),
                         ("YouTube", "Y"), ("  safari", "S"), ("Éclair", "E"),
                         ("Ａpp", "A"), ("123", "#"), ("🎬", "#"), ("", "#")] {
    precondition(PXAppInitial(name) == expected, "Incorrect index for \(name)")
}
print("App index checks passed")
let railCases: [(CGFloat, CGFloat)] = [(0, 380), (0.5, 330), (1, 380), (-1, 380), (2, 380)]
for (progress, expected) in railCases {
    precondition(abs(PXAppRailX(base: 380, bow: 50, progress: progress) - expected) < 0.001)
}
precondition(abs(PXAppRailX(base: 380, bow: 50, progress: 0.25) - PXAppRailX(base: 380, bow: 50, progress: 0.75)) < 0.001)
print("Curved index geometry checks passed")
for count in [1, 3, 9, 10, 18, 60, 150] {
    let cell = PXAppGridCell(count: count, width: 180, height: 500)
    precondition(cell * 3 <= 180.001)
    precondition(cell * CGFloat((count + 2) / 3) <= 500.001)
}
print("Full grid geometry checks passed")

let selectionRail = CGRect(x: 74, y: 0, width: 52, height: 260)
var selection = PXAppRailSelection()
func sample(_ x: CGFloat, _ y: CGFloat) -> Int? {
    selection.update(point: CGPoint(x: x, y: y), rail: selectionRail, railX: 100, count: 13)
}
precondition(sample(100, 30) == 1)
precondition(sample(100, 42) == 1) // Boundary jitter stays on the current letter.
precondition(sample(100, 46) == 2)
precondition(sample(100, 30) == 1)
precondition(sample(96, 31) == 1)
precondition(sample(92, 32) == 1)
precondition(sample(87, 33) == nil && selection.locked) // Gradual leftward departure.
precondition(sample(80, 10) == nil && selection.index == 1) // Vertical drift cannot change it.
precondition(sample(88, 30) == nil && selection.locked) // Separate re-entry threshold.
precondition(sample(94, 30) == 1 && !selection.locked)
precondition(sample(100, 10) == 0)
precondition(sample(100, 110) == 5) // Fast vertical indexing still works.
print("Letter departure lock and hysteresis checks passed")
