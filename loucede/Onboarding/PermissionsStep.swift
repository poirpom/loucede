//
//  PermissionsStep.swift
//  loucede
//

import SwiftUI
import AppKit

struct PermissionsStep: View {
    var onNext: () -> Void
    var onBack: () -> Void

    @State private var hasAccessibilityPermission = false
    @State private var isWaiting = false
    @State private var rotationAngle: Double = 0
    @State private var permissionCheckTimer: Timer?

    // Étape 4 (palette pastel) :
    // - `brandPastel` (#CAE9FF) : fond du right panel — bleu pastel,
    //   "système = configuration" (parallèle avec le site web)
    // - `accentYellow` / `accentGreen` : conservés pour le signal
    //   conditionnel de la status bubble (spinner + texte) — la
    //   transition de couleur est portée par la bubble centrale
    //   (et triplée par le SF Symbol gauche ajouté Étape 2 +
    //   le label du bouton primaire)
    // - `stepBlue` : conservé pour le lien "J'ai besoin d'aide"
    private let brandPastel  = Color(hex: "CAE9FF")
    private let accentYellow = Color(hex: "F9A825")
    private let accentGreen  = Color(hex: "00ce44")
    private let stepBlue     = Color(hex: "2196F3")


    var body: some View {
        HStack(spacing: 0) {
            // Left side - Adaptive with instructions
            ZStack {
                Color(NSColor.windowBackgroundColor)

                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                        .frame(height: 40)

                    Text("Accessibilité")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Spacer()
                        .frame(height: 10)

                    Text("L'autorisation d'accessibilité est requise\npour que loucedé fonctionne.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)

                    Spacer()
                        .frame(height: 24)

                    // Steps or Features
                    if hasAccessibilityPermission {
                        // Show simple feature list when permission is granted
                        VStack(alignment: .leading, spacing: 14) {
                            PermissionCheckItem(text: "Raccourcis clavier globaux")
                            PermissionCheckItem(text: "Détection du texte sélectionné")
                            PermissionCheckItem(text: "Collage du texte transformé")
                        }
                        .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 12) {
                            StepRow(number: 1, text: "Clique sur « Autoriser »")
                            StepRow(number: 2, text: "Trouve loucedé dans la liste")
                            StepRow(number: 3, text: "Active l'interrupteur")
                        }

                        Spacer()
                            .frame(height: 16)

                        // Help link
                        Button(action: {}) {
                            Text("J'ai besoin d'aide")
                                .font(.system(size: 13))
                                .foregroundColor(stepBlue)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Signal visuel "permission accordée" — uniquement quand
                    // hasAccessibilityPermission == true. Étape 2 : remplace
                    // le toggle de couleur du bouton par un signal SF Symbol
                    // dédié (cohérence avec accent macOS uniforme sur les
                    // boutons primaires).
                    if hasAccessibilityPermission {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(.green)
                            Text("Permission accordée")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .scale))
                    }

                    // Boutons système : Retour secondaire + primaire toggle
                    // ("Autoriser l'accès" / "Continuer" selon état).
                    HStack(spacing: 12) {
                        Button("Retour", action: onBack)
                            .buttonStyle(.bordered)
                            .controlSize(.regular)

                        Button(action: {
                            if hasAccessibilityPermission {
                                onNext()
                            } else {
                                grantPermissions()
                            }
                        }) {
                            Text(hasAccessibilityPermission ? "Continuer" : "Autoriser l'accès")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                    Spacer()
                        .frame(height: 30)
                }
                .padding(.horizontal, 32)
            }
            .frame(width: 340)

            // Right side — bleu pastel (Étape 4). Les FloatingIcon
            // décoratifs sont retirés : le pastel apporte assez de douceur,
            // plus besoin de remplir le vide visuel d'un fond uni vif.
            ZStack {
                brandPastel

                // Status indicator
                HStack(spacing: 10) {
                    ZStack {
                        // Spinning reload icon (fades out when granted)
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(accentYellow)
                            .rotationEffect(.degrees(rotationAngle))
                            .opacity(hasAccessibilityPermission ? 0 : 1)
                            .scaleEffect(hasAccessibilityPermission ? 0.5 : 1)

                        // Checkmark (fades in when granted)
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(accentGreen)
                            .opacity(hasAccessibilityPermission ? 1 : 0)
                            .scaleEffect(hasAccessibilityPermission ? 1 : 0.5)
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: hasAccessibilityPermission)

                    Text(hasAccessibilityPermission ? "Accès accordé !" : "En attente d'accès")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(hasAccessibilityPermission ? accentGreen : accentYellow)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white)
                )
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
            }
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea()
        .onAppear {
            checkAccessibilityPermission()
            startRotationAnimation()
            startPermissionCheck()
        }
        .onDisappear {
            permissionCheckTimer?.invalidate()
        }
    }

    private func checkAccessibilityPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    private func startPermissionCheck() {
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            checkAccessibilityPermission()
        }
    }

    private func startRotationAnimation() {
        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
    }

    private func grantPermissions() {
        isWaiting = true
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Step Row Component

struct StepRow: View {
    let number: Int
    let text: String

    private let stepGreen = Color(hex: "00ce44")

    var body: some View {
        HStack(spacing: 12) {
            // Number circle
            ZStack {
                Circle()
                    .fill(stepGreen)
                    .frame(width: 28, height: 28)

                Text("\(number)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
                )
        )
    }
}

// MARK: - Permission Check Item

struct PermissionCheckItem: View {
    let text: String

    private let checkGreen = Color(hex: "00ce44")

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(checkGreen)

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
        }
    }
}

