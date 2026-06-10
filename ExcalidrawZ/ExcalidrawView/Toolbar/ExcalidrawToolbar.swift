//
//  ExcalidrawToolbar.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/8/10.
//

import SwiftUI
import Combine

import SFSafeSymbols
import ChocofordUI

#if canImport(UIKit)
import UIKit
#endif

struct ExcalidrawToolbar: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) private var alertToast
    @Environment(\.colorScheme) private var colorScheme
    
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var toolState: ToolState
    @EnvironmentObject var layoutState: LayoutState
    
#if canImport(AppKit)
    @State private var window: NSWindow?
#elseif canImport(UIKit)
    @State private var window: UIWindow?
#endif
    @State private var windowFrameCancellable: AnyCancellable?
    @State private var isApplePencilDisconnectConfirmationDialogPresented = false
    
    private var activeCoordinator: ExcalidrawCanvasView.Coordinator? {
        switch fileState.currentActiveFile {
            case .collaborationFile:
                fileState.excalidrawCollaborationWebCoordinator ?? toolState.excalidrawWebCoordinator
            default:
                fileState.excalidrawWebCoordinator ?? toolState.excalidrawWebCoordinator
        }
    }
    
    
    var body: some View {
        if fileState.currentActiveFile != nil {
            toolbar()
        }
    }
    
    @ViewBuilder
    private func toolbar() -> some View {
        toolbarContent()
            .animation(.smooth, value: toolState.activatedTool)
            .animation(.smooth, value: toolState.inDragMode)
            .onChange(of: toolState.activatedTool, debounce: 0.05) { newValue in
                if newValue == nil {
                    toolState.setActivedTool(.cursor)
                }
                
                if let tool = newValue {
                    let webCoordinator = toolState.excalidrawWebCoordinator
                    
                    if tool != webCoordinator?.lastTool {
                        Task {
                            do {
                                try await toolState.toggleTool(tool)
                            } catch {
                                alertToast(error)
                            }
                        }
                    }
                }
            }
    }
    
    @ViewBuilder
    private func toolbarContent() -> some View {
#if os(iOS)
        if horizontalSizeClass == .compact {
            compactContent()
        } else if containerHorizontalSizeClass != .compact, !toolState.inPenMode {
            HStack {
                compactContent()
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background {
                if #available(iOS 26.0, *) {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(.clear, in: Capsule())
                        .shadow(color: .gray.opacity(0.15), radius: colorScheme == .light ? 8 : 0, y: 4)
                } else if #available(macOS 14.0, iOS 17.0, *) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                        .stroke(.separator, lineWidth: 0.5)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                }
            }
        } else if toolState.inPenMode {
            HStack(spacing: 10) {
                Text("Pencil Mode")
            }
            .frame(maxWidth: 400)
            .padding(6)
            .background {
                if #available(macOS 14.0, iOS 17.0, *) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                        .stroke(.separator, lineWidth: 0.5)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                }
            }
        }
#elseif os(macOS)
        leadingTollsContent()
        
        ExcalidrawToolbarToolContainer { sizeClass in
            let pickerItems = toolbarPickerItems(for: sizeClass)

            HStack(spacing: 10) {
                ZStack {
                    Color.clear
                    if sizeClass == .dense {
                        denseContent()
                    } else {
                        segmentedPicker(
                            sizeClass: sizeClass,
                            primaryPickerItems: pickerItems.primary,
                            secondaryPickerItems: pickerItems.secondary
                        )
                    }
                }
            }
            
            
            if #available(macOS 26.0, iOS 26.0, *),
               !pickerItems.secondary.isEmpty,
               let tool = toolState.activatedTool,
               sizeClass != .dense {
                secondaryPickerItemsMenu(
                    tool: tool,
                    secondaryPickerItems: pickerItems.secondary
                )
            }
        }
        
        moreTools()
#endif
    }
    
    @ViewBuilder
    private func leadingTollsContent() -> some View {
        Button {
            toolState.toggleToolLock()
        } label: {
            SwiftUI.Group {
                if #available(macOS 14.0, iOS 17.0, *) {
                    Label(.localizable(.toolbarButtonLockToolLabel), systemSymbol: toolState.isToolLocked ? .lock : .lockOpen)
                        .contentTransition(.symbolEffect(.replace))
                } else {
                    Label(.localizable(.toolbarButtonLockToolLabel), systemSymbol: toolState.isToolLocked ? .lock : .lockOpen)
                }
            }
            .foregroundStyle(toolState.isToolLocked ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.primary))
            .animation(.default, value: toolState.isToolLocked)
        }
        .help("\(String(localizable: .toolbarButtonLockToolHelp)) - Q")
    }
    
    @State private var lastActivatedSecondaryTool: ExcalidrawTool?

    private func toolbarPickerItems(
        for sizeClass: ExcalidrawToolbarToolSizeClass
    ) -> (primary: [ExcalidrawTool], secondary: [ExcalidrawTool]) {
        switch sizeClass {
            case .dense:
                return ([], [])
            case .compact:
                return (
                    [.cursor, .rectangle, .diamond, .ellipse, .arrow, .line],
                    [.freedraw, .text, .image, .eraser, .laser, .lasso, .hand, .frame, .webEmbed, .magicFrame]
                )
            case .regular:
                return (
                    [.cursor, .rectangle, .diamond, .ellipse, .arrow, .line, .freedraw, .text, .image],
                    [.eraser, .laser, .lasso, .hand, .frame, .webEmbed, .magicFrame]
                )
            case .expanded:
                return (
                    [
                        .cursor,
                        .rectangle,
                        .diamond,
                        .ellipse,
                        .arrow,
                        .line,
                        .freedraw,
                        .text,
                        .image,
                        .eraser,
                        .laser,
                        .lasso,
                        .hand,
                        .frame,
                        .webEmbed,
                        .magicFrame,
                    ],
                    []
                )
        }
    }
    
    @ViewBuilder
    private func segmentedPicker(
        sizeClass: ExcalidrawToolbarToolSizeClass,
        primaryPickerItems: [ExcalidrawTool],
        secondaryPickerItems: [ExcalidrawTool],
        size: CGFloat = 20,
        withFooter: Bool = true
    ) -> some View {
        HStack(spacing: size / 2) {
            SegmentedPicker(selection: $toolState.activatedTool) {
                primaryToolPikcerItems(
                    primaryPickerItems,
                    size: size,
                    withFooter: withFooter
                )
            }
            .padding({
                if #available(macOS 26.0, iOS 26.0, *) {
                    .top
                } else {
                    .all
                }
            }(), {
                if #available(macOS 26.0, iOS 26.0, *) {
                    0
                } else {
                    size / 3
                }
            }())
            .background {
                if #available(macOS 26.0, iOS 26.0, *) {
                    
                } else if #available(macOS 14.0, iOS 17.0, *) {
                    RoundedRectangle(cornerRadius: size / 1.6)
                        .fill(.regularMaterial)
                        .stroke(.separator, lineWidth: 0.5)
                } else {
                    RoundedRectangle(cornerRadius: size / 1.6)
                        .fill(.regularMaterial)
                }
            }
            if #available(macOS 26.0, iOS 26.0, *) {
                
            } else if !secondaryPickerItems.isEmpty,
                      sizeClass != .expanded,
                      let tool = toolState.activatedTool {
                secondaryPickerItemsMenu(
                    tool: tool,
                    secondaryPickerItems: secondaryPickerItems,
                    size: size
                )
                    .buttonStyle(.borderless)
                    .padding(size / 3)
                    .background {
                        let isSelected = toolState.activatedTool != nil && secondaryPickerItems.contains(toolState.activatedTool!)
                        if #available(macOS 14.0, iOS 17.0, *) {
                            RoundedRectangle(cornerRadius: size / 1.6)
                                .fill(
                                    isSelected ? AnyShapeStyle(Color.accentColor.secondary) : AnyShapeStyle(Material.regularMaterial)
                                )
                                .stroke(.separator, lineWidth: 0.5)
                        } else {
                            RoundedRectangle(cornerRadius: size / 1.6)
                                .fill(
                                    isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.3)) : AnyShapeStyle(Material.regularMaterial)
                                )
                            RoundedRectangle(cornerRadius: size / 1.6)
                                .stroke(.secondary, lineWidth: 0.5)
                        }
                    }
                    .watch(value: toolState.activatedTool) { newValue in
                        if let newValue, secondaryPickerItems.contains(newValue) {
                            lastActivatedSecondaryTool = newValue
                        }
                    }
            }
        }
        .padding(.horizontal, {
            if #available(macOS 26.0, iOS 26.0, *) {
                6
            } else {
                0
            }
        }())
    }
    
    @ViewBuilder
    private func secondaryPickerItemsMenu(
        tool: ExcalidrawTool,
        secondaryPickerItems: [ExcalidrawTool],
        size: CGFloat = 20,
    ) -> some View {
        Menu {
            Picker(selection: $toolState.activatedTool) {
                ForEach(secondaryPickerItems, id: \.self) { tool in
                    densePickerItems(tool: tool)
                        .tag(tool)
                }
            } label: { }
                .pickerStyle(.inline)
        } label: {
            SegmentedToolPickerItemView(
                tool: {
                    if let lastActivatedSecondaryTool, secondaryPickerItems.contains(lastActivatedSecondaryTool) {
                        return lastActivatedSecondaryTool
                    } else {
                        return (secondaryPickerItems.contains(tool) ? tool : secondaryPickerItems.first!)
                    }
                }(),
                size: size,
                withFooter: false
            )
            .foregroundStyle(
                toolState.activatedTool != nil && secondaryPickerItems.contains(toolState.activatedTool!)
                ? AnyShapeStyle(Color.accentColor)
                : AnyShapeStyle(HierarchicalShapeStyle.primary)
            )
        } primaryAction: {
            if let lastActivatedSecondaryTool,
               secondaryPickerItems.contains(lastActivatedSecondaryTool) {
                toolState.setActivedTool(lastActivatedSecondaryTool)
            } else {
                toolState.setActivedTool(secondaryPickerItems.first)
            }
        }
        .menuIndicator(.visible)
    }
    
    @ViewBuilder
    private func primaryToolPikcerItems(
        _ primaryPickerItems: [ExcalidrawTool],
        size: CGFloat,
        withFooter: Bool
    ) -> some View {
        ForEach(primaryPickerItems, id: \.self) { tool in
            toolPickerItemView(tool: tool, size: size, withFooter: withFooter)
                .tag(tool)
        }
    }
    
    @ViewBuilder
    private func toolPickerItemView(
        tool: ExcalidrawTool,
        size: CGFloat,
        withFooter: Bool
    ) -> some View {
        SegmentedPickerItem(value: tool) {
            SegmentedToolPickerItemView(
                tool: tool,
                size: size,
                withFooter: withFooter
            )
        }
        .help(tool.help)
    }
    
    @ViewBuilder
    private func compactContent() -> some View {
        if toolState.inDragMode {
            compactDragModeControls
        } else if let activatedTool = toolState.activatedTool, activatedTool != .cursor {
            if containerHorizontalSizeClass == .compact {
                Text(activatedTool.localization).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 6)
                Button {
                    if activatedTool == .arrow {
                        Task {
                            try? await toolState.excalidrawWebCoordinator?.toggleToolbarAction(key: "\u{1B}")
                        }
                    }
                    toolState.setActivedTool(.cursor)
                } label: {
                    Label(.localizable(.generalButtonCancel), systemSymbol: .checkmark)
                }
                .modernButtonStyle(style: .glassProminent, shape: .circle)
            } else {
                HStack(spacing: 20) {
                    Text(activatedTool.localization).frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        if activatedTool == .arrow {
                            Task {
                                try? await toolState.excalidrawWebCoordinator?.toggleToolbarAction(key: "\u{1B}")
                            }
                        }
                        toolState.setActivedTool(.cursor)
                    } label: {
                        Label(.localizable(.generalButtonCancel), systemSymbol: .xmark)
                    }
                }
            }
        } else {
            HStack(spacing: 20) {
                Button {
                    toolState.setActivedTool(.freedraw)
                } label: {
                    Label(.localizable(.toolbarDraw), systemSymbol: .pencilAndOutline)
                }
                Spacer()
                Menu {
                    Button {
                        toolState.setActivedTool(.rectangle)
                    } label: {
                        Label(.localizable(.toolbarRectangle), systemSymbol: .rectangle)
                    }
                    Button {
                        toolState.setActivedTool(.diamond)
                    } label: {
                        Label(.localizable(.toolbarDiamond), systemSymbol: .diamond)
                    }
                    Button {
                        toolState.setActivedTool(.ellipse)
                    } label: {
                        Label(.localizable(.toolbarEllipse), systemSymbol: .circle)
                    }
                    Button {
                        toolState.setActivedTool(.arrow)
                    } label: {
                        Label(.localizable(.toolbarArrow), systemSymbol: .lineDiagonalArrow)
                    }
                    Button {
                        toolState.setActivedTool(.line)
                    } label: {
                        Label(.localizable(.toolbarLine), systemSymbol: .lineDiagonal)
                    }
                    Button {
                        toolState.setActivedTool(.text)
                    } label: {
                        Label(.localizable(.toolbarText), systemSymbol: .characterTextbox)
                    }
                    Button {
                        toolState.setActivedTool(.image)
                    } label: {
                        Label(.localizable(.toolbarInsertImage), systemSymbol: .photoOnRectangle)
                    }
                    
                    Divider()
                    
                    Button {
                        toolState.setActivedTool(.eraser)
                    } label: {
                        if #available(macOS 13.0, *) {
                            Label(.localizable(.toolbarEraser), systemSymbol: .eraser)
                        } else {
                            Label(.localizable(.toolbarEraser), systemSymbol: .pencilSlash)
                        }
                    }
                    Button {
                        toolState.setActivedTool(.laser)
                    } label: {
                        Label(.localizable(.toolbarLaser), systemSymbol: .cursorarrowRays)
                    }
                    Button {
                        toolState.setActivedTool(.frame)
                    } label: {
                        Label(.localizable(.toolbarFrame), systemSymbol: .grid)
                    }
                    Button {
                        toolState.setActivedTool(.webEmbed)
                    } label: {
                        Label(.localizable(.toolbarWebEmbed), systemSymbol: .chevronLeftForwardslashChevronRight)
                    }
                    Button {
                        toolState.setActivedTool(.magicFrame)
                    } label: {
                        Label(.localizable(.toolbarMagicFrame), systemSymbol: .wandAndStarsInverse)
                    }
                } label: {
                    if toolState.activatedTool == .cursor {
                        Label(.localizable(.toolbarShapesAndTools), systemSymbol: .squareOnCircle)
                    } else {
                        activeShape()
                            .foregroundStyle(Color.accentColor)
                    }
                }
#if os(iOS)
                .menuOrder(.fixed)
#endif
                
                Spacer()
                
                moreTools()
                
                Spacer()
                
                if toolState.activatedTool == .cursor {
                    if let activeCoordinator {
                        CursorModeTrailingButton(coordinator: activeCoordinator) {
                            toolState.setActivedTool(.hand)
                        }
                    } else {
                        Button {
                            toolState.setActivedTool(.hand)
                        } label: {
                            Text(.localizable(.generalButtonDone))
                        }
                    }
                } else {
                    Button {
                        toolState.setActivedTool(.cursor)
                    } label: {
                        Text(.localizable(.generalButtonCancel))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var compactDragModeControls: some View {
        compactStatusBar

        Spacer(minLength: 0)

        compactInspectorTabButton(
            tab: .preference,
            icon: .sliderHorizontal3,
            title: String(localizable: .canvasPreferencesTitle)
        )
        if shouldCollapseCompactInspectorTabs {
            compactInspectorTabButton(
                tab: .aiChat,
                icon: .sparkles,
                title: "AI Chat",
                action: toggleCompactAIChatPresentation
            )
            compactInspectorTabsMenu()
        } else {
            compactInspectorTabButton(
                tab: .search,
                icon: .magnifyingglass,
                title: String(localizable: .searchButtonTitle)
            )
            .keyboardShortcut("f", modifiers: .command)
            compactInspectorTabButton(
                tab: .library,
                icon: .book,
                title: String(localizable: .librariesTitle)
            )
            compactInspectorTabButton(
                tab: .history,
                icon: .clockArrowCirclepath,
                title: String(localizable: .checkpoints)
            )
            compactInspectorTabButton(
                tab: .aiChat,
                icon: .sparkles,
                title: "AI Chat",
                action: toggleCompactAIChatPresentation
            )
        }
        compactEditButton
    }

    @ViewBuilder
    private var compactStatusBar: some View {
#if os(iOS)
        if let activeFile = fileState.currentActiveFile {
            FileICloudSyncStatusIndicator(file: activeFile)
                .frame(width: 28, height: 28)
        }
#endif
    }

    private var shouldCollapseCompactInspectorTabs: Bool {
#if os(iOS)
        guard containerHorizontalSizeClass == .compact else { return false }
        return UIScreen.main.bounds.width < 390
#else
        return false
#endif
    }

    @ViewBuilder
    private var compactEditButton: some View {
        Button {
            if case .file(let file) = fileState.currentActiveFile, file.inTrash {
                layoutState.isResotreAlertIsPresented.toggle()
            } else {
                toolState.setActivedTool(.cursor)
            }
        } label: {
            Label(.localizable(.toolbarEdit), systemSymbol: .pencil)
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
        }
        .modernButtonStyle(style: .glassProminent, size: .small, shape: .circle)
        .help(String(localizable: .toolbarEdit))
    }

    @ViewBuilder
    private func compactInspectorTabButton(
        tab: LayoutState.InspectorTab,
        icon: SFSymbol,
        title: String,
        action: (() -> Void)? = nil
    ) -> some View {
        let isDisabled = compactInspectorTabIsDisabled(tab)
        let isActive = compactInspectorTabIsActive(tab)

        Button {
            guard !isDisabled else { return }
            if let action {
                action()
            } else {
                layoutState.toggleInspector(tab)
            }
        } label: {
            Label(title, systemSymbol: icon)
                .labelStyle(.iconOnly)
                .font(.system(size: 16))
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(title)
        .opacity(isDisabled && !isActive ? 0.55 : 1)
        .allowsHitTesting(!isDisabled)
    }

    @ViewBuilder
    private func compactInspectorTabsMenu() -> some View {
        Menu {
            compactInspectorTabMenuButton(
                tab: .search,
                icon: .magnifyingglass,
                title: String(localizable: .searchButtonTitle)
            )
            .keyboardShortcut("f", modifiers: .command)
            compactInspectorTabMenuButton(
                tab: .history,
                icon: .clockArrowCirclepath,
                title: String(localizable: .checkpoints)
            )
            compactInspectorTabMenuButton(
                tab: .library,
                icon: .book,
                title: String(localizable: .librariesTitle)
            )
        } label: {
            Label(.localizable(.generalButtonMore), systemSymbol: .ellipsis)
                .labelStyle(.iconOnly)
                .font(.system(size: 16))
                .foregroundStyle(compactCollapsedInspectorTabsContainActive ? Color.accentColor : Color.primary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help(String(localizable: .generalButtonMore))
#if os(iOS)
        .menuOrder(.fixed)
#endif
    }

    @ViewBuilder
    private func compactInspectorTabMenuButton(
        tab: LayoutState.InspectorTab,
        icon: SFSymbol,
        title: String
    ) -> some View {
        let isDisabled = compactInspectorTabIsDisabled(tab)
        Button {
            guard !isDisabled else { return }
            layoutState.toggleInspector(tab)
        } label: {
            Label(title, systemSymbol: icon)
        }
        .disabled(isDisabled)
    }

    private var compactCollapsedInspectorTabsContainActive: Bool {
        [LayoutState.InspectorTab.search, .history, .library].contains { tab in
            compactInspectorTabIsActive(tab)
        }
    }

    private func compactInspectorTabIsDisabled(_ tab: LayoutState.InspectorTab) -> Bool {
        switch tab {
            case .history:
                return fileState.currentActiveFile == nil
            default:
                return false
        }
    }

    private func compactInspectorTabIsActive(_ tab: LayoutState.InspectorTab) -> Bool {
        if tab == .aiChat, layoutState.isAIChatIslandMode {
            return true
        }
        return layoutState.isInspectorPresented && layoutState.activeInspectorTab == tab
    }

    private func toggleCompactAIChatPresentation() {
        if layoutState.isAIChatIslandMode {
            layoutState.isAIChatIslandMode = false
        } else {
            layoutState.toggleInspector(.aiChat)
        }
    }
    
    @ViewBuilder
    private func denseContent() -> some View {
        HStack {
            Picker(selection: $toolState.activatedTool) {
                ForEach(ExcalidrawTool.allCases, id: \.self) { tool in
                    densePickerItems(tool: tool)
                        .tag(tool)
                }
            } label: {
                Text(.localizable(.toolbarActiveToolTitle))
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
    
    @ViewBuilder
    private func densePickerItems(tool: ExcalidrawTool) -> some View {
        Text(tool.localization)
    }
    
    @ViewBuilder
    private func activeShape() -> some View {
        switch toolState.activatedTool {
            case .rectangle:
                Label(.localizable(.toolbarRectangle), systemSymbol: .rectangle)
            case .diamond:
                Label(.localizable(.toolbarDiamond), systemSymbol: .diamond)
            case .ellipse:
                Label(.localizable(.toolbarEllipse), systemSymbol: .ellipsis)
            case .arrow:
                Label(.localizable(.toolbarArrow), systemSymbol: .lineDiagonalArrow)
            case .line:
                Label(.localizable(.toolbarLine), systemSymbol: .lineDiagonal)
            default:
                Label(.localizable(.toolbarShapes), systemSymbol: .squareOnCircle)
        }
    }
    
    
    @ViewBuilder
    private func moreTools() -> some View {
        ExcalidrawToolbarMoreToolsMenu()
    }
}

enum ExcalidrawToolbarToolSizeClass {
    case dense
    case compact
    case regular
    case expanded
}

struct ExcalidrawToolbarToolContainer<Content: View>: View {
    @Environment(\.containerSize) private var containerSize
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var fileState: FileState
    
    var content: (_ size: ExcalidrawToolbarToolSizeClass) -> Content
    
    init(
        @ViewBuilder content: @escaping (_ size: ExcalidrawToolbarToolSizeClass) -> Content
    ) {
        self.content = content
    }
    
    @State private var sizeClass: ExcalidrawToolbarToolSizeClass = .dense
    
    var body: some View {
        content(sizeClass)
            .watch(value: containerSize, initial: true) { _, newValue in
                syncSizeClass(width: newValue.width)
            }
            .watch(value: layoutState.isInspectorPresented) { _ in
                DispatchQueue.main.async {
                    syncSizeClass(width: containerSize.width)
                }
            }
            .watch(value: layoutState.isSidebarPresented) { _ in
                DispatchQueue.main.async {
                    syncSizeClass(width: containerSize.width)
                }
            }
    }

    private func syncSizeClass(width: CGFloat) {
        guard width > 0 else { return }
        let newSizeClass = getSizeClass(width)
        guard newSizeClass != sizeClass else { return }
        sizeClass = newSizeClass
    }
    
    private func getSizeClass(_ width: CGFloat) -> ExcalidrawToolbarToolSizeClass {
        let collaborationExtraWidth: CGFloat = 90 // Collaborators
        
        let width: CGFloat = if case .collaborationFile = fileState.currentActiveFile {
            width - collaborationExtraWidth
        } else {
            width
        }
        
        if #available(macOS 13.0, *) {
            if layoutState.isInspectorPresented,
               layoutState.isSidebarPresented {
                switch width {
                    case ..<1660:
                        return .dense
                    case ..<1830:
                        return .compact
                    case ..<1980:
                        return .regular
                    default:
                        return .expanded
                }
            } else if layoutState.isSidebarPresented {
                switch width {
                    case ..<1330:
                        return .dense
                    case ..<1480:
                        return .compact
                    case ..<1680:
                        return .regular
                    default:
                        return .expanded
                }
            } else if layoutState.isInspectorPresented {
                switch width {
                    case ..<1510:
                        return .dense
                    case ..<1680:
                        return .compact
                    case ..<1860:
                        return .regular
                    default:
                        return .expanded
                }
            }
        }
        switch width {
            case ..<1170:
                return .dense
            case ..<1330:
                return .compact
            case ..<1510:
                return .regular
            default:
                return .expanded
        }
    }
}

struct SegmentedToolPickerItemView: View {
    var tool: ExcalidrawTool
    var size: CGFloat
    var withFooter: Bool
    
    init(tool: ExcalidrawTool, size: CGFloat, withFooter: Bool) {
        self.tool = tool
        self.size = size
        self.withFooter = withFooter
    }
    
    /// Padding behavior for the icon container — Path/SVG-style icons use less internal padding.
    private var labelType: ExcalidrawToolbarItemModifer.LabelType {
        switch tool {
            case .rectangle, .diamond, .ellipse, .line:
                return .nativeShape
            case .cursor:
                return .svg
            default:
                return .image
        }
    }
    
    /// Keyboard shortcut hint shown as a footer label.
    private var shortcutLabel: String? {
        switch tool {
            case .cursor: return "1"
            case .rectangle: return "2"
            case .diamond: return "3"
            case .ellipse: return "4"
            case .arrow: return "5"
            case .line: return "6"
            case .freedraw: return "7"
            case .text: return "8"
            case .image: return "9"
            case .eraser: return "0"
            case .laser: return "K"
            case .frame: return "F"
            case .hand, .webEmbed, .magicFrame, .lasso: return nil
        }
    }
    
    var body: some View {
        tool.icon()
            .modifier(
                ExcalidrawToolbarItemModifer(size: size, labelType: labelType) {
                    if withFooter, let shortcutLabel {
                        Text(shortcutLabel)
                    }
                }
            )
    }
}

struct ExcalidrawToolbarItemModifer: ViewModifier {
    enum LabelType {
        case nativeShape
        case svg
        case image
    }
    
    var labelType: LabelType
    var footer: AnyView
    
    init<Footer : View>(
        size: CGFloat = 20,
        labelType: LabelType,
        @ViewBuilder footer: () -> Footer
    ) {
        self.size = size
        self.labelType = labelType
        self.footer = AnyView(footer())
    }
    
    var size: CGFloat
    
    func body(content: Content) -> some View {
        content
            .padding(labelType == .nativeShape ? size / 6 : labelType == .svg ? 0 : size / 6)
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
            .padding(size / 5)
            .overlay(alignment: .bottomTrailing) {
                footer
                    .font(.footnote)
            }
            .padding(1)
    }
}

struct CursorModeTrailingButton: View {
    @Environment(\.alertToast) private var alertToast

    @ObservedObject var coordinator: ExcalidrawCanvasView.Coordinator
    var onDone: () -> Void

    private var hasSelection: Bool {
        !coordinator.selectedElementIDs.isEmpty
    }

    var body: some View {
        Button(role: hasSelection ? .destructive : nil) {
            if hasSelection {
                deleteSelectedElements()
            } else {
                onDone()
            }
        } label: {
            if hasSelection {
                Label(.localizable(.generalButtonDelete), systemSymbol: .trash)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.red)
            } else {
                Text(.localizable(.generalButtonDone))
            }
        }
        .contentTransition(.opacity)
        .animation(.smooth, value: hasSelection)
    }

    private func deleteSelectedElements() {
        Task { @MainActor in
            do {
                try await coordinator.toggleDeleteAction()
                coordinator.clearSelectedElementIDs()
            } catch {
                alertToast(error)
            }
        }
    }
}

#Preview {
    ExcalidrawToolbar()
        .background(.background)
}
