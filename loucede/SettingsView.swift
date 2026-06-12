//
//  SettingsView.swift
//  loucede
//

import SwiftUI
import AppKit

// MARK: - Helper

func openAccessibilitySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Notification deeplink

extension Notification.Name {
    /// Poste un Int (index de l'onglet cible) pour forcer la navigation
    /// dans une fenêtre Réglages déjà ouverte. Voir `AppDelegate.openSettings(tab:)`.
    static let loucedeSwitchSettingsTab = Notification.Name("loucedeSwitchSettingsTab")
}

struct SettingsView: View {
    @StateObject private var store = ActionsStore.shared
    @StateObject private var updateChecker = UpdateChecker.shared
    // Phase 1.5a : onglet "Général" (index 0) par défaut au lieu de "Actions" (1).
    // Phase 6.3 : accepte un `initialTab` pour le deeplink depuis la popup.
    @State private var selectedTab: Int
    @State private var selectedAction: Action?

    init(initialTab: Int = 0) {
        _selectedTab = State(initialValue: initialTab)
    }

    // Phase 6.7b revertée (2026-04-29) : @AppStorage("appTheme") et
    // savedColorScheme retirés — loucedé suit le mode système macOS.
    // La clé UserDefaults "appTheme" reste orpheline chez les users
    // existants (inoffensive).

    var body: some View {
        VStack(spacing: 0) {
            // Correctif 2026-04-27 : barre d'onglets passe en format
            // « pictogramme + titre » (style macOS natif Settings). Chaque
            // onglet est un `TabIconButton` avec un SF Symbol au-dessus du
            // label. Onglet sélectionné mis en évidence par un fond pillé
            // (corner radius 8) en couleur accent translucide.
            HStack(spacing: 4) {
                TabIconButton(title: "Général", systemImage: "gearshape", isSelected: selectedTab == 0) {
                    withAnimation(.easeInOut(duration: 0.25)) { selectedTab = 0 }
                }
                // Phase 1.5b : "Prompts" renommé "Actions" pour cohérence avec
                // le reste du vocabulaire (ActionsStore, Action, actionRow…).
                TabIconButton(title: "Actions", systemImage: "square.and.pencil", isSelected: selectedTab == 1) {
                    withAnimation(.easeInOut(duration: 0.25)) { selectedTab = 1 }
                }
                // K.unify.3 (2026-05-21) : onglet « Modèles » retiré (modèle
                // unifié — les modèles vivent désormais dans Actions). Les
                // index suivants sont décalés : Licence 3→2, Mises à jour
                // 4→3, À propos 5→4.
                TabIconButton(title: "Licence", systemImage: "key.fill", isSelected: selectedTab == 2) {
                    withAnimation(.easeInOut(duration: 0.25)) { selectedTab = 2 }
                }
                // Phase 6.3 (2026-04-28) : onglet Mises à jour. Badge orange
                // si mise à jour disponible.
                TabIconButton(
                    title: "Mises à jour",
                    systemImage: "arrow.triangle.2.circlepath",
                    isSelected: selectedTab == 3,
                    showBadge: updateChecker.updateAvailable
                ) {
                    withAnimation(.easeInOut(duration: 0.25)) { selectedTab = 3 }
                }
                TabIconButton(title: "À propos", systemImage: "info.circle", isSelected: selectedTab == 4) {
                    withAnimation(.easeInOut(duration: 0.25)) { selectedTab = 4 }
                }
                // Phase F.3 (2026-06-12) : onglet Documentation — la doc
                // embarquée (ex-fenêtre dédiée ⌘D) vit désormais ici.
                TabIconButton(title: "Doc", systemImage: "book", isSelected: selectedTab == 5) {
                    withAnimation(.easeInOut(duration: 0.25)) { selectedTab = 5 }
                }
            }
            .padding(.vertical, 8)
            .onAppear { updateChecker.checkForUpdates() }
            .onReceive(NotificationCenter.default.publisher(for: .loucedeSwitchSettingsTab)) { note in
                if let tab = note.object as? Int {
                    withAnimation(.easeInOut(duration: 0.25)) { selectedTab = tab }
                }
            }

            Divider()

            if updateChecker.updateAvailable {
                UpdateBanner(version: updateChecker.latestVersion ?? "") {
                    updateChecker.openDownloadPage()
                }
            }

            Group {
                switch selectedTab {
                case 0: GeneralSettingsView()
                case 1: ActionsSettingsView(selectedAction: $selectedAction)
                // K.unify.3 : case 2 (TemplatesView) supprimé, index décalés.
                case 2: LicenseSettingsView()
                case 3: UpdatesView()
                case 4: AboutView()
                case 5: DocumentationView()
                default: EmptyView()
                }
            }
            .id(selectedTab)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .animation(.easeInOut(duration: 0.2), value: selectedTab)
        }
        // F.4 (C1.5) : PAS de taille fixe côté SwiftUI — le contenu
        // remplit la hosting view, qui suit la NSWindow frame par frame
        // pendant l'animation de resizeSettingsWindow. Une seule source
        // d'animation (AppKit) : un .frame fixe animé en parallèle
        // « flottait » au moindre décalage de timing (contenu centré
        // dans la hosting view) — retour runtime C1. Les tailles par
        // onglet ne vivent que dans tabSizes, consommées par
        // l'AppDelegate (création + resize).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: selectedTab) { _, newTab in
            globalAppDelegate?.resizeSettingsWindow(to: Self.size(forTab: newTab))
        }
    }

    // MARK: - Tailles par onglet (F.4)

    /// Tailles cibles de la fenêtre Réglages par onglet (style Things 3,
    /// resize dynamique F.4). Source unique consommée par le .frame du
    /// body (contenu SwiftUI) ET par AppDelegate.openSettings /
    /// resizeSettingsWindow (frame NSWindow).
    static let tabSizes: [Int: CGSize] = [
        0: CGSize(width: 800, height: 540),    // Général
        1: CGSize(width: 1000, height: 700),   // Actions (sidebar 38/62)
        2: CGSize(width: 800, height: 540),    // Licence
        3: CGSize(width: 800, height: 540),    // Mises à jour
        4: CGSize(width: 800, height: 540),    // À propos
        5: CGSize(width: 860, height: 700),    // Doc
    ]

    /// Taille cible d'un onglet, défaut 800×540 (filet pour un index
    /// inconnu — ne devrait pas arriver, les onglets sont hardcodés).
    static func size(forTab tab: Int) -> CGSize {
        tabSizes[tab] ?? CGSize(width: 800, height: 540)
    }
}

// MARK: - Tab button

/// Bouton d'onglet style macOS natif Settings : pictogramme SF Symbol
/// au-dessus du libellé, fond pillé quand sélectionné.
/// Correctif 2026-04-27 : remplace l'ancien `TabTextButton` (texte seul).
struct TabIconButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    var showBadge: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .regular))
                        .frame(width: 22, height: 22)
                        .foregroundColor(isSelected ? Color.accentColor : .secondary)
                    if showBadge {
                        Circle()
                            .fill(Color(red: 0.976, green: 0.620, blue: 0.043)) // #F59E0B
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -4)
                    }
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .frame(width: 80, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 3D Keyboard keys (réutilisés par les vues réglages)

struct Keyboard3DKey: View {
    @Environment(\.colorScheme) var colorScheme
    let text: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color(white: 0.25) : Color(white: 0.7))
                .frame(width: 36, height: 36)
                .offset(y: 3)
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color.white : Color(white: 0.95))
                .frame(width: 36, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(colorScheme == .dark ? 0 : 0.3), lineWidth: 1)
                )
            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.black)
        }
        .frame(width: 36, height: 39)
    }
}

struct Settings3DKey: View {
    @Environment(\.colorScheme) var colorScheme
    let text: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.7))
                .frame(width: 30, height: 30)
                .offset(y: colorScheme == .dark ? 3 : 2)
            RoundedRectangle(cornerRadius: 6)
                .fill(colorScheme == .dark ? Color(white: 0.3) : Color(white: 0.95))
                .frame(width: 30, height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(colorScheme == .dark ? Color(white: 0.4) : Color.gray.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.clear, radius: 2, x: 0, y: 1)
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        }
        .frame(width: 30, height: colorScheme == .dark ? 33 : 32)
    }
}

struct Keyboard3DKeyLarge: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color(white: 0.25) : Color(white: 0.7))
                .frame(width: 64, height: 64)
                .offset(y: 4)
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color.white : Color(white: 0.95))
                .frame(width: 64, height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.gray.opacity(colorScheme == .dark ? 0 : 0.3), lineWidth: 1)
                )
            Image(systemName: "command")
                .font(.system(size: 28, weight: .regular))
                .foregroundColor(Color(white: 0.35))
        }
        .frame(width: 64, height: 68)
    }
}

struct Keyboard3DKeyEditable: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var text: String
    var onSave: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color(white: 0.25) : Color(white: 0.7))
                .frame(width: 44, height: 36)
                .offset(y: 3)
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color.white : Color(white: 0.95))
                .frame(width: 44, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(colorScheme == .dark ? 0 : 0.3), lineWidth: 1)
                )
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .frame(width: 44, height: 36)
                .onChange(of: text) { _, newValue in
                    text = newValue.uppercased().prefix(1).description
                    onSave()
                }
        }
        .frame(width: 44, height: 39)
    }
}

// MARK: - Dot pattern

struct DotPatternView: View {
    let dotSize: CGFloat = 2
    let spacing: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            let columns = Int(geometry.size.width / spacing) + 1
            let rows = Int(geometry.size.height / spacing) + 1
            Canvas { context, size in
                for row in 0..<rows {
                    for col in 0..<columns {
                        let x = CGFloat(col) * spacing
                        let y = CGFloat(row) * spacing
                        let rect = CGRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize)
                        context.fill(Circle().path(in: rect), with: .color(Color.gray.opacity(0.15)))
                    }
                }
            }
        }
    }
}

// MARK: - Update banner

struct UpdateBanner: View {
    let version: String
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(.white)
            Text("Version \(version) disponible")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Button(action: onDownload) {
                Text("Télécharger")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.accentColor)
    }
}

#Preview {
    SettingsView()
}
