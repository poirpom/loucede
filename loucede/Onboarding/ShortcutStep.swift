//
//  ShortcutStep.swift
//  loucede
//

import SwiftUI
import AppKit

struct ShortcutStep: View {
    var onNext: () -> Void
    var onBack: () -> Void

    @ObservedObject private var store = ActionsStore.shared
    @State private var recordedKeys: [String] = []
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    /// Phase 3 : affichage du raccourci courant = modifiers + lettre, lu depuis
    /// ActionsStore (source de vérité unique partagée avec GeneralSettingsView
    /// et le handler Carbon). Remplace l'ancien @State + clé UserDefaults
    /// orpheline `loucede_shortcut_keys` qui n'était jamais lue ailleurs.
    private var savedShortcutKeys: [String] {
        store.mainShortcutModifiers + [store.mainShortcut]
    }

    private let brandOrange = Color(hex: "ff7300")

    var body: some View {
        HStack(spacing: 0) {
            // Left side - Adaptive form
            ZStack {
                Color(NSColor.windowBackgroundColor)

                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                        .frame(height: 40)

                    Text("Raccourci")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Spacer()
                        .frame(height: 10)

                    Text("Définis ton raccourci clavier\npour invoquer loucedé partout.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)

                    Spacer()
                        .frame(height: 40)

                    // Shortcut recorder with tooltip
                    VStack(spacing: 0) {
                        // Tooltip appears above when recording
                        if isRecording {
                            OnboardingShortcutTooltip(recordedKeys: recordedKeys)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.8, anchor: .bottom).combined(with: .opacity),
                                    removal: .scale(scale: 0.8, anchor: .bottom).combined(with: .opacity)
                                ))
                                .padding(.bottom, 8)
                        }

                        // Shortcut display box
                        Button(action: {
                            startRecording()
                        }) {
                            HStack(spacing: 8) {
                                if savedShortcutKeys.isEmpty {
                                    Text("Clique pour enregistrer un raccourci…")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(savedShortcutKeys, id: \.self) { key in
                                        OnboardingShortcutKey(text: key)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                                    .foregroundColor(Color(NSColor.separatorColor))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecording)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: recordedKeys)

                    Spacer()
                        .frame(height: 16)

                    Text("Clique sur la case ci-dessus\npour enregistrer un nouveau raccourci.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)

                    Spacer()

                    // Boutons système : Retour secondaire + Continuer primaire
                    HStack(spacing: 12) {
                        Button("Retour", action: onBack)
                            .buttonStyle(.bordered)
                            .controlSize(.regular)

                        Button("Continuer", action: onNext)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }

                    Spacer()
                        .frame(height: 14)

                    Text("Modifiable à tout moment dans les réglages.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()
                        .frame(height: 20)
                }
                .padding(.horizontal, 32)
            }
            .frame(width: 340)

            // Right side - Orange with keyboard image
            ZStack {
                brandOrange

                VStack(spacing: 20) {
                    Spacer()

                    // Keyboard image
                    Image("keyboard")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 380)
                        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)

                    // Animated hint tooltip
                    KeyboardHintTooltip()

                    Spacer()
                }
                .padding(30)
            }
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea()
        .onDisappear {
            stopRecording()
        }
    }

    /// Phase 3 : capture du raccourci principal sur le modèle de
    /// `GeneralSettingsView.startRecordingMainShortcut`. Écrit dans
    /// `ActionsStore` (modifiers + lettre + keyCode) puis appelle
    /// `saveMainShortcut()` pour persister les 3 clés UserDefaults.
    /// Le publisher Combine de loucedeApp ré-enregistre le hotkey Carbon
    /// automatiquement (debounce 500 ms).
    private func startRecording() {
        stopRecording() // Clean up any existing monitor
        isRecording = true
        recordedKeys = []

        // Use local monitor for key events
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard self.isRecording else { return event }

            let modifiers = event.modifierFlags

            // Build current modifier keys array
            var currentModifiers: [String] = []
            if modifiers.contains(.control) { currentModifiers.append("^") }
            if modifiers.contains(.option) { currentModifiers.append("\u{2325}") }
            if modifiers.contains(.shift) { currentModifiers.append("\u{21E7}") }
            if modifiers.contains(.command) { currentModifiers.append("\u{2318}") }

            if event.type == .flagsChanged {
                // Update recorded keys to show current modifiers in real-time
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    self.recordedKeys = currentModifiers
                }
                return event
            }

            if event.type == .keyDown {
                // Must have Command or Option to complete
                let hasCommand = modifiers.contains(.command)
                let hasOption = modifiers.contains(.option)

                if !hasCommand && !hasOption {
                    // Ignore keys without Command or Option
                    return event
                }

                // Add the final key
                let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
                if !key.isEmpty && key.count == 1 {
                    var finalKeys = currentModifiers
                    finalKeys.append(key)

                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        self.recordedKeys = finalKeys
                    }

                    // Persiste dans ActionsStore (source unique) puis
                    // enregistre ; le publisher re-register Carbon.
                    let capturedKey = key
                    let capturedModifiers = currentModifiers
                    let capturedKeyCode = event.keyCode
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.store.mainShortcutModifiers = capturedModifiers
                        self.store.mainShortcut = capturedKey
                        self.store.mainShortcutKeyCode = capturedKeyCode
                        self.store.saveMainShortcut()
                        withAnimation {
                            self.isRecording = false
                        }
                        self.stopRecording()
                    }
                    return nil
                }
            }
            return event
        }
    }

    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// MARK: - Onboarding Shortcut Tooltip

struct OnboardingShortcutTooltip: View {
    let recordedKeys: [String]

    var body: some View {
        VStack(spacing: 0) {
            // Tooltip content
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text("ex.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    // Always show 3 key slots
                    ForEach(0..<3, id: \.self) { index in
                        if index < recordedKeys.count {
                            OnboardingTooltipKey(text: recordedKeys[index])
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.5).combined(with: .opacity),
                                    removal: .opacity
                                ))
                                .id("key-\(index)-\(recordedKeys[index])")
                        } else {
                            OnboardingTooltipKey(text: "")
                                .opacity(0.4)
                        }
                    }
                }

                VStack(spacing: 4) {
                    Text("Enregistrement…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("Appuie sur \u{2318} ou \u{2325} + touche")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
            )

            // Arrow pointing down
            OnboardingTooltipArrow()
                .fill(Color.white)
                .frame(width: 16, height: 10)
                .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 2)
        }
    }
}

// MARK: - Onboarding Tooltip Key

struct OnboardingTooltipKey: View {
    let text: String

    var body: some View {
        ZStack {
            // Bottom layer (3D effect)
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.separatorColor))
                .frame(width: 28, height: 28)
                .offset(y: 2)

            // Top layer
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
                .frame(width: 28, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
                )

            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(width: 28, height: 30)
    }
}

// MARK: - Onboarding Tooltip Arrow

struct OnboardingTooltipArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Onboarding Shortcut Key Display

struct OnboardingShortcutKey: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    // 3D effect bottom
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.separatorColor))
                        .offset(y: 2)

                    // Top
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
                        )
                }
            )
    }
}

// MARK: - Keyboard Hint Tooltip (Animated)

struct KeyboardHintTooltip: View {
    @State private var activeKeyIndex = 0
    @State private var floatOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // Arrow pointing up to keyboard
            KeyboardHintArrow()
                .fill(Color.white)
                .frame(width: 16, height: 10)
                .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: -2)

            // Tooltip content
            VStack(spacing: 8) {
                // Main row: [⌘] ou [⌥] + [W]
                HStack(spacing: 8) {
                    KeyboardHintKey(text: "\u{2318}", isActive: activeKeyIndex == 0)
                    Text("ou")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "999999"))
                    KeyboardHintKey(text: "\u{2325}", isActive: activeKeyIndex == 1)
                    Text("+")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: "999999"))
                    KeyboardHintKey(text: "W", isActive: false)
                }

                // Subtitle
                Text("Choisis ⌘ ou ⌥, combine avec une lettre")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "666666"))

                // Bonus line
                HStack(spacing: 4) {
                    Text("Tu peux aussi ajouter")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "999999"))
                    ShortcutBonusKey(text: "^")
                    Text("ou")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "999999"))
                    ShortcutBonusKey(text: "\u{21E7}")
                    Text("pour enrichir ton raccourci.")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "999999"))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
        }
        .offset(y: floatOffset)
        .onAppear {
            startAnimations()
        }
    }

    private func startAnimations() {
        // Key highlight cycling animation
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                activeKeyIndex = (activeKeyIndex + 1) % 2
            }
        }

        // Floating animation
        withAnimation(
            .easeInOut(duration: 2.0)
            .repeatForever(autoreverses: true)
        ) {
            floatOffset = -6
        }
    }
}

// MARK: - Keyboard Hint Key (with animation)

struct KeyboardHintKey: View {
    let text: String
    let isActive: Bool

    var body: some View {
        ZStack {
            // Bottom layer (3D effect)
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color(hex: "1976D2") : Color(hex: "d0d0d0"))
                .frame(width: 32, height: 32)
                .offset(y: 2)

            // Top layer
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color(hex: "2196F3") : Color.white)
                .frame(width: 32, height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isActive ? Color(hex: "1976D2") : Color(hex: "e0e0e0"), lineWidth: 1)
                )

            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isActive ? .white : Color(hex: "333333"))
        }
        .frame(width: 32, height: 34)
        .scaleEffect(isActive ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActive)
    }
}

// MARK: - Shortcut Bonus Key

struct ShortcutBonusKey: View {
    let text: String

    var body: some View {
        ZStack {
            // Bottom layer (3D effect)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: "d0d0d0"))
                .frame(width: 20, height: 20)
                .offset(y: 2)

            // Top layer
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white)
                .frame(width: 20, height: 20)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(hex: "e0e0e0"), lineWidth: 1)
                )

            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "333333").opacity(0.7))
        }
        .frame(width: 20, height: 22)
        .opacity(0.7)
    }
}

// MARK: - Keyboard Hint Arrow (pointing up)

struct KeyboardHintArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
