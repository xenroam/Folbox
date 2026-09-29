import SwiftUI
import AppKit

struct AboutView: View {
    @EnvironmentObject private var appSettings: SettingsStore
    var onPreferredSizeChange: ((CGSize) -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 120, height: 120)

            Text(AppDefaults.AppInfo.projectName())
                .font(.title)
                .fontWeight(.semibold)

            Text(AppDefaults.AppInfo.versionAndBuild())
                .foregroundStyle(.secondary)

            Text(appSettings.t("folbox.about.description"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    openGitHub()
                } label: {
                    Label(appSettings.t("folbox.about.github"), systemImage: "chevron.left.slash.chevron.right")
                }

                Button {
                    openFeedback()
                } label: {
                    Label(appSettings.t("folbox.about.feedback"), systemImage: "bubble.left.and.bubble.right")
                }
            }

            HStack(spacing: 10) {
                Button(appSettings.t("folbox.about.privacy")) {
                    openPrivacyPolicy()
                }
                .buttonStyle(.link)

                Button(appSettings.t("folbox.about.disclaimer")) {
                    openDisclaimer()
                }
                .buttonStyle(.link)
            }

            Text(appSettings.t("folbox.about.copyright", String(currentYear)))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 380, minHeight: 250)
        .onAppear {
            notifyPreferredSizeChange()
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: AboutViewSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(AboutViewSizeKey.self) { size in
            onPreferredSizeChange?(size)
        }
    }

    private func notifyPreferredSizeChange() {
        DispatchQueue.main.async {
            onPreferredSizeChange?(CGSize.zero)
        }
    }

    private var appIcon: NSImage {
        NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    private func openGitHub() {
        guard let url = URL(string: "https://github.com/xenroam/Folbox") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openFeedback() {
        guard let url = URL(string: "https://github.com/xenroam/Folbox/issues/new") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openPrivacyPolicy() {
        guard let url = URL(string: "https://xenroam.github.io/Folbox/PRIVACY.md") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openDisclaimer() {
        guard let url = URL(string: "https://xenroam.github.io/Folbox/DISCLAIMER.md") else { return }
        NSWorkspace.shared.open(url)
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }
}

private struct AboutViewSizeKey: PreferenceKey {
    static var defaultValue: CGSize { .zero }

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
