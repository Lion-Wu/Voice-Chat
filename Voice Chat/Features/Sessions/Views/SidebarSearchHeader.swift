import SwiftUI

enum SidebarSearchHeaderStyle {
    case touch
    case vision
}

struct SidebarSearchHeader: View {
    let style: SidebarSearchHeaderStyle
    @Binding var searchText: String

    var body: some View {
        VStack(spacing: 0) {
            searchField
        }
        .frame(maxWidth: .infinity)
        .background(backgroundStyle)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(ChatTheme.separator)
        }
    }

    @ViewBuilder
    private var searchField: some View {
        #if os(visionOS)
        if style == .vision {
            searchControls
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous), displayMode: .always)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 12)
        } else {
            touchSearchField
        }
        #else
        touchSearchField
        #endif
    }

    private var touchSearchField: some View {
        searchControls
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .appChromedContainer(cornerRadius: 18, interactive: true, shadowOpacity: 0.42)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 8)
    }

    private var searchControls: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search Chats", text: $searchText)
                .textFieldStyle(.plain)
                #if os(iOS) || os(tvOS)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                #endif

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear Search"))
            }
        }
    }

    private var backgroundStyle: some ShapeStyle {
        switch style {
        case .touch:
            return .ultraThinMaterial
        case .vision:
            return .bar
        }
    }
}
