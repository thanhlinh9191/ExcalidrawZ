//
//  SidebarFileRowSelectionState.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/6/25.
//

import Combine
import CoreData
import Foundation

final class SidebarFileRowSelectionState: ObservableObject {
    @Published private(set) var isSelected = false
    @Published private(set) var isMultiSelected = false

    private var fileObjectID: NSManagedObjectID?
    private var cancellables: Set<AnyCancellable> = []

    func bind(file: File, fileState: FileState) {
        guard fileObjectID != file.objectID else { return }

        fileObjectID = file.objectID
        cancellables.removeAll()

        updateActiveSelection(fileState: fileState)
        updateMultiSelection(fileState: fileState)

        fileState.$activeFiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak fileState] _ in
                guard let self, let fileState else { return }
                self.updateActiveSelection(fileState: fileState)
            }
            .store(in: &cancellables)

        fileState.$selectedFiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak fileState] _ in
                guard let self, let fileState else { return }
                self.updateMultiSelection(fileState: fileState)
            }
            .store(in: &cancellables)
    }

    private func updateActiveSelection(fileState: FileState) {
        guard let fileObjectID else { return }
        let nextValue: Bool
        if case .file(let file) = fileState.currentActiveFile {
            nextValue = file.objectID == fileObjectID
        } else {
            nextValue = false
        }
        if isSelected != nextValue {
            isSelected = nextValue
        }
    }

    private func updateMultiSelection(fileState: FileState) {
        guard let fileObjectID else { return }
        let nextValue = fileState.selectedFiles.contains { $0.objectID == fileObjectID }
        if isMultiSelected != nextValue {
            isMultiSelected = nextValue
        }
    }
}

final class SidebarGroupRowSelectionState: ObservableObject {
    @Published private(set) var isSelected = false

    private var groupObjectID: NSManagedObjectID?
    private var cancellables: Set<AnyCancellable> = []

    func bind(group: Group, fileState: FileState) {
        guard groupObjectID != group.objectID else { return }

        groupObjectID = group.objectID
        cancellables.removeAll()

        updateSelection(fileState: fileState)

        fileState.$currentActiveGroup
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak fileState] _ in
                guard let self, let fileState else { return }
                self.updateSelection(fileState: fileState)
            }
            .store(in: &cancellables)

        fileState.$activeFiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak fileState] _ in
                guard let self, let fileState else { return }
                self.updateSelection(fileState: fileState)
            }
            .store(in: &cancellables)

    }

    private func updateSelection(fileState: FileState) {
        guard let groupObjectID else { return }
        let nextValue: Bool
        if case .group(let group) = fileState.currentActiveGroup,
           fileState.currentActiveFile == nil {
            nextValue = group.objectID == groupObjectID
        } else {
            nextValue = false
        }
        if isSelected != nextValue {
            isSelected = nextValue
        }
    }
}
