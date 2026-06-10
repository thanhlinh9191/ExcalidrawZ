//
//  ExcalidrawEditor.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 9/23/25.
//

import SwiftUI
import Combine
import CoreData
#if os(iOS)
import UIKit
#endif

import ChocofordUI
import Logging

struct ExcalidrawEditor: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.alertToast) var alertToast
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass

    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var localFolderState: LocalFolderState
    @EnvironmentObject var toolState: ToolState
    /// Drives the AI chat island overlay — its presentation toggle is global,
    /// but the *anchor* (bottom-center) is editor-local, hence the overlay
    /// lives here rather than at the NavigationSplitView level.
    @EnvironmentObject var layoutState: LayoutState
    @EnvironmentObject private var lockedContentState: LockedContentStateStore

    let logger = Logger(label: "ExcalidrawEditor")

    @Binding var activeFile: FileState.ActiveFile?
    var interactionEnabled: Bool

    @State private var isSettingsPresented = false
    @State private var excalidrawFile: ExcalidrawFile?
    @State private var isLoadingFile = false
    @State private var loadingTask: Task<Void, Never>?
    @State private var fileLoadRevealTask: Task<Void, Never>?
    @State private var documentLoadCompletion: ExcalidrawDocumentLoadCompletion?

    @State private var conflictFileURL: URL?
    @State private var isSyncing = false

    // MARK: - Smart Sync State

    /// Latest cloud data from observeExcalidrawFileStatus (not immediately applied)
    @State private var latestCloudData: Data?
    /// Last received file content from WebView (for change detection)
    @State private var lastReceivedFileContent: Data?
    /// Last time the user edited the file (applyExcalidrawFile was called with actual changes)
    @State private var lastEditTime: Date?
    /// Task waiting to apply deferred cloud updates (cancellable)
    @State private var cloudSyncTask: Task<Void, Never>?
    /// Idle timeout in seconds before applying cloud updates
    private let idleTimeout: TimeInterval = 2.0

    init(
        activeFile: Binding<FileState.ActiveFile?>,
        interactionEnabled: Bool = true
    ) {
        self._activeFile = activeFile
        self.interactionEnabled = interactionEnabled
    }
    
    var localFileBinding: Binding<ExcalidrawFile?> {
        Binding<ExcalidrawFile?> {
            return fileState.currentActiveFile == nil ? ExcalidrawFile() : excalidrawFile
        } set: { val in
            guard let val else { return }
            _ = persistCanvasUpdate(val)
        }
    }

    private enum CanvasUpdatePersistenceResult {
        case accepted
        case ignoredNoChanges
        case rejected

        var shouldUpdateEditorState: Bool {
            switch self {
                case .accepted, .ignoredNoChanges:
                    return true
                case .rejected:
                    return false
            }
        }
    }
    
    var isInCollaborationSpace: Bool {
        if case .collaborationFile = activeFile {
            return true
        } else {
            return false
        }
    }

    private var usesCompactIOSAIChatSurfaces: Bool {
#if os(iOS)
        containerHorizontalSizeClass == .compact
#else
        false
#endif
    }
    
    
    @State private var canvasLoadingState: ExcalidrawCanvasView.LoadingState = .loading

    /// Live size of the editor's content frame. Fed into `AIChatIslandView`
    /// so it can clamp its drag offset back inside the editor when the user
    /// flings it past an edge.
    @State private var editorContentSize: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                ExcalidrawCanvasView(
                    file: Binding {
                        localFileBinding.wrappedValue
                    } set: { val in
                        applyExcalidrawFile(val)
                    },
                    loadingState: $canvasLoadingState,
                    interactionEnabled: interactionEnabled,
                    onDocumentLoadFinished: { fileID in
                        documentLoadCompletion = ExcalidrawDocumentLoadCompletion(fileID: fileID)
                        revealLoadedFileAfterRender(fileID: fileID)
                    }
                ) { error in
                    alertToast(error)
                }
                .preferredColorScheme(appPreference.excalidrawAppearance.colorScheme)
                .excalidrawEditorOverlays(
                    loadingState: $canvasLoadingState,
                    hasFile: localFileBinding.wrappedValue != nil
                )
                .opacity(isInCollaborationSpace ? 0 : 1)
                .allowsHitTesting(!isInCollaborationSpace && !isLoadingFile)

                CollaborationEditorStack()
                    .opacity(isInCollaborationSpace ? 1 : 0)
                    .allowsHitTesting(isInCollaborationSpace && !isLoadingFile)
            }
            .allowsHitTesting(!isLoadingFile)
#if os(iOS)
            .dismissKeyboardOnCanvasTap()
#endif

            ExcalidrawTrailingControls()
                .opacity(isLoadingFile ? 0 : 1)
                .allowsHitTesting(!isLoadingFile)
        }
        .readSize($editorContentSize)
        .overlay(alignment: .bottom) {
#if os(iOS)
            if !usesCompactIOSAIChatSurfaces {
                AIChatIslandOverlay(canvasSize: editorContentSize)
            }
#else
            AIChatIslandOverlay(canvasSize: editorContentSize)
#endif
        }
#if os(iOS)
        .overlay(alignment: .bottom) {
            CompactAIChatInputOverlay()
        }
        .overlay(alignment: .bottom) {
            CompactAIChatGeneratingOverlay()
        }
        .overlay(alignment: .bottom) {
            CompactAIChatProposalOverlay()
        }
#endif
        .animation(.smooth(duration: 0.3), value: layoutState.isAIChatIslandMode)
        .animation(.smooth(duration: 0.3), value: layoutState.isCompactAIChatToolbarPresented)
        .animation(.smooth(duration: 0.3), value: layoutState.isCompactAIChatInputEditing)
        .modifier(
            LockedFileUnlockOverlayModifier(
                activeFile: activeFile,
                documentLoadCompletion: documentLoadCompletion,
                onPrepareLockedFile: prepareEditorForLockedFile,
                onApplyUnlockedContent: applyUnlockedFileContentToEditor
            )
        )
        .allowsHitTesting(interactionEnabled)
        .observeExcalidrawFileStatus(
            for: activeFile,
            activeFileLockState: lockedContentState.activeFileLockState,
            conflictFileURL: $conflictFileURL,
        ) { latestData, onDone in
            handleLatestData(latestData)
        } onResolveConflict: { url in
            // Conflict resolution should apply immediately
            loadingTask?.cancel()
            loadingTask = Task {
                if let latestData = try? await FileSyncCoordinator.shared.openFile(url) {
                    await pullUpdatingFromCloud(latestData: latestData)
                }
            }
        }
#if os(iOS)
        .applyIOSAutoSync(
            activeFile: activeFile,
            activeFileLockState: lockedContentState.activeFileLockState,
            localFileBinding: localFileBinding
        ) { latestData in
            await pullUpdatingFromCloud(latestData: latestData)
        }
#endif
        .watch(value: activeFile) { (newFile: FileState.ActiveFile?) in
            loadingTask?.cancel()
            loadingTask = Task {
                await lockedContentState.prepareForActiveFileChange(to: newFile)
                await loadExcalidrawFile(from: newFile)
            }
        }
        .watch(value: fileState.currentActiveFileIsInTrash) { _ in
            collapseCompactAISurfacesIfCurrentFileIsTrashed()
        }
        .watch(value: layoutState.isAIChatIslandMode) { _ in
            collapseCompactAISurfacesIfCurrentFileIsTrashed()
        }
        .watch(value: layoutState.isCompactAIChatToolbarPresented) { _ in
            collapseCompactAISurfacesIfCurrentFileIsTrashed()
        }
        .task {
            await lockedContentState.prepareForActiveFileChange(to: activeFile)
            await loadExcalidrawFile(from: activeFile)
        }
        .onAppear {
            collapseCompactAISurfacesIfCurrentFileIsTrashed()
        }
    }

    private func collapseCompactAISurfacesIfCurrentFileIsTrashed() {
        guard fileState.currentActiveFileIsInTrash else { return }
        layoutState.isAIChatIslandMode = false
        layoutState.exitCompactAIChatToolbar()
    }

    private func beginFileLoadRevealGuard(fileID: String) {
        fileLoadRevealTask?.cancel()
        isLoadingFile = true
        fileLoadRevealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled,
                  activeFile?.id == fileID else { return }
            isLoadingFile = false
            fileLoadRevealTask = nil
        }
    }

    private func revealLoadedFileAfterRender(fileID: String) {
        guard activeFile?.id == fileID else { return }

        fileLoadRevealTask?.cancel()
        fileLoadRevealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled,
                  activeFile?.id == fileID else { return }
            isLoadingFile = false
            fileLoadRevealTask = nil
        }
    }

    private func cancelFileLoadRevealGuard() {
        fileLoadRevealTask?.cancel()
        fileLoadRevealTask = nil
        isLoadingFile = false
    }
    
    private func loadExcalidrawFile(from activeFile: FileState.ActiveFile?) async {
        guard let activeFile else {
            cancelFileLoadRevealGuard()
            self.excalidrawFile = ExcalidrawFile()
            fileState.excalidrawWebCoordinator?.documentSyncController.setTargetFileID(nil)
            return
        }

        switch activeFile {
            case .file(_), .localFile(_), .temporaryFile(_):
                fileState.excalidrawWebCoordinator?.documentSyncController
                    .setTargetFileID(activeFile.id)
                beginFileLoadRevealGuard(fileID: activeFile.id)
            default:
                cancelFileLoadRevealGuard()
                fileState.excalidrawWebCoordinator?.documentSyncController.setTargetFileID(nil)
        }
        
        do {
            switch activeFile {
                case .file(let file):
                    let content = try await file.loadContent()
                    let parsedFile = try? ExcalidrawFile(data: content, id: activeFile.id)
                    await MainActor.run {
                        guard self.activeFile?.id == activeFile.id else { return }
                        self.excalidrawFile = parsedFile
                    }
                    
                case .localFile(let url):
                    let data = try await FileSyncCoordinator.shared.openFile(url)
                    let file = try ExcalidrawFile(data: data, id: activeFile.id)
                    await MainActor.run {
                        guard self.activeFile?.id == activeFile.id else { return }
                        self.excalidrawFile = file
                    }

                case .temporaryFile(let url):
                    let data = try await FileSyncCoordinator.shared.openFile(url)
                    let file = try ExcalidrawFile(data: data, id: activeFile.id)
                    await MainActor.run {
                        guard self.activeFile?.id == activeFile.id else { return }
                        self.excalidrawFile = file
                    }

                default:
                    await MainActor.run {
                        self.excalidrawFile = nil
                    }
            }
        } catch EncryptedContentError.contentLocked(_, _) {
            await MainActor.run {
                guard self.activeFile?.id == activeFile.id else { return }
                cancelFileLoadRevealGuard()
                prepareEditorForLockedFile()
            }
        } catch is EncryptedContentError {
            await MainActor.run {
                guard self.activeFile?.id == activeFile.id else { return }
                cancelFileLoadRevealGuard()
                lockedContentState.markUnlockFailed(fileID: activeFile.id)
                prepareEditorForLockedFile()
            }
        } catch {
            fileState.excalidrawWebCoordinator?.documentSyncController.setTargetFileID(nil)
            alertToast(error)
            await MainActor.run {
                cancelFileLoadRevealGuard()
                self.excalidrawFile = nil
            }
        }
    }

    @MainActor
    private func prepareEditorForLockedFile() {
        fileState.excalidrawWebCoordinator?.documentSyncController.setTargetFileID(nil)
        cloudSyncTask?.cancel()
        cloudSyncTask = nil
        latestCloudData = nil
        lastReceivedFileContent = nil
        excalidrawFile = nil
    }

    private func applyUnlockedFileContentToEditor(
        _ content: Data,
        request: LockedFileUnlockRequest
    ) async throws {
        let parsedFile = try ExcalidrawFile(data: content, id: request.fileID)
        await MainActor.run {
            guard self.activeFile?.id == request.fileID else { return }
            self.fileState.excalidrawWebCoordinator?.documentSyncController
                .setTargetFileID(request.fileID)
            self.excalidrawFile = parsedFile
            self.lastReceivedFileContent = parsedFile.content
        }
    }
    
    private func handleLatestData(_ latestData: Data) {
        guard lockedContentState.activeFileLockState != .locked else {
            logger.info("Ignored cloud update while active file is locked")
            return
        }

        // Check if user has been idle long enough
        let isIdle = if let lastEdit = lastEditTime {
            Date().timeIntervalSince(lastEdit) > idleTimeout
        } else {
            true  // No edit yet, consider idle
        }

        if isIdle {
            // User is idle, apply cloud update immediately
            logger.info("User idle, applying cloud update immediately")
            cloudSyncTask?.cancel()  // Cancel any pending task
            isSyncing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isSyncing = false
            }
            Task {
                await pullUpdatingFromCloud(latestData: latestData)
            }
        } else {
            // User is actively editing, defer cloud update and wait for idle
            logger.info("User is editing, deferring cloud update and starting wait task")
            self.latestCloudData = latestData

            // Cancel previous task if any
            cloudSyncTask?.cancel()

            // Start new task to wait for idle
            cloudSyncTask = Task {
                // Wait for idle timeout
                try? await Task.sleep(nanoseconds: UInt64(idleTimeout * 1_000_000_000))

                // Check if still idle and still have cloud data
                if let lastEdit = await MainActor.run(body: { self.lastEditTime }),
                   Date().timeIntervalSince(lastEdit) >= idleTimeout,
                   let stillCloudData = await MainActor.run(body: { self.latestCloudData }) {
                    // Apply deferred cloud update
                    await MainActor.run {
                        self.logger.info("Wait task: User became idle, applying deferred cloud update")
                        self.latestCloudData = nil
                        self.cloudSyncTask = nil
                        self.isSyncing = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            self.isSyncing = false
                        }
                    }
                    await pullUpdatingFromCloud(latestData: stillCloudData)
                } else {
                    await MainActor.run {
                        self.cloudSyncTask = nil
                    }
                }
            }
        }
    }

    private func pullUpdatingFromCloud(latestData: Data) async {
        guard lockedContentState.activeFileLockState != .locked else {
            self.logger.info("Skipped cloud pull while active file is locked")
            return
        }

        self.logger.info("pullUpdatingFromCloud")
        do {
            let file = try ExcalidrawFile(data: latestData, id: excalidrawFile?.id)
            await MainActor.run {
                self.excalidrawFile = file
                NotificationCenter.default.post(name: .forceReloadExcalidrawFile, object: nil)
            }
        } catch {
            alertToast(error)
            await MainActor.run {
                self.excalidrawFile = nil
            }
        }
    }

    /// Compare only elements and appState fields from two JSON data
    private func compareExcalidrawContent(_ data1: Data, _ data2: Data) -> Bool {
        let start = Date()
        do {
            guard let dict1 = try JSONSerialization.jsonObject(with: data1) as? [String: Any],
                  let dict2 = try JSONSerialization.jsonObject(with: data2) as? [String: Any] else {
                return false
            }
            
            if let elements1 = dict1["elements"] as? [Any],
               let elements2 = dict2["elements"] as? [Any] {
                logger.info("elements1: \(elements1.count) -- elements2: \(elements2.count)")
            }

            // Compare elements
            let elements1JSON = try JSONSerialization.data(withJSONObject: dict1["elements"] ?? [])
            let elements2JSON = try JSONSerialization.data(withJSONObject: dict2["elements"] ?? [])

            // Compare appState
            let appState1JSON = try JSONSerialization.data(withJSONObject: dict1["appState"] ?? [:])
            let appState2JSON = try JSONSerialization.data(withJSONObject: dict2["appState"] ?? [:])

            self.logger.info("compareExcalidrawContent time consume: \((Date().timeIntervalSince(start)).formatted())")
            return elements1JSON == elements2JSON && appState1JSON == appState2JSON
        } catch {
            logger.error("Failed to compare excalidraw content: \(error)")
            return false
        }
    }

    private func applyExcalidrawFile(_ file: ExcalidrawFile?) {
        guard let file else { return }
        guard let currentContent = file.content else { return }

        // Check if content actually changed (compare elements and appState)
        if let lastContent = lastReceivedFileContent,
           compareExcalidrawContent(lastContent, currentContent) {
            // Content unchanged, don't update lastEditTime or cancel task
            logger.info("Content unchanged, skipping update")
            return
        }

        guard persistCanvasUpdate(file).shouldUpdateEditorState else { return }

        // Content changed, update tracking
        lockedContentState.noteUserActivity()
        lastReceivedFileContent = currentContent
        lastEditTime = Date()
        logger.info("Content changed, updating lastEditTime and canceling any pending cloud sync task")

        // Cancel pending cloud sync task (user is editing again, need to reset wait)
        cloudSyncTask?.cancel()
        cloudSyncTask = nil

        // Keep in-memory file in sync so exports read the latest elements.
        excalidrawFile = file
    }

    private func persistCanvasUpdate(_ file: ExcalidrawFile) -> CanvasUpdatePersistenceResult {
        guard activeFile?.id == file.id else { return .rejected }

        // Block updates while loading new file.
        guard !isLoadingFile else {
            logger.info("Blocked update during file loading")
            return .rejected
        }

        guard lockedContentState.activeFileLockState != .locked else {
            logger.info("Blocked update while active file is locked")
            return .rejected
        }

        switch activeFile {
            case .file(let activeFile):
                if let currentFile = excalidrawFile, file.elements == currentFile.elements {
                    logger.info("no updates, ignored.")
                    return .ignoredNoChanges
                }
                return fileState.updateFile(activeFile, with: file) ? .accepted : .rejected

            case .localFile(let url):
                guard case .localFolder(let folder) = fileState.currentActiveGroup else { return .rejected }
                Task {
                    try folder.withSecurityScopedURL { _ in
                        do {
                            let oldElements = try ExcalidrawFile(contentsOf: url).elements
                            if file.elements == oldElements {
                                logger.info("no updates, ignored.")
                                return
                            }
                            try await fileState.updateLocalFile(
                                to: url,
                                with: file,
                                context: viewContext
                            )
                        } catch {
                            alertToast(error)
                        }
                    }
                }
                return .accepted

            case .temporaryFile(let url):
                Task {
                    do {
                        let oldElements = try ExcalidrawFile(contentsOf: url).elements
                        if file.elements == oldElements {
                            logger.info("no updates, ignored.")
                            return
                        }
                        try await fileState.updateLocalFile(
                            to: url,
                            with: file,
                            context: viewContext
                        )
                    } catch {
                        alertToast(error)
                    }
                }
                return .accepted

            default:
                return .rejected
        }
    }
}

#if os(iOS)
private extension View {
    func dismissKeyboardOnCanvasTap() -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
        )
    }
}
#endif
