//
//  GeneralSettingsView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/5/12.
//

import SwiftUI
import ChocofordUI
#if DEBUG && canImport(TipKit)
import TipKit
#endif
#if os(macOS) && !APP_STORE
import Sparkle
#endif

enum FolderStructureStyle: Int {
    case disclosureGroup
    case tree
}

private struct FolderChildren: Identifiable, Hashable {
    var id = UUID()
}

struct GeneralSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.alertToast) private var alertToast
#if os(macOS) && !APP_STORE
    @EnvironmentObject var updateChecker: UpdateChecker
#endif
    @EnvironmentObject var appPreference: AppPreference
    
    @AppStorage("DisableCloudSync") var isICloudDisabled: Bool = false
    
    @AppStorage("FolderStructureStyle") var folderStructStyle: FolderStructureStyle = .disclosureGroup
    
    @State private var isDisclosureGroupUnspportedAlertPresented = false
    struct DisclosureGroupUnspportedError: LocalizedError {
        var errorDescription: String? {
            "Disclosure Group Style is unavailable below macOS 13.0."
        }
    }

    var body: some View {
        SettingsFormContainer {
            content()
        }
    }
    
    @ViewBuilder
    private func content() -> some View {
        Section {
            settingCellView(.localizable(.settingsAppAppearanceName)) {
                HStack(spacing: 16) {
                    RadioGroup(selected: $appPreference.appearance) { option, isOn in
                        RadioButton(isOn: isOn) {
                            Text(option.text)
                        }
                    }
                }
            }
            settingCellView(.localizable(.settingsExcalidrawAppearanceName)) {
                HStack(spacing: 16) {
                    RadioGroup(selected: $appPreference.excalidrawAppearance) { option, isOn in
                        RadioButton(isOn: isOn) {
                            Text(option.text)
                        }
                    }
                }
            }
        } header: {
            if #available(macOS 14.0, *) {
                Text(.localizable(.settingsAppAppearanceName))
            } else {
                Text(.localizable(.settingsAppAppearanceName))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        
        // Folder structure UI
        Section {
            HStack {
                Text(.localizable(.settingsFolderStructureStyleTitle))
                Spacer()
                Picker(.localizable(.settingsFolderStructureStyleTitle), selection: $folderStructStyle) {
                    Text(.localizable(.settingsFolderStructureStyleDisclosureGroup)).tag(FolderStructureStyle.disclosureGroup)
                    Text(.localizable(.settingsFolderStructureStyleTreeStructure)).tag(FolderStructureStyle.tree)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .onChange(of: folderStructStyle) { newValue in
                    if #available(macOS 13.0, *) { } else {
                        if newValue == .disclosureGroup {
                            isDisclosureGroupUnspportedAlertPresented.toggle()
                            folderStructStyle = .tree
                        }
                    }
                }
                .alert(
                    isPresented: $isDisclosureGroupUnspportedAlertPresented,
                    error: DisclosureGroupUnspportedError()
                ) {
                    
                }
            }
        } footer: {
            HStack {
                VStack(spacing: 10) {
                    Text(.localizable(.settingsFolderStructureDisclosureGroupStyleTitle)).font(.headline)
                    VStack(alignment: .leading, spacing: 4) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemSymbol: .chevronDown).font(.footnote)
                                Text(.localizable(.generalFolderName))
                            }
                            
                            VStack(spacing: 4) {
                                Text(.localizable(.generalSubfolderName))
                                Text(.localizable(.generalSubfolderName))
                            }
                            .padding(.leading, 24)
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemSymbol: .chevronDown).font(.footnote).opacity(0)
                            Text(.localizable(.generalFolderName))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: 160)
                
                Divider()
                
                VStack(spacing: 10) {
                    let children: [FolderChildren] = [FolderChildren(), FolderChildren()]
                    let children2: [FolderChildren] = []
                    Text(.localizable(.settingsFolderStructureTreeStructureStyleTitle)).font(.headline)
                    VStack(alignment: .leading, spacing: 4) {
                        VStack(alignment: .leading, spacing: 0) {
                            TreeStructureView(children: children) {
                                Text(.localizable(.generalFolderName))
                            } childView: { child in
                                TreeStructureView(children: children2) {
                                    Text(.localizable(.generalSubfolderName))
                                } childView: { child in
                                    
                                }
                            }
                        }
                        TreeStructureView(children: children) {
                            Text(.localizable(.generalFolderName)).padding(.vertical, 4)
                        } childView: { _ in
                            
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: 160)
            }
            .foregroundStyle(.secondary)
        }
        
#if DEBUG
        Section {
            let containerShape = RoundedRectangle(cornerRadius: 8)
            HStack(alignment: .top, spacing: 20) {
                Text("Sidebar").font(.headline).foregroundStyle(.secondary)
                Spacer()
                RadioGroup(selected: $appPreference.sidebarLayout) { option, isOn in
                    Image(option.imageName("Sidebar"))
                        .resizable()
                        .scaledToFit()
                        .frame(height: 120)
                        .clipShape(containerShape)
                        .padding(2)
                        .overlay {
                            if isOn.wrappedValue {
                                containerShape.stroke(Color.accentColor.opacity(0.5), lineWidth: 4)
                            }
                        }
                        .onTapGesture {
                            isOn.wrappedValue = true
                        }
                }
            }
            
            HStack(alignment: .top, spacing: 20) {
                Text("Inspector").font(.headline).foregroundStyle(.secondary)
                Spacer()
                RadioGroup(selected: $appPreference.inspectorLayout) { option, isOn in
                    Image(option.imageName("Inspector"))
                        .resizable()
                        .scaledToFit()
                        .frame(height: 120)
                        .clipShape(containerShape)
                        .padding(2)
                        .overlay {
                            if isOn.wrappedValue {
                                containerShape.stroke(Color.accentColor.opacity(0.5), lineWidth: 4)
                            }
                        }
                        .onTapGesture {
                            isOn.wrappedValue = true
                        }
                }
            }
        } header: {
            Text("Layout")
        }

        Section {
            HStack {
                Text("Feature Tips")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    resetFeatureTips()
                } label: {
                    Label("Reset Tips", systemImage: "lightbulb")
                }
            }
        } header: {
            Text("Debug")
        }
#endif
        
#if os(macOS) && !APP_STORE
        Section {
            Toggle(.localizable(.settingsUpdatesAutoCheckLabel), isOn: $updateChecker.automaticallyChecksForUpdates)
                .disabled(!updateChecker.canCheckForUpdates)
        } header: {
            if #available(macOS 14.0, *) {
                Text(.localizable(.settingsUpdateHeadline))
            } else {
                Text(.localizable(.settingsUpdateHeadline))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } footer: {
            HStack {
                Spacer()
                Button {
                    updateChecker.updater?.checkForUpdates()
                } label: {
                    Text(.localizable(.settingsUpdatesButtonCheck))
                }
            }
        }
#endif // os(macOS) && !APP_STORE
        
        Section {
            Toggle(
                .localizable(.settingsICloudToggleDisable),
                isOn: Binding {
                    FileManager.default.ubiquityIdentityToken == nil ||
                    isICloudDisabled
                } set: { disabled in
                    isICloudDisabled = disabled
                }
            )
            .modifier(ToggleICloudSyncingModifier())
        } header: {
            Text(localizable: .settingsICloudTitle)
        }
        
        Section {} footer: {
            AsyncButton {
                try await PersistenceController.shared.refreshIndices()
            } label: {
                Text(localizable: .settingsButtonRefreshSpotlightIndices)
            }
        }
    }
    
    @ViewBuilder
    func settingCellView<T: View, V: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder trailing: @escaping () -> T,
        @ViewBuilder content: (() -> V) = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .fontWeight(.medium)
                Spacer()
                trailing()
            }
            
            content()
        }
    }

#if DEBUG
    private func resetFeatureTips() {
#if canImport(TipKit)
        if #available(macOS 14.0, iOS 17.0, *) {
            do {
                try Tips.resetDatastore()
                FeatureDiscoveryTips.configureIfAvailable()
                alertToast(.init(
                    displayMode: .hud,
                    type: .complete(.green),
                    title: "Tips reset"
                ))
            } catch {
                alertToast(error)
            }
        }
#endif
    }
#endif
}

#if DEBUG
#Preview {
    GeneralSettingsView()
        .environmentObject(AppPreference())
#if os(macOS) && !APP_STORE
        .environmentObject(UpdateChecker())
#endif
}


#Preview {
    if #available(macOS 13.0, *) {
        Form {
            
        }
        .formStyle(.grouped)
        .environmentObject(AppPreference())
    }
}
#endif
