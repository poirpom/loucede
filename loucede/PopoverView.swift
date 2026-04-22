//
//  PopoverView.swift
//  loucede
//
//  Vue principale de la popup. Phase 1 — l'état est centralisé dans
//  PopoverState (singleton) pour permettre le préchargement en mémoire
//  de la fenêtre (createPopoverWindow appelé une seule fois au démarrage).
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

// Champs de focus possibles dans le popup. Utilisés avec @FocusState pour
// forcer le focus clavier sur la bonne sous-vue à chaque ouverture — nécessaire
// depuis que la fenêtre AppKit est préchargée (cf. PopoverState.openCounter).
private enum PopoverFocus: Hashable {
    case main
    case result
}

struct PopoverView: View {
    var onClose: () -> Void
    var onOpenSettings: () -> Void

    @StateObject private var store = ActionsStore.shared
    @StateObject private var textManager = CapturedTextManager.shared
    @ObservedObject private var state = PopoverState.shared
    @FocusState private var focus: PopoverFocus?

    init(onClose: @escaping () -> Void = {}, onOpenSettings: @escaping () -> Void = {}) {
        self.onClose = onClose
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            if let action = state.activeAction {
                resultView(for: action)
            } else {
                mainView
            }
        }
        .frame(width: 320)
        .background(VisualEffectBlur())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onKeyPress(.escape) {
            // Depuis la vue résultat, Esc revient à la liste de prompts
            // (cohérent avec le bouton "Retour"). Depuis la liste, Esc ferme le popup.
            if state.activeAction != nil {
                state.streamTask?.cancel()
                state.activeAction = nil
                state.resultText = ""
            } else {
                state.streamTask?.cancel()
                onClose()
            }
            return .handled
        }
        // Re-force le focus à chaque ouverture du popup (openCounter s'incrémente
        // dans PopoverState.reset()). Sans ça, la fenêtre préchargée garde un
        // focus stale et .onKeyPress ne reçoit plus rien sur mainView.
        .onChange(of: state.openCounter) { _, _ in
            focus = state.activeAction == nil ? .main : .result
        }
        // Focus initial au premier affichage (avant le premier openCounter).
        .onAppear {
            focus = state.activeAction == nil ? .main : .result
        }
        // Bascule aussi le focus quand on passe de liste → résultat ou retour.
        .onChange(of: state.activeAction) { _, newValue in
            focus = newValue == nil ? .main : .result
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
        .focusable()
        .focusEffectDisabled()
        .focused($focus, equals: .main)
        .onKeyPress(.upArrow) {
            state.selectedIndex = max(0, state.selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            state.selectedIndex = min(store.actions.count - 1, state.selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.return) {
            if store.actions.indices.contains(state.selectedIndex) {
                state.runAction(store.actions[state.selectedIndex])
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
        .background(state.selectedIndex == index ? Color.accentColor.opacity(0.25) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { state.runAction(action) }
        .onHover { hovering in if hovering { state.selectedIndex = index } }
    }

    // MARK: - Result

    private func resultView(for action: Action) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: action.icon)
                Text(action.name).font(.system(size: 13, weight: .semibold))
                Spacer()
                if state.isProcessing {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(12)

            Divider()

            ScrollView {
                Text(state.resultText)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 300)

            Divider()

            HStack(spacing: 8) {
                // Copier : ⌘↵ — copie le résultat dans le presse-papier (popup reste ouvert)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(state.resultText, forType: .string)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                        Text("Copier")
                        KeyboardKey("⌘↵")
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)

                // Coller : ↵ — colle dans l'app précédente (ferme le popup)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(state.resultText, forType: .string)
                    globalAppDelegate?.performPasteInPreviousApp()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.doc")
                        Text("Coller")
                        KeyboardKey("↵")
                    }
                }
                .keyboardShortcut(.return, modifiers: [])

                Spacer()

                // Retour : esc — géré par le handler Esc global au niveau du body,
                // le bouton reste actionnable à la souris.
                Button {
                    state.streamTask?.cancel()
                    state.activeAction = nil
                    state.resultText = ""
                } label: {
                    HStack(spacing: 6) {
                        Text("Retour")
                        KeyboardKey("esc")
                    }
                }
            }
            .padding(12)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focus, equals: .result)
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
