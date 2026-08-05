//
//  ScreenCaptureService.swift
//  loucede
//
//  O.1.d (Snapshot OCR) — capture d'une zone de l'écran via ScreenCaptureKit
//  (SCScreenshotManager, macOS 14+). 100 % in-process, aucun fichier temporaire
//  en production (décision A, cf. details/snapshot-ocr.md).
//
//  MAILLON CRITIQUE — conversion de coordonnées : l'overlay (O.1.c) renvoie la
//  zone en coordonnées GLOBALES AppKit (origine BAS-gauche, écran actif) ; SCK
//  attend un `sourceRect` en coordonnées LOCALES au display, origine HAUT-gauche,
//  en points. Une conversion fausse = capture décalée/inversée verticalement.
//

import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ScreenCaptureService {
    enum CaptureError: Error { case noDisplay }

    /// O.4 — lecture immédiate de l'état TCC (source de vérité système).
    /// Ne reflète PAS forcément la capacité réelle de SCK à capturer : un
    /// octroi frais n'est pris en compte par SCK qu'au redémarrage du process
    /// (cf. `beginCaptureCycle` catch dans `loucedeApp.swift`).
    static func hasScreenRecordingAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Déclenche le prompt système natif (no-op silencieux si déjà accordée
    /// ou déjà refusée définitivement).
    static func requestScreenRecordingAccess() {
        CGRequestScreenCaptureAccess()
    }

    /// Capture la zone `globalRect` (coords GLOBALES AppKit, origine bas-gauche)
    /// de l'écran `screen`. Renvoie un `CGImage` en résolution native (Retina).
    static func captureImage(globalRect: CGRect, screen: NSScreen) async throws -> CGImage {
        // 1. NSScreen → SCDisplay (via le CGDirectDisplayID).
        guard let screenNumber = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else {
            throw CaptureError.noDisplay
        }
        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        )
        guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplay
        }

        // 2. AppKit global (bas-gauche) → display-local haut-gauche (points).
        //    x : décalage par rapport au bord gauche de l'écran.
        //    y : flip vertical — le HAUT de la zone (globalRect.maxY en AppKit)
        //        mesuré depuis le HAUT de l'écran (screen.frame.maxY).
        let sourceRect = CGRect(
            x: globalRect.minX - screen.frame.minX,
            y: screen.frame.maxY - globalRect.maxY,
            width: globalRect.width,
            height: globalRect.height
        )

        // 3. Config : sourceRect en points, sortie en pixels natifs (Retina)
        //    pour une qualité OCR maximale.
        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = Int((globalRect.width * scale).rounded())
        config.height = Int((globalRect.height * scale).rounded())
        config.showsCursor = false
        config.scalesToFit = false

        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config
        )
    }
}
