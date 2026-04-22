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
    // Message du toast de confirmation (ex. "Copié", "Collé"). Nil = pas de toast.
    @State private var confirmation: String?
    // Monitor NSEvent pour capter les keycodes physiques 18-29 (touches 1/& à 0/à)
    // et exécuter l'action au slot correspondant. Installé une seule fois au premier
    // .onAppear — NSEvent.addLocalMonitor ne matche que les events de cette app, donc
    // il ne se déclenche que quand le popup est key window (pas de conflit hors popup).
    @State private var slotMonitor: Any?

    init(onClose: @escaping () -> Void = {}, onOpenSettings: @escaping () -> Void = {}) {
        self.onClose = onClose
        self.onOpenSettings = onOpenSettings
    }

    /// Mapping keyCode physique Carbon → index de slot (0 = touche 1/&, …, 9 = touche 0/à).
    /// Ces keyCodes sont identiques en AZERTY FR et QWERTY US (c'est la position physique
    /// de la touche sur le clavier). Source : Carbon HIToolbox `kVK_ANSI_1` … `kVK_ANSI_0`.
    private static func slotIndex(forPhysicalKeyCode keyCode: UInt16) -> Int? {
        switch keyCode {
        case 18: return 0 // touche 1 / &
        case 19: return 1 // touche 2 / é
        case 20: return 2 // touche 3 / "
        case 21: return 3 // touche 4 / '
        case 23: return 4 // touche 5 / (
        case 22: return 5 // touche 6 / §
        case 26: return 6 // touche 7 / è
        case 28: return 7 // touche 8 / !
        case 25: return 8 // touche 9 / ç
        case 29: return 9 // touche 0 / à
        default: return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let action = state.activeAction {
                resultView(for: action)
            } else {
                mainView
            }
        }
        .frame(width: 400)
        // Phase 1.4h : fond popup solide #2E2E2E (remplace le VisualEffectBlur
        // translucide). Choix délibéré de palette dark unifiée, indépendante
        // de la transparence macOS.
        .background(Color(hex: "2E2E2E"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Re-force le focus à chaque ouverture du popup (openCounter s'incrémente
        // dans PopoverState.reset()). Sans ça, la fenêtre préchargée garde un
        // focus stale et .onKeyPress ne reçoit plus rien sur mainView.
        .onChange(of: state.openCounter) { _, _ in
            focus = state.activeAction == nil ? .main : .result
            confirmation = nil
        }
        // Focus initial au premier affichage (avant le premier openCounter).
        .onAppear {
            focus = state.activeAction == nil ? .main : .result
            installSlotMonitorIfNeeded()
        }
        // Bascule aussi le focus quand on passe de liste → résultat ou retour.
        .onChange(of: state.activeAction) { _, newValue in
            focus = newValue == nil ? .main : .result
            confirmation = nil
        }
    }

    // MARK: - Confirmation toast helper

    /// Affiche un toast de confirmation au centre de la vue (copie / collage).
    /// `duration` = temps avant disparition auto. `then` = action à exécuter
    /// après la disparition (utile pour Coller qui ferme le popup).
    /// Installe le monitor NSEvent qui capte les touches 1/& → 0/à (keycodes 18-29)
    /// et lance l'action assignée au slot correspondant, quand le popup est en mode liste.
    /// N'installe qu'une seule fois (pas de leak, pas de double capture).
    private func installSlotMonitorIfNeeded() {
        guard slotMonitor == nil else { return }
        slotMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Ne capte que si on est dans la liste de prompts (pas en vue résultat),
            // et si aucun modifier n'est actif (on ne veut pas intercepter ⌘1, ⌥1, etc.).
            guard state.activeAction == nil else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods.isEmpty else { return event }
            // Match keyCode physique → slot.
            guard let slot = Self.slotIndex(forPhysicalKeyCode: event.keyCode) else {
                return event
            }
            // Cherche l'action assignée à ce slot et l'exécute.
            if let action = store.actions.first(where: { $0.slotIndex == slot }) {
                state.runAction(action)
                return nil // événement consommé
            }
            // Slot vide : on laisse passer (ne bloque rien côté utilisateur).
            return event
        }
    }

    private func showConfirmation(_ message: String, duration: Double = 1.2, then completion: (() -> Void)? = nil) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            confirmation = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if confirmation == message {
                withAnimation(.easeOut(duration: 0.2)) {
                    confirmation = nil
                }
            }
            completion?()
        }
    }

    // MARK: - Main

    private var mainView: some View {
        // spacing: 0 (comme resultView) pour que la zone #1B1C1C colle directement
        // au Divider sous la preview, sans gap visuel dû au spacing du VStack.
        VStack(alignment: .leading, spacing: 0) {
            if textManager.hasSelection {
                Text(textManager.capturedText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
            }

            Divider().opacity(textManager.hasSelection ? 1 : 0)

            // Phase 1.4i : zone basse de la popup (liste + footer nav) en #1B1C1C,
            // pour la distinguer du chrome supérieur (aperçu texte) en #2E2E2E.
            VStack(spacing: 0) {
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
                    // Phase 1.4e : mêmes dimensions typographiques que les boutons
                    // de la fenêtre résultat (13pt, taille .body par défaut) pour
                    // cohérence visuelle entre les deux footers.
                    // Texte en blanc : lisibilité sur le fond #1B1C1C + cohérence
                    // avec les libellés Copier / Coller / Retour de la vue résultat.
                    KeyboardKey("↑")
                    KeyboardKey("↓")
                    Text("Naviguer").font(.system(size: 13)).foregroundStyle(.white)
                    Spacer()
                    KeyboardKey("↵")
                    Text("Valider").font(.system(size: 13)).foregroundStyle(.white)
                    Spacer()
                    KeyboardKey("esc")
                    Text("Fermer").font(.system(size: 13)).foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color(hex: "1B1C1C"))
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
        // Esc depuis la liste : ferme le popup.
        .onKeyPress(.escape) {
            state.streamTask?.cancel()
            onClose()
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
            // Badge de slot : affiche le numéro (1-9, 0) correspondant à la touche
            // physique qui déclenche l'action. Absent si slotIndex == nil.
            if let slot = action.slotIndex {
                KeyboardKey(slot == 9 ? "0" : "\(slot + 1)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // Phase 1.4j : couleur de sélection #3F84F7 dans la liste d'actions de la popup.
        .background(state.selectedIndex == index ? Color(hex: "3F84F7") : Color.clear)
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

            // Phase 1.4i : zone basse du résultat (texte + footer boutons) en #1B1C1C.
            VStack(spacing: 0) {
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
                    // Phase 1.4 : boutons en .plain pour retirer le chrome bordered
                    // macOS — cohérence visuelle avec le footer nav de la liste et
                    // allègement de l'interface.
                    // Phase 1.4d : pas de picto SF Symbol, KeyboardKey avant le Text
                    // (même ordre que le footer nav de la liste : touche → libellé).
                    // Copier : ⌘↵ — copie le résultat dans le presse-papier (popup reste ouvert)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(state.resultText, forType: .string)
                        showConfirmation("Copié")
                    } label: {
                        HStack(spacing: 6) {
                            KeyboardKey("⌘↵")
                            Text("Copier")
                        }
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)

                    // Coller : ↵ — colle dans l'app précédente (ferme le popup).
                    // On attend que le toast "Collé" soit visible ~300 ms avant
                    // d'appeler performPasteInPreviousApp (qui orderOut le popup).
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(state.resultText, forType: .string)
                        showConfirmation("Collé", duration: 0.3) {
                            globalAppDelegate?.performPasteInPreviousApp()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            KeyboardKey("↵")
                            Text("Coller")
                        }
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])

                    Spacer()

                    // Retour : esc — géré par le handler Esc au niveau de la resultView,
                    // le bouton reste actionnable à la souris.
                    Button {
                        state.streamTask?.cancel()
                        state.activeAction = nil
                        state.resultText = ""
                    } label: {
                        HStack(spacing: 6) {
                            KeyboardKey("esc")
                            Text("Retour")
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
            }
            .background(Color(hex: "1B1C1C"))
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focus, equals: .result)
        // Esc depuis la vue résultat : revient à la liste de prompts (comportement
        // cohérent avec le bouton "Retour"). Attaché directement ici car les
        // handlers sur le body outer ne se déclenchent pas toujours quand le focus
        // SwiftUI est ancré sur une sous-vue focusable.
        .onKeyPress(.escape) {
            state.streamTask?.cancel()
            state.activeAction = nil
            state.resultText = ""
            return .handled
        }
        // Overlay du toast de confirmation (copie / collage). S'affiche brièvement
        // au centre de la vue résultat et se dissipe automatiquement.
        .overlay(alignment: .center) {
            if let msg = confirmation {
                ConfirmationToast(message: msg)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
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

// MARK: - Confirmation Toast (✓ Copié / ✓ Collé)

struct ConfirmationToast: View {
    let message: String

    // Phase 1.4a : toutes les dimensions ×3 (+200 %).
    // Picto 14→42, texte 13→39, padding 14/10→42/30, spacing 8→24, shadow 8→24.
    // Si trop grand visuellement sur écran, diviser par 1.5 pour retomber à ×2.
    var body: some View {
        HStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 42))
            Text(message)
                .font(.system(size: 39, weight: .medium))
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 30)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.gray.opacity(0.2), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 24, y: 6)
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
