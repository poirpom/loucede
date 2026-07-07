//
//  OCRService.swift
//  loucede
//
//  O.1.b (Snapshot OCR) — reconnaissance de texte 100 % LOCALE via le
//  framework Vision. Aucune dépendance externe, aucun réseau : c'est le
//  différenciateur privacy du chantier (cf. details/snapshot-ocr.md).
//
//  API pure `CGImage → String` : le CGImage vient de la capture d'écran
//  (ScreenCaptureKit `SCScreenshotManager`, câblé en O.1.d). Langue
//  auto-détectée par Vision (pas de configuration côté loucedé).
//

import Foundation
import Vision
import CoreGraphics

enum OCRService {
    /// Reconnaît le texte présent dans `image`, en local via Vision.
    ///
    /// - Niveau `.accurate` (qualité > vitesse — l'OCR est ponctuel, pas
    ///   temps réel) + correction linguistique activée.
    /// - `automaticallyDetectsLanguage` : Vision choisit la langue seul
    ///   (décision produit « langue auto », macOS 13+).
    /// - Les observations sont ordonnées puis jointes par sauts de ligne ;
    ///   on ne garde que le meilleur candidat de chaque ligne.
    ///
    /// Renvoie une chaîne vide si rien n'est reconnu ou en cas d'échec
    /// (l'appelant traite ce cas comme « aucun texte détecté » → état 3 de
    /// la fenêtre en O.2.c).
    static func recognizeText(in image: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            // `perform` est synchrone et potentiellement coûteux → hors main.
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true

                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                    let observations = request.results ?? []
                    let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                    let text = lines.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }
}
