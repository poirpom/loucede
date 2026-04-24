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
import Combine
import MarkdownUI

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
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focus: PopoverFocus?
    // Message du toast de confirmation (ex. "Copié", "Collé"). Nil = pas de toast.
    @State private var confirmation: String?
    // Monitor NSEvent pour capter les keycodes physiques 18-29 (touches 1/& à 0/à)
    // et exécuter l'action au slot correspondant. Installé une seule fois au premier
    // .onAppear — NSEvent.addLocalMonitor ne matche que les events de cette app, donc
    // il ne se déclenche que quand le popup est key window (pas de conflit hors popup).
    @State private var slotMonitor: Any?
    // Curseur clignotant du champ de recherche. Toggle via un Timer.publish
    // pour signaler visuellement que le champ est actif (la saisie clavier est
    // captée en permanence par .onKeyPress — le focus SwiftUI est toujours sur .main).
    @State private var cursorVisible: Bool = true
    // Phase 1.4b : état « fenêtre résultat agrandie » (touche F).
    // Reset à false dès qu'on quitte la vue résultat (retour liste ou réouverture
    // du popup), pour que chaque nouvelle action reparte en format compact.
    @State private var resultExpanded: Bool = false

    init(onClose: @escaping () -> Void = {}, onOpenSettings: @escaping () -> Void = {}) {
        self.onClose = onClose
        self.onOpenSettings = onOpenSettings
    }

    // MARK: - Couleurs adaptatives (mode clair / sombre)
    //
    // Phase 6.7 (2026-04-24) : la palette Phase 1.4h/1.4i était codée en dur
    // pour le mode sombre ; en mode clair les fonds #2E2E2E et #1B1C1C
    // rendaient les textes illisibles (blanc sur blanc quasi). Bascule via
    // `@Environment(\.colorScheme)` pour préserver la palette sombre telle
    // qu'elle a été travaillée, et exposer un équivalent clair cohérent
    // (hiérarchie gris clair haut / blanc pur bas, miroir du sombre).

    /// Fond principal de la popup (chrome supérieur, preview texte).
    /// Sombre : `#2E2E2E` (Phase 1.4h). Clair : gris très clair.
    private var popupBackground: Color {
        colorScheme == .dark ? Color(hex: "2E2E2E") : Color(hex: "F5F5F5")
    }

    /// Fond de la zone basse (liste + résultat + footers).
    /// Sombre : `#1B1C1C` (Phase 1.4i), plus sombre que `popupBackground`.
    /// Clair : blanc pur, plus clair que `popupBackground` — on conserve
    /// la hiérarchie visuelle bas/haut par inversion de polarité.
    private var lowerBackground: Color {
        colorScheme == .dark ? Color(hex: "1B1C1C") : Color(hex: "FFFFFF")
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
        // Phase 1.4b : largeur responsive (400 compact → 500 agrandi). Nécessaire
        // pour que le contenu SwiftUI suive l'animation de la NSWindow ; sinon
        // on verrait une bande transparente de chaque côté.
        .frame(width: resultExpanded ? 500 : 400)
        // Phase 1.4h : fond popup solide (remplace le VisualEffectBlur translucide).
        // Palette adaptative Phase 6.7 via `popupBackground` — #2E2E2E en sombre,
        // gris très clair en mode clair.
        .background(popupBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Re-force le focus à chaque ouverture du popup (openCounter s'incrémente
        // dans PopoverState.reset()). Sans ça, la fenêtre préchargée garde un
        // focus stale et .onKeyPress ne reçoit plus rien sur mainView.
        .onChange(of: state.openCounter) { _, _ in
            focus = state.activeAction == nil ? .main : .result
            confirmation = nil
            // Reset : showPopover remet déjà la fenêtre à 400×500, on n'a
            // qu'à synchroniser l'état local.
            resultExpanded = false
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
            // Retour liste depuis résultat agrandi → replier la fenêtre en
            // animant les deux côtés (NSWindow + SwiftUI) comme toggleResultExpanded.
            if newValue == nil, resultExpanded {
                globalAppDelegate?.resizePopover(expanded: false)
                withAnimation(.easeInOut(duration: 0.25)) {
                    resultExpanded = false
                }
            }
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
        // Capture locale : évite que le closure du monitor ne retienne `self`.
        let closeHandler = onClose
        let settingsHandler = onOpenSettings
        slotMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Vue résultat : on ne touche à rien, le handler SwiftUI gère.
            guard state.activeAction == nil else { return event }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // --- Sans modifier : Backspace / Esc gérés ici, le reste passe à SwiftUI.
            // Raison : .onKeyPress(.delete) et .onKeyPress(.escape) sont peu fiables
            // sur macOS (le système intercepte souvent avant SwiftUI), alors que le
            // NSEvent monitor voit toutes les touches physiques sans ambigüité.
            if mods.isEmpty {
                switch event.keyCode {
                case 51: // ⌫ Backspace
                    if !state.searchQuery.isEmpty {
                        state.searchQuery.removeLast()
                        return nil
                    }
                    return event
                case 53: // ⎋ Escape
                    if !state.searchQuery.isEmpty {
                        state.searchQuery = ""
                        return nil
                    }
                    // Esc sans recherche active : ferme le popup.
                    state.streamTask?.cancel()
                    closeHandler()
                    return nil
                default:
                    return event // chiffres, lettres, ponctuation → SwiftUI onKeyPress
                }
            }

            // --- ⌘ seul : slots d'actions (Option B, Phase 1.4g) + ⌘, Réglages.
            // On passe les slots derrière ⌘ pour libérer les frappes nues (chiffres
            // inclus) au profit du champ de recherche libre de la liste.
            if mods == [.command] {
                // ⌘, — raccourci standard macOS pour ouvrir les Réglages (Phase 6.7).
                // charactersIgnoringModifiers pour être indépendant du layout clavier
                // (la virgule n'est pas à la même position physique en AZERTY / QWERTY).
                if event.charactersIgnoringModifiers == "," {
                    settingsHandler()
                    return nil
                }
                guard let slot = Self.slotIndex(forPhysicalKeyCode: event.keyCode) else {
                    return event
                }
                if let action = store.actions.first(where: { $0.slotIndex == slot }) {
                    state.runAction(action)
                    return nil
                }
                return event
            }

            return event
        }
    }

    /// Phase 1.4b : bascule le format de la fenêtre résultat (compact ↔ agrandi).
    /// Deux animations jouent en parallèle et de même durée (0.25 s easeInOut) :
    /// 1) la NSWindow via NSAnimationContext (AppDelegate.resizePopover)
    /// 2) les frames SwiftUI via withAnimation
    /// La 2e évite le saut abrupt à la réduction : sans elle, SwiftUI recalcule
    /// instantanément maxHeight=300, ce qui crée un espace vide avant que la
    /// fenêtre elle-même n'ait fini de rétrécir.
    private func toggleResultExpanded() {
        let newExpanded = !resultExpanded
        globalAppDelegate?.resizePopover(expanded: newExpanded)
        withAnimation(.easeInOut(duration: 0.25)) {
            resultExpanded = newExpanded
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

    /// Liste d'actions filtrée par `state.searchQuery` (Phase 1.4g).
    /// Recherche case-insensitive sur le nom, trim des espaces en bord.
    /// Vide → renvoie toutes les actions (pas de filtrage).
    private var filteredActions: [Action] {
        let q = state.searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.actions }
        return store.actions.filter {
            $0.name.range(of: q, options: .caseInsensitive) != nil
        }
    }

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
                // Phase 1.4g : bandeau de recherche toujours visible, avec
                // placeholder « Rechercher » pour signaler la fonction à
                // l'utilisateur. Alimenté par la frappe directe (onKeyPress
                // ci-dessous), backspace supprime le dernier char.
                // Curseur clignotant : feedback visuel « champ actif » — le popup
                // reçoit la saisie en permanence via onKeyPress, donc il n'y a pas
                // de vrai @FocusState sur un TextField à refléter. On affiche
                // simplement un curseur qui clignote pour que l'utilisateur
                // comprenne qu'il peut taper directement.
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if state.searchQuery.isEmpty {
                        // Empty : curseur à gauche + placeholder grisé à droite
                        // (convention macOS : Spotlight, champ de recherche Finder…).
                        // Phase 6.7 : `.primary` pour s'adapter clair/sombre (blanc
                        // en sombre, noir en clair) — un `Color.white` en dur
                        // disparaissait sur le fond blanc en mode clair.
                        Rectangle()
                            .fill(Color.primary)
                            .frame(width: 1.5, height: 14)
                            .opacity(cursorVisible ? 1 : 0)
                        Text("Rechercher")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        // Non-empty : saisie + curseur à la fin (position d'insertion).
                        HStack(spacing: 1) {
                            Text(state.searchQuery)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                            Rectangle()
                                .fill(Color.primary)
                                .frame(width: 1.5, height: 14)
                                .opacity(cursorVisible ? 1 : 0)
                        }
                    }
                    Spacer()
                    if !state.searchQuery.isEmpty {
                        Text("⌫")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture { focus = .main }
                // Timer de clignotement ~530 ms (rythme caret macOS). Auto-démarré
                // via autoconnect, s'arrête naturellement quand la vue disparaît.
                .onReceive(Timer.publish(every: 0.53, on: .main, in: .common).autoconnect()) { _ in
                    cursorVisible.toggle()
                }
                Divider()

                ScrollView {
                    if filteredActions.isEmpty {
                        Text("Aucune action trouvée")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(filteredActions.enumerated()), id: \.element.id) { index, action in
                                actionRow(action: action, index: index)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .frame(maxHeight: 360)

                // Phase 6.7 : ligne Réglages fixe sous la liste, toujours accessible.
                // Séparateur visuel + item navigable (↑↓+↵) + raccourci ⌘, standard macOS.
                Divider()
                settingsRow()
                    .padding(.horizontal, 8)
                    .padding(.top, 2)

                HStack(spacing: 8) {
                    // Phase 1.4e : mêmes dimensions typographiques que les boutons
                    // de la fenêtre résultat (13pt, taille .body par défaut) pour
                    // cohérence visuelle entre les deux footers.
                    // Phase 6.7 : `.primary` au lieu de `.white` en dur — s'adapte
                    // au colorScheme (blanc en sombre, noir en clair).
                    KeyboardKey("↑")
                    KeyboardKey("↓")
                    Text("Naviguer").font(.system(size: 13)).foregroundStyle(.primary)
                    Spacer()
                    KeyboardKey("↵")
                    Text("Valider").font(.system(size: 13)).foregroundStyle(.primary)
                    Spacer()
                    KeyboardKey("esc")
                    Text("Fermer").font(.system(size: 13)).foregroundStyle(.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(lowerBackground)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focus, equals: .main)
        // Handler clavier SwiftUI pour flèches + Entrée + saisie de recherche.
        // Backspace (⌫) et Esc (⎋) sont gérés par le monitor NSEvent
        // (cf. installSlotMonitorIfNeeded) car .onKeyPress(.delete/.escape) est
        // peu fiable sur macOS quand la fenêtre est préchargée (NSHostingView) —
        // le système intercepte souvent avant que SwiftUI ne reçoive l'event.
        .onKeyPress(phases: .down) { press in
            switch press.key {
            case .upArrow:
                state.selectedIndex = max(0, state.selectedIndex - 1)
                return .handled
            case .downArrow:
                // Phase 6.7 : +1 pour inclure le settings row (index = filteredActions.count).
                state.selectedIndex = min(filteredActions.count, state.selectedIndex + 1)
                return .handled
            case .return:
                // Phase 6.7 : si selectedIndex pointe sur le settings row (dernier
                // index = filteredActions.count), on ouvre les Réglages.
                if state.selectedIndex == filteredActions.count {
                    onOpenSettings()
                } else if filteredActions.indices.contains(state.selectedIndex) {
                    state.runAction(filteredActions[state.selectedIndex])
                }
                return .handled
            default:
                // Phase 1.4g : tout caractère imprimable mono-char alimente
                // la recherche (lettres, accents, chiffres, espace, ponctuation).
                if press.characters.count == 1, let ch = press.characters.first,
                   ch.isLetter || ch.isNumber || ch.isPunctuation || ch == " " {
                    state.searchQuery.append(ch)
                    return .handled
                }
                return .ignored
            }
        }
        // Reset l'index sélectionné quand la liste filtrée change, sinon on peut
        // pointer hors-bornes après filtrage.
        .onChange(of: state.searchQuery) { _, _ in
            state.selectedIndex = 0
        }
    }

    private func actionRow(action: Action, index: Int) -> some View {
        let isSelected = state.selectedIndex == index
        return HStack(spacing: 10) {
            // Phase 6.4 : emoji via ActionIconView (fallback placeholder
            // gris pour les SF legacy). Boîte fixe pour aligner la liste.
            ActionIconView(icon: action.icon, boxSize: 20, fontSize: 14)
            Text(action.name)
                .font(.system(size: 13))
            Spacer()
            // Badge de slot : affiche ⌘1 … ⌘9 / ⌘0 correspondant au raccourci
            // qui déclenche l'action (Option B — Phase 1.4g). Les chiffres nus
            // alimentent le champ de recherche, d'où le préfixe ⌘. On affiche
            // le chiffre logique plutôt que le label AZERTY car c'est ce que
            // l'utilisateur tape réellement avec ⌘, quel que soit son layout.
            if let slot = action.slotIndex {
                KeyboardKey("⌘\(slot == 9 ? 0 : slot + 1)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // Phase 1.4j : couleur de sélection #3F84F7 dans la liste d'actions.
        // Phase 6.7 : texte forcé en blanc quand sélectionné, pour garantir
        // le contraste sur le fond bleu dans les deux modes (sans ça, en
        // mode clair le texte `primary` serait noir → peu lisible).
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(isSelected ? Color(hex: "3F84F7") : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { state.runAction(action) }
        .onHover { hovering in if hovering { state.selectedIndex = index } }
    }

    /// Ligne « Réglages » fixe sous la liste d'actions (Phase 6.7).
    /// Toujours accessible : navigable ↑↓+↵ (index = `filteredActions.count`)
    /// + raccourci ⌘, standard macOS (géré dans le monitor NSEvent).
    /// Visuellement alignée sur `actionRow` (même padding, même radius, même
    /// couleur de sélection #3F84F7) pour cohérence.
    private func settingsRow() -> some View {
        let isSelected = state.selectedIndex == filteredActions.count
        return HStack(spacing: 10) {
            // Icône engrenage SF Symbol, calibrée sur la boîte 20×20 des
            // ActionIconView pour alignement vertical avec les actions.
            Image(systemName: "gearshape")
                .font(.system(size: 14))
                .frame(width: 20, height: 20)
            Text("Réglages")
                .font(.system(size: 13))
            Spacer()
            KeyboardKey("⌘,")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(isSelected ? Color(hex: "3F84F7") : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { onOpenSettings() }
        .onHover { hovering in if hovering { state.selectedIndex = filteredActions.count } }
    }

    // MARK: - Result

    private func resultView(for action: Action) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                // Phase 6.4 : emoji via ActionIconView dans le header résultat
                ActionIconView(icon: action.icon, boxSize: 20, fontSize: 14)
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
                    // Phase 6.5 (2026-04-23) : rendu Markdown via MarkdownUI
                    // (gonzalezreal/swift-markdown-ui, MIT). L'action
                    // "Extrais la recette" produit du Markdown structuré
                    // (titres `#`/`##`, listes, gras, code…) — l'afficher
                    // en texte brut rendait les marques visibles. Le bouton
                    // Copier continue de coller le Markdown brut
                    // (cf. `state.resultText` préservé).
                    Markdown(state.resultText)
                        .markdownTextStyle(\.text) {
                            FontSize(13)
                        }
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                // Phase 1.4b : en format agrandi, le scrollview flex pour remplir
                // la hauteur disponible. En format compact, plafonné à 300.
                // Valeur finie (2000) plutôt que .infinity pour permettre à SwiftUI
                // d'interpoler la hauteur sous withAnimation (depuis/vers .infinity
                // produit un saut abrupt, surtout à la réduction).
                .frame(maxHeight: resultExpanded ? 2000 : 300)

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

                    // Phase 1.4b : indicateur F Agrandir / F Réduire. Clic souris
                    // bascule aussi pour cohérence (sinon seule la touche F marcherait).
                    Button { toggleResultExpanded() } label: {
                        HStack(spacing: 6) {
                            KeyboardKey("F")
                            Text(resultExpanded ? "Réduire" : "Agrandir")
                        }
                    }
                    .buttonStyle(.plain)

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
            .background(lowerBackground)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focus, equals: .result)
        // Handler clavier vue résultat : Esc (retour liste) + F (bascule taille).
        // Unifié en un seul .onKeyPress(phases:) plutôt que plusieurs handlers
        // empilés, pour avoir un dispatch explicite et prévisible.
        .onKeyPress(phases: .down) { press in
            switch press.key {
            case .escape:
                state.streamTask?.cancel()
                state.activeAction = nil
                state.resultText = ""
                return .handled
            default:
                // F / f → bascule format. lowercased() pour accepter caps lock.
                if press.characters.lowercased() == "f" {
                    toggleResultExpanded()
                    return .handled
                }
                return .ignored
            }
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
