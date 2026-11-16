import SwiftUI
import NotchBoardCore

enum Theme {
    /// Draft & Focus teal.
    static let accent = Color(red: 0x54 / 255, green: 0xCB / 255, blue: 0xBB / 255)
    static let card = Color.white.opacity(0.07)
    static let secondary = Color.white.opacity(0.58)
    static let tertiary = Color.white.opacity(0.38)
    static let spring = Animation.spring(response: 0.34, dampingFraction: 0.84)
}

/// The black shape that grows out of the notch.
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    /// Small outward flare at the top corners, like the hardware notch.
    var topFlare: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(bottomRadius, topFlare) }
        set { bottomRadius = newValue.first; topFlare = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let f = min(topFlare, rect.width / 4)
        let r = min(bottomRadius, rect.height / 2, (rect.width - 2 * f) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + f, y: rect.minY + f),
                       control: CGPoint(x: rect.minX + f, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + f, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + f + r, y: rect.maxY),
                       control: CGPoint(x: rect.minX + f, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - f - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - f, y: rect.maxY - r),
                       control: CGPoint(x: rect.maxX - f, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - f, y: rect.minY + f))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - f, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct NotchRootView: View {
    let model: AppModel
    let layout: NotchLayout

    private var size: CGSize {
        if model.isExpanded { return NotchLayout.expandedSize }
        let wings = model.music.isPlaying ? NotchLayout.wingWidth * 2 : 0
        return CGSize(width: layout.notchSize.width + wings, height: layout.notchSize.height)
    }

    var body: some View {
        let expanded = model.isExpanded
        let shape = NotchShape(bottomRadius: expanded ? 26 : 10, topFlare: expanded ? 10 : 6)
        // Glass only while open; collapsed it must match the black hardware notch.
        let glass = expanded ? model.preferences.effectiveGlass : 0
        ZStack(alignment: .top) {
            PanelBackground(shape: shape, glass: glass, style: model.preferences.glassStyle)
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .top) {
                    Group {
                        if expanded {
                            ExpandedView(model: model, notchSize: layout.notchSize)
                                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                        } else {
                            CollapsedView(music: model.music, notchSize: layout.notchSize)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .clipShape(shape)
                }
                .shadow(color: .black.opacity(expanded ? 0.35 : 0), radius: 12, y: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Theme.spring, value: expanded)
        .animation(Theme.spring, value: model.music.isPlaying)
        .animation(.easeOut(duration: 0.2), value: glass)
        .environment(\.glassAmount, glass)
        .environment(\.colorScheme, .dark)
    }
}

/// Liquid Glass under a black tint. `glass` 0 is solid black, 1 is bare glass.
struct PanelBackground: View {
    let shape: NotchShape
    let glass: Double
    let style: Preferences.GlassStyle

    var body: some View {
        ZStack {
            if glass > 0 { glassLayer }
            shape.fill(Color.black.opacity(1 - glass))
        }
    }

    @ViewBuilder private var glassLayer: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(style == .clear ? .clear : .regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}

extension EnvironmentValues {
    /// How much glass shows through, so cards can add contrast to match.
    @Entry var glassAmount: Double = 0
}

/// Collapsed: artwork in the left wing and a live waveform in the right
/// while music plays; otherwise just the black notch.
struct CollapsedView: View {
    let music: MusicService
    let notchSize: CGSize

    var body: some View {
        HStack(spacing: 0) {
            if music.isPlaying {
                ArtworkView(image: music.artwork, size: max(notchSize.height - 12, 14), corner: 5)
                    .frame(width: NotchLayout.wingWidth)
                Spacer(minLength: notchSize.width)
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: true)
                    .frame(width: NotchLayout.wingWidth)
            }
        }
        .frame(height: notchSize.height)
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let corner: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Theme.card
                    Image(systemName: "music.note").font(.system(size: size * 0.42)).foregroundStyle(Theme.tertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}
