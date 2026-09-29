import SwiftUI
import AppKit

struct ComponentConfigurationView: View {
    @EnvironmentObject private var instanceStore: ComponentStore
    @Environment(\.dismiss) private var dismiss

    let mode: ComponentConfigurationMode
    let instanceID: UUID?
    var onFinish: (() -> Void)?
    var onPreferredSizeChange: ((CGSize) -> Void)?

    @State private var name = ""
    @State private var styleColorHex = AppDefaults.Component.styleColorHex
    @State private var customCollapsedColumns: Int?
    @State private var hasLoadedEditData = false
    @State private var showDeleteConfirmation = false
    @State private var showMoveFilesConfirmation = false
    @State private var deleteAlertMessage = ""
    @State private var showDeleteAlert = false

    private var primaryButtonTitle: String {
        mode == .create ? t("folbox.common.create") : t("folbox.common.save")
    }

    private var editTarget: ComponentInstance? {
        guard let instanceID else {
            return nil
        }

        return instanceStore.instance(with: instanceID)
    }

    private var editFileCount: Int {
        editTarget?.filePaths.count ?? 0
    }

    private var deleteTargetName: String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
            return cleaned
        }
        if let targetName = editTarget?.name, !targetName.isEmpty {
            return targetName
        }
        return t("folbox.component_config.this_component")
    }

    private var useCustomCollapsedColumnsBinding: Binding<Bool> {
        Binding(
            get: { customCollapsedColumns != nil },
            set: { enabled in
                if enabled {
                    customCollapsedColumns = GridMetrics.clamp(customCollapsedColumns ?? SettingsStore.shared.gridColumns)
                } else {
                    customCollapsedColumns = nil
                }
            }
        )
    }

    private var customCollapsedColumnsSliderBinding: Binding<Double> {
        Binding(
            get: { Double(GridMetrics.clamp(customCollapsedColumns ?? SettingsStore.shared.gridColumns)) },
            set: { customCollapsedColumns = GridMetrics.clamp(Int($0.rounded())) }
        )
    }

    private var customCollapsedColumnsValueText: String {
        "\(GridMetrics.clamp(customCollapsedColumns ?? SettingsStore.shared.gridColumns))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField(t("folbox.component_config.name_placeholder"), text: $name)
                .textFieldStyle(.roundedBorder)

            ColorPickerField(hexValue: $styleColorHex)

            VStack(alignment: .leading, spacing: 8) {
                Toggle(t("folbox.component_config.use_custom_collapsed_columns"), isOn: useCustomCollapsedColumnsBinding)

                if customCollapsedColumns != nil {
                    HStack {
                        Text(t("folbox.settings.collapsed_columns"))
                        Spacer()
                        Text(customCollapsedColumnsValueText)
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: customCollapsedColumnsSliderBinding,
                        in: Double(GridMetrics.minimumCount) ... Double(GridMetrics.maximumCount),
                        step: 1
                    )
                }
            }

            HStack {
                if mode == .edit {
                    Button(t("folbox.common.delete"), role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .disabled(editTarget == nil)
                    .alert(t("folbox.component_config.delete_title"), isPresented: $showDeleteConfirmation) {
                        Button(t("folbox.common.cancel"), role: .cancel) {}
                        Button(t("folbox.common.confirm"), role: .destructive) {
                            deleteInstance()
                        }
                    } message: {
                        Text(t("folbox.component_config.delete_message", deleteTargetName))
                    }
                }

                Spacer()

                Button(t("folbox.common.cancel")) {
                    close()
                }
                .keyboardShortcut(.cancelAction)

                Button(primaryButtonTitle) {
                    createOrSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 380)
        .onAppear {
            populateEditFieldsIfNeeded()
            notifyPreferredSizeChange()
        }
        .onChange(of: instanceID) {
            hasLoadedEditData = false
            populateEditFieldsIfNeeded()
            notifyPreferredSizeChange()
        }
        .onChange(of: customCollapsedColumns != nil) {
            notifyPreferredSizeChange()
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ComponentConfigurationViewSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(ComponentConfigurationViewSizeKey.self) { size in
            onPreferredSizeChange?(size)
        }
        .alert(t("folbox.component_config.delete_blocked_title"), isPresented: $showDeleteAlert) {
            Button(t("folbox.common.ok"), role: .cancel) {}
        } message: {
            Text(deleteAlertMessage)
        }
        .alert(t("folbox.component_config.move_files_title"), isPresented: $showMoveFilesConfirmation) {
            Button(t("folbox.common.cancel"), role: .cancel) {}
            Button(t("folbox.common.confirm"), role: .destructive) {
                exportFilesAndDeleteIfNeeded()
            }
        } message: {
            Text(t("folbox.component_config.move_files_message"))
        }
    }

    private func createOrSave() {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else {
            return
        }

        if mode == .create {
            let created = instanceStore.createInstance(
                name: cleanedName,
                styleColorHex: styleColorHex,
                customCollapsedColumns: customCollapsedColumns
            )
            DesktopPanelController.shared.showPanel(for: created.id)
        } else if let instanceID {
            instanceStore.updateInstance(
                id: instanceID,
                name: cleanedName,
                styleColorHex: styleColorHex,
                customCollapsedColumns: customCollapsedColumns
            )
        }

        close()
    }

    private func deleteInstance() {
        if editFileCount > 0 {
            showMoveFilesConfirmation = true
            return
        }

        guard let instanceID else {
            return
        }

        if instanceStore.deleteInstanceIfEmpty(id: instanceID) {
            close()
        }
    }

    private func exportFilesAndDeleteIfNeeded() {
        guard let instanceID else {
            return
        }

        guard let destinationURL = chooseExportDirectory() else {
            deleteAlertMessage = t("folbox.component_config.delete_cancelled_message")
            showDeleteAlert = true
            return
        }

        let exportedCount = instanceStore.exportAllFiles(instanceID: instanceID, to: destinationURL)
        if exportedCount < editFileCount {
            deleteAlertMessage = t("folbox.component_config.move_files_failed_message")
            showDeleteAlert = true
            return
        }

        if instanceStore.deleteInstanceIfEmpty(id: instanceID) {
            close()
            return
        }

        deleteAlertMessage = t("folbox.component_config.delete_failed_message")
        showDeleteAlert = true
    }

    private func close() {
        if let onFinish {
            onFinish()
        } else {
            dismiss()
        }
    }

    private func chooseExportDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.title = t("folbox.component_config.move_files_title")
        panel.message = t("folbox.component_config.move_files_picker_message")
        panel.prompt = t("folbox.component_config.move_files_prompt")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        NSApp.activate(ignoringOtherApps: true)

        if panel.runModal() == .OK {
            return panel.url
        }

        return nil
    }

    private func populateEditFieldsIfNeeded() {
        guard mode == .edit else {
            return
        }

        guard !hasLoadedEditData else {
            return
        }

        guard let target = editTarget else {
            return
        }

        name = target.name
        styleColorHex = target.styleColorHex
        customCollapsedColumns = target.customCollapsedColumns
        hasLoadedEditData = true
    }

    private func notifyPreferredSizeChange() {
        DispatchQueue.main.async {
            onPreferredSizeChange?(CGSize.zero)
        }
    }

    private func t(_ key: String, _ arguments: CVarArg...) -> String {
        AppLocalization.string(key, language: SettingsStore.shared.language, arguments: arguments)
    }
}

private struct ComponentConfigurationViewSizeKey: PreferenceKey {
    static var defaultValue: CGSize { .zero }

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct ColorPickerField: View {
    @Binding var hexValue: String

    @State private var color: Color = .blue
    @State private var hexText: String = ""
    @FocusState private var isHexFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ColorPicker("", selection: $color)
                    .labelsHidden()
                    .onChange(of: color) {
                        guard !isHexFieldFocused else { return }
                        hexText = color.hexString
                        hexValue = hexText
                    }

                TextField("#RRGGBB", text: $hexText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .focused($isHexFieldFocused)
                    .onChange(of: hexText) {
                        if let parsed = Color(hex: hexText) {
                            color = parsed
                            hexValue = hexText
                        }
                    }

                Spacer()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 10), spacing: 6) {
                ForEach(ColorPresets.accentColors, id: \.self) { presetHex in
                    Button {
                        guard let presetColor = Color(hex: presetHex) else { return }
                        color = presetColor
                        hexText = presetHex
                        hexValue = presetHex
                    } label: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: presetHex) ?? .secondary)
                            .frame(width: 20, height: 20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.primary.opacity(presetHex.caseInsensitiveCompare(hexValue) == .orderedSame ? 0.9 : 0), lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            color = Color(hex: hexValue) ?? .blue
            hexText = hexValue
        }
        .onChange(of: hexValue) {
            guard hexValue != hexText else { return }
            hexText = hexValue
            color = Color(hex: hexValue) ?? color
        }
    }
}
