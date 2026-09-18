import SwiftUI

#if os(macOS)
import AppKit
#endif

struct AboutView: View {
    static let windowID = "about"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedComponents: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                applicationHeader

                switch OpenSourceNotices.bundled {
                case .success(let notices):
                    VStack(alignment: .leading, spacing: 16) {
                        Text("\(ApplicationInformation.name) License")
                            .font(.title2.bold())
                        licenseText(notices.applicationLicense)
                            .padding(24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(licenseBackground, in: RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Open Source Software")
                            .font(.title2.bold())

                        VStack(spacing: 0) {
                            ForEach(notices.components) { component in
                                if component.id != notices.components.first?.id {
                                    Divider()
                                }
                                DisclosureGroup(isExpanded: expansionBinding(for: component)) {
                                    VStack(alignment: .leading, spacing: 16) {
                                        Link(destination: component.url) {
                                            Label("Project Website", systemImage: "arrow.up.right")
                                        }
                                        licenseText(component.notice)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 12)
                                    .padding(.bottom, 8)
                                } label: {
                                    ViewThatFits(in: .horizontal) {
                                        componentLabel(component, vertical: false)
                                        componentLabel(component, vertical: true)
                                    }
                                    .padding(.vertical, 8)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 6)
                            }
                        }
                        .background(licenseBackground, in: RoundedRectangle(cornerRadius: 12))
                    }
                case .failure:
                    ContentUnavailableView("Unable to load license information.", systemImage: "doc.text.magnifyingglass")
                }
            }
            .frame(maxWidth: 760)
            .padding(contentPadding)
            .frame(maxWidth: .infinity)
        }
        .background(pageBackground)
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 600)
        #else
        .navigationTitle(Text("About \(ApplicationInformation.name)"))
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func componentLabel(_ component: OpenSourceNotices.Component, vertical: Bool) -> some View {
        let layout = vertical
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            Text(verbatim: component.name)
                .fontWeight(.medium)
            if !vertical {
                Spacer(minLength: 8)
            }
            Text(verbatim: component.version)
                .foregroundStyle(.secondary)
        }
    }

    private var contentPadding: CGFloat {
        #if os(macOS)
        32
        #else
        20
        #endif
    }

    private var pageBackground: Color {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        PlatformColor.groupedBackground
        #endif
    }

    private var licenseBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        PlatformColor.secondaryGroupedBackground
        #endif
    }

    private var applicationHeader: some View {
        HStack(alignment: .top, spacing: 24) {
            #if os(macOS)
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            #endif

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: ApplicationInformation.name)
                        .font(.largeTitle.bold())
                    if let version = ApplicationInformation.version {
                        HStack(spacing: 4) {
                            Text("Version")
                            Text(verbatim: version)
                            if let build = ApplicationInformation.build {
                                Text(verbatim: "(\(build))")
                                    .accessibilityLabel(Text("Build"))
                                    .accessibilityValue(Text(verbatim: build))
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                Text("\(ApplicationInformation.name) is open source software, released under the MIT License.")
                    .fixedSize(horizontal: false, vertical: true)
                if let url = URL(string: "https://github.com/Lion-Wu/Voice-Chat") {
                    Link(destination: url) {
                        Label("View Source on GitHub", systemImage: "arrow.up.right")
                    }
                }
            }
        }
    }

    private func expansionBinding(for component: OpenSourceNotices.Component) -> Binding<Bool> {
        Binding(
            get: { expandedComponents.contains(component.id) },
            set: { isExpanded in
                withAnimation(reduceMotion ? nil : .default) {
                    if isExpanded {
                        expandedComponents.insert(component.id)
                    } else {
                        expandedComponents.remove(component.id)
                    }
                }
            }
        )
    }

    private func licenseText(_ text: String) -> some View {
        Text(verbatim: text.trimmingCharacters(in: .whitespacesAndNewlines))
            #if os(macOS)
            .font(.system(size: 13))
            #else
            .font(.callout)
            #endif
            .lineSpacing(3)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.layoutDirection, .leftToRight)
    }
}

enum ApplicationInformation {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? Bundle.main.bundleURL.deletingPathExtension().lastPathComponent
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
}

private struct OpenSourceNotices: Sendable {
    static let bundled: Result<OpenSourceNotices, Error> = Result {
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(Manifest.self, from: resourceData("OpenSourceNotices", extension: "json"))
        let resolved = try decoder.decode(ResolvedPackages.self, from: resourceData("Package", extension: "resolved"))
        let license = try String(decoding: resourceData("LICENSE", extension: nil), as: UTF8.self)
        let components = try manifest.components.map { entry in
            let version: String
            switch (entry.version, entry.packageIdentity) {
            case (.some(let localVersion), .none):
                version = localVersion
            case (.none, .some(let identity)):
                guard let pin = resolved.pins.first(where: { $0.identity == identity }) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                #if os(visionOS)
                version = entry.visionOSVersion ?? pin.state.displayVersion
                #else
                version = pin.state.displayVersion
                #endif
            default:
                throw CocoaError(.fileReadCorruptFile)
            }
            return Component(name: entry.name, version: version, url: entry.url, notice: entry.notice)
        }
        // Reflow the application's plain-text MIT paragraphs for the available width.
        let applicationLicense = license.components(separatedBy: "\n\n")
            .map { $0.split(whereSeparator: \.isNewline).joined(separator: " ") }
            .joined(separator: "\n\n")
        return OpenSourceNotices(applicationLicense: applicationLicense, components: components)
    }

    let applicationLicense: String
    let components: [Component]

    private static func resourceData(_ name: String, extension fileExtension: String?) throws -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    struct Component: Identifiable, Sendable {
        var id: String { name }
        let name: String
        let version: String
        let url: URL
        let notice: String
    }

    private struct Manifest: Decodable {
        let components: [Entry]

        struct Entry: Decodable {
            let name: String
            let version: String?
            let packageIdentity: String?
            let visionOSVersion: String?
            let url: URL
            let notice: String
        }
    }

    private struct ResolvedPackages: Decodable {
        let pins: [Pin]

        struct Pin: Decodable {
            let identity: String
            let state: State

            struct State: Decodable {
                let version: String?
                let revision: String

                var displayVersion: String {
                    version ?? String(revision.prefix(7))
                }
            }
        }
    }
}
