import SwiftUI
import AppKit

struct SettingsView: View {
    private enum SettingsPage: CaseIterable, Identifiable {
        case general
        case layout
        case appearance

        var id: String {
            switch self {
            case .general:
                return "general"
            case .layout:
                return "layout"
            case .appearance:
                return "appearance"
            }
        }
    }

    @EnvironmentObject private var appSettings: SettingsStore
    @EnvironmentObject private var instanceStore: ComponentStore
    @EnvironmentObject private var desktopAutoMoveStore: DesktopAutoMoveStore
    @StateObject private var shortcutManager = PanelShortcutManager.shared

    @State private var selectedPage: SettingsPage = .general

    var body: some View {
        VStack(spacing: 12) {
            pageSwitcher

            Group {
                if selectedPage == .general {
                    generalPage
                } else if selectedPage == .layout {
                    layoutPage
                } else {
                    appearancePage
                }
            }
        }
        .frame(width: 340, height: 480)
        .onAppear {
            appSettings.refreshLaunchAtLoginStatus()
        }
        .onDisappear {
            shortcutManager.stopRecording()
        }
    }

    private var pageSwitcher: some View {
        HStack(spacing: 6) {
            pageButton(.general)
            pageButton(.layout)
            pageButton(.appearance)
        }
        .padding(3)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func pageButton(_ page: SettingsPage) -> some View {
        let isSelected = selectedPage == page

        return Button {
            selectedPage = page
        } label: {
            Text(title(for: page))
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.white.opacity(0.22) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white.opacity(isSelected ? 0.22 : 0), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var generalPage: some View {
        ScrollView {
            VStack(spacing: 10) {
                settingsCard {
                    menuPickerRow(title: appSettings.t("folbox.settings.language"), selection: $appSettings.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    toggleRow(title: appSettings.t("folbox.settings.launch_at_login"), isOn: launchAtLoginBinding)
                }

                settingsCard {
                    shortcutRecorderRow
                    toggleRow(title: appSettings.t("folbox.settings.single_click_opens_file"), isOn: $appSettings.singleClickOpensFile)
                    SliderRow(
                        title: appSettings.t("folbox.settings.animation_duration"),
                        value: $appSettings.panelAnimationDuration,
                        range: 0.1 ... 0.5,
                        valueText: String(format: "%.2fs", appSettings.panelAnimationDuration)
                    )
                }

                settingsCard {
                    toggleRow(title: appSettings.t("folbox.settings.custom_storage_location"), isOn: customStorageToggleBinding)

                    if appSettings.useCustomStorageLocation {
                        HStack(spacing: 10) {
                            Text(appSettings.customStorageDisplayPath ?? appSettings.t("folbox.settings.not_selected"))
                                .font(.system(size: 13, weight: .regular))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 12)
                            Button(appSettings.t("folbox.settings.change")) {
                                chooseCustomStorageFolder()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }

                    toggleRow(title: appSettings.t("folbox.settings.auto_move_desktop_files"), isOn: autoMoveToggleBinding)

                    if desktopAutoMoveStore.isEnabled {
                        HStack(spacing: 10) {
                            Text(desktopAutoMoveStore.destinationDisplayPath ?? appSettings.t("folbox.settings.not_selected"))
                                .font(.system(size: 13, weight: .regular))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 12)
                            Button(appSettings.t("folbox.settings.change")) {
                                chooseAutoMoveDestinationFolder(enableAfterChoosing: false)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                }
                sponsorSupportButton
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
            .padding(.bottom, 6)
        }
        .background(SettingsFormScrollConfigurator())
    }

    private var sponsorSupportButton: some View {
        Button {
            openSponsorPage()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 13, weight: .bold))
                Text(appSettings.t("folbox.settings.sponsor_support"))
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 30)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.24, green: 0.59, blue: 0.98),
                    Color(red: 0.10, green: 0.36, blue: 0.86)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var layoutPage: some View {
        ScrollView {
            VStack(spacing: 10) {
                settingsCard {
                    menuPickerRow(title: appSettings.t("folbox.settings.title_position"), selection: $appSettings.titlePosition) {
                        ForEach(TitlePosition.allCases) { position in
                            Text(position.displayName).tag(position)
                        }
                    }
                    menuPickerRow(title: appSettings.t("folbox.settings.file_list_display"), selection: $appSettings.fileListDisplayMode) {
                        ForEach(FileListDisplayMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    menuPickerRow(title: appSettings.t("folbox.settings.expand_direction"), selection: $appSettings.panelExpandDirection) {
                        ForEach(PanelExpandDirection.allCases) { direction in
                            Text(direction.displayName).tag(direction)
                        }
                    }
                    menuPickerRow(title: appSettings.t("folbox.settings.scroll_behavior"), selection: $appSettings.panelScrollMode) {
                        ForEach(PanelScrollMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    SliderRow(
                        title: appSettings.t("folbox.settings.collapsed_columns"),
                        value: gridColumnsBinding,
                        range: Double(GridMetrics.minimumCount) ... Double(GridMetrics.maximumCount),
                        step: 1,
                        valueText: "\(appSettings.gridColumns)"
                    )
                    SliderRow(
                        title: appSettings.t("folbox.settings.expanded_columns"),
                        value: expandedColumnsBinding,
                        range: Double(GridMetrics.minimumCount) ... Double(GridMetrics.maximumCount),
                        step: 1,
                        valueText: "\(appSettings.expandedColumns)"
                    )
                    SliderRow(
                        title: appSettings.t("folbox.settings.expanded_rows"),
                        value: gridRowsBinding,
                        range: Double(GridMetrics.minimumCount) ... Double(GridMetrics.maximumCount),
                        step: 1,
                        valueText: "\(appSettings.gridRows)"
                    )
                    SliderRow(
                        title: appSettings.t("folbox.settings.file_tile_size"),
                        value: fileTileSizeBinding,
                        range: Double(GridMetrics.minimumTileSize) ... Double(GridMetrics.maximumTileSize),
                        step: 4,
                        valueText: "\(appSettings.fileTileSize)"
                    )
                    .onChange(of: appSettings.fileTileSize) {
                        DesktopPanelController.shared.refreshPanelLayouts(animated: false)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
        }
        .onChange(of: appSettings.gridColumns) {
            DesktopPanelController.shared.refreshPanelLayouts(animated: false)
        }
        .onChange(of: appSettings.fileListDisplayMode) {
            DesktopPanelController.shared.refreshPanelLayouts(animated: false)
        }
        .background(SettingsFormScrollConfigurator())
    }

    private var appearancePage: some View {
        ScrollView {
            VStack(spacing: 10) {
                settingsCard {
                    SliderRow(
                        title: appSettings.t("folbox.settings.collapsed_background_opacity"),
                        value: $appSettings.collapsedBackgroundOpacity,
                        range: 0.0 ... 1.0,
                        valueText: String(format: "%.0f%%", appSettings.collapsedBackgroundOpacity * 100)
                    )
                    SliderRow(
                        title: appSettings.t("folbox.settings.expanded_background_opacity"),
                        value: $appSettings.expandedBackgroundOpacity,
                        range: 0.0 ... 1.0,
                        valueText: String(format: "%.0f%%", appSettings.expandedBackgroundOpacity * 100)
                    )
                    SliderRow(
                        title: appSettings.t("folbox.settings.component_opacity"),
                        value: $appSettings.componentOpacity,
                        range: 0.3 ... 1.0,
                        valueText: String(format: "%.0f%%", appSettings.componentOpacity * 100)
                    )
                    SliderRow(
                        title: appSettings.t("folbox.settings.panel_blur"),
                        value: $appSettings.panelBlurIntensity,
                        range: 0.0 ... 1.0,
                        valueText: String(format: "%.0f%%", appSettings.panelBlurIntensity * 100)
                    )
                    toggleRow(title: appSettings.t("folbox.settings.show_file_tile_border"), isOn: $appSettings.showFileTileBorder)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
        }
        .background(SettingsFormScrollConfigurator())
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func menuPickerRow<Selection: Hashable, Content: View>(
        title: String,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 12)
            Picker("", selection: selection) {
                content()
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 12)
            SettingsToggleSwitch(isOn: isOn)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var fileTileSizeBinding: Binding<Double> {
        Binding(
            get: { Double(appSettings.fileTileSize) },
            set: { appSettings.fileTileSize = Int($0.rounded()) }
        )
    }

    private var gridColumnsBinding: Binding<Double> {
        Binding(
            get: { Double(appSettings.gridColumns) },
            set: { appSettings.gridColumns = Int($0.rounded()) }
        )
    }

    private var expandedColumnsBinding: Binding<Double> {
        Binding(
            get: { Double(appSettings.expandedColumns) },
            set: { appSettings.expandedColumns = Int($0.rounded()) }
        )
    }

    private var gridRowsBinding: Binding<Double> {
        Binding(
            get: { Double(appSettings.gridRows) },
            set: { appSettings.gridRows = Int($0.rounded()) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { appSettings.launchAtLogin },
            set: { appSettings.setLaunchAtLoginEnabled($0) }
        )
    }

    private var shortcutRecorderRow: some View {
        HStack(spacing: 10) {
            Text(appSettings.t("folbox.settings.shortcut"))
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 12)
            if hasConfiguredPanelShortcut {
                Button(appSettings.t("folbox.common.clear")) {
                    shortcutManager.clearShortcut()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            }
            Button {
                if shortcutManager.isRecording {
                    shortcutManager.stopRecording()
                } else {
                    shortcutManager.beginRecording {
                        shortcutManager.refreshRegistration()
                    }
                }
            } label: {
                Text(shortcutManager.isRecording ? appSettings.t("folbox.settings.press_shortcut") : shortcutManager.shortcutDisplay)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var hasConfiguredPanelShortcut: Bool {
        let shortcut = HotKeyManager.Shortcut(
            keyCode: CGKeyCode(appSettings.panelShortcutKeyCode),
            modifiers: HotKeyManager.normalizedFlags(rawValue: appSettings.panelShortcutModifierFlagsRaw)
        )
        return shortcut.isConfigured
    }

    private var customStorageToggleBinding: Binding<Bool> {
        Binding(
            get: { appSettings.useCustomStorageLocation },
            set: { newValue in
                if newValue {
                    chooseCustomStorageFolder()
                } else {
                    let oldRoot = instanceStore.currentStorageRootURL
                    appSettings.clearCustomStorageLocation()
                    instanceStore.relocateStorage(from: oldRoot, to: instanceStore.currentStorageRootURL)
                }
            }
        )
    }

    private var autoMoveToggleBinding: Binding<Bool> {
        Binding(
            get: { desktopAutoMoveStore.isEnabled },
            set: { newValue in
                if newValue {
                    chooseAutoMoveDestinationFolder(enableAfterChoosing: true)
                } else {
                    desktopAutoMoveStore.isEnabled = false
                }
            }
        )
    }

    private func chooseCustomStorageFolder() {
        let panel = NSOpenPanel()
        panel.title = appSettings.t("folbox.settings.choose_storage_folder")
        panel.prompt = appSettings.t("folbox.common.choose")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = instanceStore.currentStorageRootURL

        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let oldRoot = instanceStore.currentStorageRootURL
        guard appSettings.setCustomStorageURL(url) else { return }
        instanceStore.relocateStorage(from: oldRoot, to: instanceStore.currentStorageRootURL)
    }

    private func chooseAutoMoveDestinationFolder(enableAfterChoosing: Bool) {
        let panel = NSOpenPanel()
        panel.title = appSettings.t("folbox.settings.choose_auto_move_folder")
        panel.prompt = appSettings.t("folbox.common.choose")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = instanceStore.currentStorageRootURL

        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let url = panel.url else {
            if enableAfterChoosing {
                desktopAutoMoveStore.isEnabled = false
            }
            return
        }

        guard desktopAutoMoveStore.setDestinationURL(url) else {
            if enableAfterChoosing {
                desktopAutoMoveStore.isEnabled = false
            }
            return
        }

        if enableAfterChoosing {
            desktopAutoMoveStore.isEnabled = true
        }
    }

    private func openSponsorPage() {
        guard let url = URL(string: AppDefaults.AppInfo.sponsorURLString) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func title(for page: SettingsPage) -> String {
        switch page {
        case .general:
            return appSettings.t("folbox.settings.page.general")
        case .layout:
            return appSettings.t("folbox.settings.page.layout")
        case .appearance:
            return appSettings.t("folbox.settings.page.appearance")
        }
    }
}

private struct SettingsFormScrollConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsFormScrollFinderView {
        SettingsFormScrollFinderView()
    }

    func updateNSView(_ nsView: SettingsFormScrollFinderView, context: Context) {
        nsView.applyConfiguration()
    }
}

private final class SettingsFormScrollFinderView: NSView {
    override var intrinsicContentSize: NSSize { .zero }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyConfiguration()
    }

    override func layout() {
        super.layout()
        applyConfiguration()
    }

    fileprivate func applyConfiguration() {
        var view = superview
        while let current = view {
            if let scrollView = current as? NSScrollView {
                if scrollView.scrollerStyle != .overlay {
                    scrollView.scrollerStyle = .overlay
                }
                let inset = NSEdgeInsets(top: 8, left: 0, bottom: 10, right: 0)
                let currentInset = scrollView.contentInsets
                if currentInset.top != inset.top ||
                    currentInset.left != inset.left ||
                    currentInset.bottom != inset.bottom ||
                    currentInset.right != inset.right {
                    scrollView.contentInsets = inset
                }
                return
            }
            view = current.superview
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    let valueText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 12)
                Text(valueText)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if let step {
                Slider(value: $value, in: range, step: step)
                    .controlSize(.small)
            } else {
                Slider(value: $value, in: range)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct SettingsToggleSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn ? Color(nsColor: .controlAccentColor) : Color(nsColor: .quaternaryLabelColor))
                    .frame(width: 34, height: 20)
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .padding(2)
                    .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 0.5)
            }
            .animation(.easeInOut(duration: 0.16), value: isOn)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(AppLocalization.string("folbox.accessibility.toggle")))
        .accessibilityValue(Text(isOn ? AppLocalization.string("folbox.accessibility.on") : AppLocalization.string("folbox.accessibility.off")))
    }
}
