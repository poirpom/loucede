//
//  CapturePermissionToast.swift
//  loucede
//
//  O.4 (Snapshot OCR) — feedback permission Screen Recording. Deux toasts
//  flottants ÉPHÉMÈRES (pas de WindowController à état comme CaptureText-
//  WindowController) : un seul affiché à la fois, matériau système adaptatif
//  (.ultraThinMaterial, même famille que ConfirmationToast), auto-dismiss.
//
//  Messages AUTOSUFFISANTS (O.5 — onboarding permission — hors périmètre de
//  la release) : l'utilisateur peut découvrir la permission ici en premier,
//  sans avoir vu d'explication au préalable.
//

import AppKit
import SwiftUI

enum CapturePermissionToast {
    /// Cas (a) — permission jamais accordée (ou révoquée). Pas de capture
    /// tentée : le gate de `startOCRCapture()` a bloqué AVANT l'overlay.
    static func showMissing() {
        present(CaptureMissingPermissionToastView(onTap: {
            openScreenRecordingSettings()
            dismiss()
        }), autoDismissAfter: 6)
    }

    /// Cas (b) — permission accordée côté système mais pas encore effective
    /// pour ScreenCaptureKit (cache pris au lancement du process) : détecté
    /// après un échec de capture malgré un preflight positif.
    static func showNeedsRestart() {
        present(CaptureRestartPermissionToastView(onRestart: {
            relaunch()
        }), autoDismissAfter: 8)
    }

    // MARK: - Présentation (panel flottant partagé)

    private static var panel: NSPanel?
    /// Jeton d'identité pour l'auto-dismiss (garde façon `showConfirmation`
    /// de PopoverView : un panel plus récent ne doit pas être fermé par le
    /// timer d'un panel déjà remplacé).
    private static var currentToken = UUID()

    private static func present<V: View>(_ view: V, autoDismissAfter: TimeInterval) {
        dismiss()   // anti-stacking : un seul toast à la fois

        let token = UUID()
        currentToken = token

        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height - 90
        )

        let win = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false   // l'ombre vit dans la vue SwiftUI (ConfirmationToast-like)
        win.level = .floating
        win.contentView = hosting
        win.orderFrontRegardless()

        panel = win

        DispatchQueue.main.asyncAfter(deadline: .now() + autoDismissAfter) {
            guard currentToken == token else { return }
            dismiss()
        }
    }

    private static func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Relance propre via LaunchServices (préserve le statut `.accessory` /
    /// barre des menus) — préférée à `Process()` + `executableURL`.
    private static func relaunch() {
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

// MARK: - Vues (même famille visuelle que ConfirmationToast)

private struct CaptureMissingPermissionToastView: View {
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 22))
                .foregroundStyle(PolishTokens.selectionBackground)
            VStack(alignment: .leading, spacing: 2) {
                Text("Autorise l'enregistrement de l'écran")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Ouvre les Réglages pour extraire du texte à l'écran")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .toastCapsule()
        .contentShape(Capsule())
        .onTapGesture { onTap() }
    }
}

private struct CaptureRestartPermissionToastView: View {
    let onRestart: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Autorisation accordée")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Redémarre loucedé pour activer la capture")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Button(action: onRestart) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Redémarrer")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(PolishTokens.selectionBackground))
            }
            .buttonStyle(.plain)
        }
        .toastCapsule()
    }
}

/// Chrome commun capsule (calqué `ConfirmationToast` : matériau adaptatif,
/// pas de fond sombre en dur → light/dark natif).
private extension View {
    func toastCapsule() -> some View {
        self
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.gray.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 24, y: 6)
            .fixedSize()
    }
}
