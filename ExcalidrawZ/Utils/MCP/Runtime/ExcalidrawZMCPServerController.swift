//
//  ExcalidrawZMCPServerController.swift
//  ExcalidrawZ
//
//  Created by Codex on 6/15/26.
//

import Foundation
import Combine

enum ExcalidrawMCPServiceMode: String, CaseIterable, Identifiable {
    case basic
    case optimized

    var id: Self { self }
}

@MainActor
final class ExcalidrawZMCPServerController: ObservableObject {
    enum State: Equatable {
        case off
        case starting
        case running
        case stopping
        case failed(String)
    }

    static let shared = ExcalidrawZMCPServerController()

    private static let isEnabledDefaultsKey = "ExcalidrawZMCPServerEnabled"
    private static let serviceModeDefaultsKey = "ExcalidrawZMCPServiceMode"

    @Published private(set) var state: State = .off
    @Published private(set) var isEnabled: Bool
    @Published private(set) var serviceMode: ExcalidrawMCPServiceMode

    let port: UInt16

    private var server: ExcalidrawZMCPServer?
    private var serverTask: Task<Void, Never>?

    private init(port: UInt16 = ExcalidrawZMCPServer.defaultPort) {
        self.port = port
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.isEnabledDefaultsKey)
        self.serviceMode = Self.loadServiceMode()

        if isEnabled {
            startServerIfNeeded()
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.isEnabledDefaultsKey)

        if enabled {
            startServerIfNeeded()
        } else {
            stopServerIfNeeded()
        }
    }

    func setServiceMode(_ mode: ExcalidrawMCPServiceMode) {
        guard serviceMode != mode else { return }
        serviceMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.serviceModeDefaultsKey)
    }

    func startServerIfNeeded() {
        guard serverTask == nil else { return }

        let router = ExcalidrawMCPToolRouter()
        let server = ExcalidrawZMCPServer(port: port, router: router)
        self.server = server
        state = .starting

        serverTask = Task { [weak self, server, router] in
            do {
                let rawElementConverter = ExcalidrawMCPUpstreamRawElementConverter { elements in
                    try await ExcalidrawMCPAppBridge.shared.createElements(elements)
                }

                await router.setElementConverter { elements in
                    try await rawElementConverter.convertRawElements(elements)
                }
                await router.setSessionUpdateHandler { session in
                    try await ExcalidrawMCPAppBridge.shared.apply(session)
                }

                await MainActor.run {
                    self?.state = .running
                }

                try await server.start()

                await MainActor.run {
                    guard let self else { return }
                    self.finishServerTask(
                        unexpectedErrorMessage: "The MCP server stopped unexpectedly."
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard let self else { return }
                    self.finishServerTask()
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.finishServerTask(unexpectedErrorMessage: error.localizedDescription)
                }
            }
        }
    }

    func stopServerIfNeeded() {
        guard let server else {
            state = .off
            return
        }

        state = .stopping
        Task { [server] in
            await server.stop()
        }
    }

    private func finishServerTask(unexpectedErrorMessage: String? = nil) {
        let wasStopping = state == .stopping
        let shouldRestart = isEnabled && wasStopping
        serverTask = nil
        server = nil

        if shouldRestart {
            startServerIfNeeded()
        } else if !isEnabled || wasStopping {
            state = .off
        } else if let unexpectedErrorMessage {
            state = .failed(unexpectedErrorMessage)
        } else {
            state = .off
        }
    }

    private static func loadServiceMode() -> ExcalidrawMCPServiceMode {
        guard let rawValue = UserDefaults.standard.string(forKey: serviceModeDefaultsKey),
              let mode = ExcalidrawMCPServiceMode(rawValue: rawValue) else {
            return .basic
        }
        return mode
    }
}
