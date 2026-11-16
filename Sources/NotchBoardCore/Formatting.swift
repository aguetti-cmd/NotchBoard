import Foundation
import CoreGraphics

public enum TokenFormat {
    /// 950, 12.4K, 3.1M, 1.2B
    public static func compact(_ value: Int) -> String {
        let v = Double(value)
        switch abs(v) {
        case ..<1_000: return "\(value)"
        case ..<10_000: return String(format: "%.1fK", v / 1_000)
        case ..<1_000_000: return String(format: "%.0fK", v / 1_000)
        case ..<10_000_000: return String(format: "%.1fM", v / 1_000_000)
        case ..<1_000_000_000: return String(format: "%.0fM", v / 1_000_000)
        default: return String(format: "%.1fB", v / 1_000_000_000)
        }
    }
}

public enum TimeFormat {
    /// 3:07 for a track position in seconds.
    public static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Where the notch is on a screen, or where a stand-in pill goes when the
/// screen has none. All values are in global screen coordinates.
public struct NotchGeometry: Sendable, Equatable {
    public let notch: CGRect
    public let hasNotch: Bool

    public static let fallbackWidth: CGFloat = 190

    public static func compute(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        leftAuxWidth: CGFloat?,
        rightAuxWidth: CGFloat?,
        menuBarHeight: CGFloat
    ) -> NotchGeometry {
        if safeAreaTop > 0, let l = leftAuxWidth, let r = rightAuxWidth {
            let width = screenFrame.width - l - r
            if width > 40 {
                let rect = CGRect(
                    x: screenFrame.minX + l,
                    y: screenFrame.maxY - safeAreaTop,
                    width: width,
                    height: safeAreaTop
                )
                return NotchGeometry(notch: rect, hasNotch: true)
            }
        }
        let height = max(menuBarHeight, 24)
        let rect = CGRect(
            x: screenFrame.midX - fallbackWidth / 2,
            y: screenFrame.maxY - height,
            width: fallbackWidth,
            height: height
        )
        return NotchGeometry(notch: rect, hasNotch: false)
    }
}
