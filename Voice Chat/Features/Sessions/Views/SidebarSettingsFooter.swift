import SwiftUI

enum SidebarSettingsFooterStyle {
    case mac
    case touch
    case vision
}

struct SidebarSettingsFooter: View {
    let style: SidebarSettingsFooterStyle
    let onOpenSettings: () -> Void

    var body: some View {
        switch style {
        case .mac:
            macFooter
        case .touch:
            touchFooter
        case .vision:
            visionFooter
        }
    }

    private var cornerRadius: CGFloat {
        #if os(macOS)
        return 22
        #else
        return 18
        #endif
    }

    private var outerHorizontalPadding: CGFloat {
        #if os(macOS)
        return 12
        #elseif os(visionOS)
        return 20
        #else
        return 16
        #endif
    }

    private var outerVerticalPadding: CGFloat {
        #if os(macOS)
        return 6
        #elseif os(visionOS)
        return 12
        #else
        return 8
        #endif
    }

    private var innerHorizontalPadding: CGFloat {
        #if os(macOS)
        return 14
        #elseif os(visionOS)
        return 16
        #else
        return 12
        #endif
    }

    private var innerVerticalPadding: CGFloat {
        #if os(macOS)
        return 7
        #elseif os(visionOS)
        return 12
        #else
        return 10
        #endif
    }

    @ViewBuilder
    private var label: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            Image(systemName: "gear")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Settings")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, innerHorizontalPadding)
        .padding(.vertical, innerVerticalPadding)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var macFooter: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            Divider()
            if #available(macOS 26.0, *) {
                SettingsLink {
                    label
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: cornerRadius))
                .controlSize(.mini)
                .padding(.horizontal, outerHorizontalPadding)
                .padding(.vertical, outerVerticalPadding)
            } else {
                SettingsLink {
                    label
                        .appChromedContainer(
                            cornerRadius: cornerRadius,
                            interactive: true,
                            shadowOpacity: 0.24
                        )
                        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .padding(.horizontal, outerHorizontalPadding)
                        .padding(.vertical, outerVerticalPadding)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .controlSize(.mini)
            }
        }
        .background(.bar)
        #else
        EmptyView()
        #endif
    }

    @ViewBuilder
    private var touchFooter: some View {
        #if os(macOS)
        EmptyView()
        #else
        VStack(spacing: 10) {
            if #available(iOS 26.0, *) {
                Button(action: onOpenSettings) {
                    label
                }
                .appGlassButtonStyle()
                .buttonBorderShape(.roundedRectangle(radius: cornerRadius))
                .padding(.horizontal, outerHorizontalPadding)
            } else {
                Button(action: onOpenSettings) {
                    label
                        .appChromedContainer(
                            cornerRadius: cornerRadius,
                            interactive: true,
                            shadowOpacity: 0.44
                        )
                        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, outerHorizontalPadding)
            }
        }
        .padding(.vertical, 8)
        .background(.thinMaterial)
        #endif
    }

    @ViewBuilder
    private var visionFooter: some View {
        #if os(macOS)
        EmptyView()
        #else
        VStack(spacing: 0) {
            Divider()

            Button(action: onOpenSettings) {
                label
                    .appChromedContainer(
                        cornerRadius: cornerRadius,
                        interactive: true,
                        shadowOpacity: 0.24
                    )
                    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, outerHorizontalPadding)
            .padding(.vertical, outerVerticalPadding)
        }
        .background(.bar)
        #endif
    }
}
