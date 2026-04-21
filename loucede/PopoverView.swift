//
//  PopoverView.swift
//  loucede
//
//  Vue principale de la popup. Version minimale (Phase 0) — sera
//  refondue en Phase 1 pour le préchargement en mémoire et en
//  Phase 2 pour le modèle Prompt enrichi (emoji + slot 1-10).
//

import SwiftUI
import AppKit

// MARK: - Shared UI helpers

extension View {
    func pointerCursor() -> some View {
        self.onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

struct PopoverView: View {
    var onClose: () -> Void
    var onOpenSettings: () -> Void

    @StateObject private var store = ActionsStore.shared
    @StateObject private var textManager = CapturedTextManager.shared
    @State private var selectedIndex = 0
    @State private var isProcessing = false
    @State private var resultText: String = ""
    @State private var activeAction: Action?
    @State private var streamTask: Task<Void, Never>?

    init(onClose: @escaping () -> Void = {}, onOpenSettings: @escaping () -> Void = {}, initialAction: Action? = nil) {
        self.onClose = onClose
        self.onOpenSettings = onOpenSettings
        self._activeAction = State(initialValue: initialAction)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let action = activeAction {
                resultView(for: action)
            } else {
                mainView
            }
        }
        .frame(width: 320)
        .background(VisualEffectBlur())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            selectedIndex = 0
            if let initial = activeAction {
                runAction(initial)
            }
        }
        .onKeyPress(.escape) {
            streamTask?.cancel()
            onClose()
            return .handled
        }
    }

    // MARK: - Main

    private var mainView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if textManager.hasSelection {
                Text(textManager.capturedText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
            }

            Divider().opacity(textManager.hasSelection ? 1 : 0)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(store.actions.enumerated()), id: \.element.id) { index, action in
                        actionRow(action: action, index: index)
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxHeight: 360)

            HStack(spacing: 8) {
                KeyboardKey("↑")
                KeyboardKey("↓")
                Text("Naviguer").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                KeyboardKey("↵")
                Text("Valider").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                KeyboardKey("esc")
                Text("Fermer").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.1))
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(store.actions.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.return) {
            if store.actions.indices.contains(selectedIndex) {
                runAction(store.actions[selectedIndex])
            }
            return .handled
        }
    }

    private func actionRow(action: Action, index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: action.icon)
                .font(.system(size: 14))
                .frame(width: 20)
            Text(action.name)
                .font(.system(size: 13))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selectedIndex == index ? Color.accentColor.opacity(0.25) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { runAction(action) }
        .onHover { hovering in if hovering { selectedIndex = index } }
    }

    // MARK: - Result

    private func resultView(for action: Action) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: action.icon)
                Text(action.name).font(.system(size: 13, weight: .semibold))
                Spacer()
                if isProcessing {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(12)

            Divider()

            ScrollView {
                Text(resultText)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 300)

            Divider()

            HStack(spacing: 8) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(resultText, forType: .string)
                } label: {
                    Label("Copier", systemImage: "doc.on.doc")
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(resultText, forType: .string)
                    globalAppDelegate?.performPasteInPreviousApp()
                } label: {
                    Label("Coller", systemImage: "arrow.down.doc")
                }

                Spacer()

                Button {
                    streamTask?.cancel()
                    activeAction = nil
                    resultText = ""
                } label: {
                    Text("Retour")
                }
            }
            .padding(12)
        }
    }

    // MARK: - Actions

    private func runAction(_ action: Action) {
        activeAction = action
        resultText = ""
        isProcessing = true

        let apiKey = store.apiKey
        let provider = store.selectedProvider
        let model = store.selectedModel
        let inputText = textManager.capturedText
        let fullPrompt = inputText.isEmpty ? action.prompt : "\(action.prompt)\n\n\(inputText)"

        streamTask = Task {
            do {
                try await AIService.shared.chatStream(
                    messages: [(role: "user", content: fullPrompt)],
                    apiKey: apiKey,
                    provider: provider,
                    model: model
                ) { chunk in
                    resultText += chunk
                }
            } catch {
                await MainActor.run {
                    resultText = "Erreur : \(error.localizedDescription)"
                }
            }
            await MainActor.run { isProcessing = false }
        }
    }
}

// MARK: - Keyboard Key (also used by QuickPromptView)

struct KeyboardKey: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - Visual Effect Blur (translucent background)

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .popover
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
