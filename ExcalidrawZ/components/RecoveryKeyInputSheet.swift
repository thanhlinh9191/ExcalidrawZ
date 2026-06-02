//
//  RecoveryKeyInputSheet.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/05/28.
//

import SwiftUI

import ChocofordUI

enum RecoveryKeyInputSheetHeaderLayout {
    case prominent
    case compact
}

struct RecoveryKeyInputSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String?
    let message: String?
    let primaryButtonTitle: String
    let headerLayout: RecoveryKeyInputSheetHeaderLayout
    let width: CGFloat
    let onSubmit: (RecoveryKey) async throws -> Void

    @FocusState private var isRecoveryKeyFocused: Bool
    @State private var recoveryKeyText = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(
        title: String,
        subtitle: String? = nil,
        message: String? = nil,
        primaryButtonTitle: String,
        headerLayout: RecoveryKeyInputSheetHeaderLayout = .prominent,
        width: CGFloat = 560,
        onSubmit: @escaping (RecoveryKey) async throws -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.message = message
        self.primaryButtonTitle = primaryButtonTitle
        self.headerLayout = headerLayout
        self.width = width
        self.onSubmit = onSubmit
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                recoveryKeyTextField

                errorLabel
            }
            .padding(24)

            HStack(spacing: 10) {
                Spacer()
                footerButtons
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 22)
        }
        .onAppear {
            isRecoveryKeyFocused = true
        }
#if os(macOS)
        .frame(width: width)
#endif
    }

    @ViewBuilder
    private var header: some View {
        switch headerLayout {
            case .prominent:
                prominentHeader
            case .compact:
                compactHeader
        }
    }

    @ViewBuilder
    private var prominentHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 38, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)

            Text(title)
                .font(.title2.weight(.semibold))

            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var compactHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "key.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 46, height: 46)
                .background(Color.accentColor.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title2.weight(.semibold))

                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var recoveryKeyTextField: some View {
        SecureField(String(localizable: .lockedContentRecoveryKeyPlaceholder), text: $recoveryKeyText)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .focused($isRecoveryKeyFocused)
            .disabled(isWorking)
            .onSubmit {
                guard !primaryButtonDisabled else { return }
                Task {
                    await submit()
                }
            }
#if os(iOS)
            .textInputAutocapitalization(.characters)
#endif
    }

    @ViewBuilder
    private var errorLabel: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                footerButtonContent
            }
        } else {
            footerButtonContent
        }
    }

    @ViewBuilder
    private var footerButtonContent: some View {
        HStack(spacing: 10) {
            Button(.localizable(.generalButtonCancel)) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .modernButtonStyle(style: .glass, size: .large, shape: .capsule)
            .disabled(isWorking)

            Button {
                Task {
                    await submit()
                }
            } label: {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(primaryButtonTitle)
                }
            }
            .keyboardShortcut(.defaultAction)
            .modernButtonStyle(style: .glassProminent, size: .large, shape: .capsule)
            .disabled(primaryButtonDisabled)
        }
    }

    private var primaryButtonDisabled: Bool {
        isWorking || recoveryKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() async {
        let startedAt = Date()
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        do {
            let recoveryKey = try RecoveryKey(displayString: recoveryKeyText)
            try await onSubmit(recoveryKey)
            dismiss()
        } catch {
            await LockedContentSecurityDelay.waitBeforeShowingFailure(startedAt: startedAt)
            errorMessage = LockedContentErrorPresenter.message(for: error)
        }
    }
}
