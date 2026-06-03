//
//  ModelPricing.swift
//  loucede
//
//  Phase L.4 — grille de tarifs IA (input/output par 1M tokens, en EUR) +
//  helper de calcul du coût estimé. Données de pricing pures, sans
//  dépendance UI. Consommée par la carte « Coût estimé » (L.5).
//

import Foundation

struct ModelPrice {
    let inputPer1M_EUR: Double   // Coût input par 1M tokens, en EUR
    let outputPer1M_EUR: Double  // Coût output par 1M tokens, en EUR
}

/// Tarifs IA — vérifiés le 2026-06-03 (structure 3 tiers — Phase O)
/// Source USD : pages officielles OpenAI/Anthropic/Mistral + revues comparatives 2026
/// Conversion USD→EUR au taux 0.86 (EUR/USD = 1.1619 au 2026-06-03)
/// À revérifier à chaque release V1.x ou à l'ajout de nouveaux modèles.
///
/// Structure (Phase O) : 9 modèles « câblés V1.x » sont exposés dans
/// `AIModel.allModels` (3 tiers × 3 providers). La grille conserve en plus :
///   • les entrées « legacy » (modèles retirés du Picker mais préservés) ;
///   • les « 🆕 candidats » (prochains cycles Phase O).
/// Ces entrées hors-catalogue restent ici comme filet anti-drift : si une API
/// renvoyait jamais l'un de ces modelId, le coût reste estimable.
/// Note : `claude-opus-4-8` — tarif non confirmé publiquement à la pose, aligné
/// sur le tier Opus courant (à revérifier au prochain refresh).
let modelPricing: [String: ModelPrice] = [
    // === OpenAI — câblés V1.x (3 tiers : 🚀 rapide / ⚖️ intermédiaire / 🧠 puissant) ===
    "gpt-4o-mini":     ModelPrice(inputPer1M_EUR: 0.13,  outputPer1M_EUR: 0.52),
    "gpt-4o":          ModelPrice(inputPer1M_EUR: 2.15,  outputPer1M_EUR: 8.60),
    "gpt-4.1":         ModelPrice(inputPer1M_EUR: 1.72,  outputPer1M_EUR: 6.88),
    // === OpenAI — legacy (retirés du Picker, conservés — filet anti-drift) ===
    "gpt-4-turbo":     ModelPrice(inputPer1M_EUR: 8.60,  outputPer1M_EUR: 25.80),
    "o1-mini":         ModelPrice(inputPer1M_EUR: 2.58,  outputPer1M_EUR: 10.32),
    // === OpenAI — 🆕 candidats prochains cycles Phase O ===
    "gpt-5":           ModelPrice(inputPer1M_EUR: 1.08,  outputPer1M_EUR: 8.60),
    "gpt-5.4":         ModelPrice(inputPer1M_EUR: 2.15,  outputPer1M_EUR: 12.90),
    "gpt-5.5":         ModelPrice(inputPer1M_EUR: 4.30,  outputPer1M_EUR: 25.80),
    "gpt-4.1-mini":    ModelPrice(inputPer1M_EUR: 0.34,  outputPer1M_EUR: 1.38),
    "gpt-4.1-nano":    ModelPrice(inputPer1M_EUR: 0.09,  outputPer1M_EUR: 0.34),
    "o3":              ModelPrice(inputPer1M_EUR: 1.72,  outputPer1M_EUR: 6.88),
    "o3-mini":         ModelPrice(inputPer1M_EUR: 0.95,  outputPer1M_EUR: 3.78),
    "o1":              ModelPrice(inputPer1M_EUR: 12.90, outputPer1M_EUR: 51.60),

    // === Anthropic — câblés V1.x (3 tiers : 🚀 rapide / ⚖️ intermédiaire / 🧠 puissant) ===
    "claude-haiku-4-5":           ModelPrice(inputPer1M_EUR: 0.86, outputPer1M_EUR: 4.30),
    "claude-sonnet-4-6":          ModelPrice(inputPer1M_EUR: 2.58, outputPer1M_EUR: 12.90),
    "claude-opus-4-8":            ModelPrice(inputPer1M_EUR: 4.30, outputPer1M_EUR: 21.50),
    // === Anthropic — legacy (retirés du Picker, conservés — filet anti-drift) ===
    // claude-haiku-4-5-20251001 : daté = cible du fallback A_O.2 si l'alias court échoue au runtime.
    "claude-haiku-4-5-20251001":  ModelPrice(inputPer1M_EUR: 0.86, outputPer1M_EUR: 4.30),
    "claude-sonnet-4-20250514":   ModelPrice(inputPer1M_EUR: 2.58, outputPer1M_EUR: 12.90),
    "claude-opus-4-5-20251101":   ModelPrice(inputPer1M_EUR: 4.30, outputPer1M_EUR: 21.50),
    // === Anthropic — 🆕 candidats prochains cycles Phase O ===
    "claude-sonnet-4-5-20250929": ModelPrice(inputPer1M_EUR: 2.58, outputPer1M_EUR: 12.90),
    "claude-opus-4-6":            ModelPrice(inputPer1M_EUR: 4.30, outputPer1M_EUR: 21.50),
    "claude-opus-4-7":            ModelPrice(inputPer1M_EUR: 4.30, outputPer1M_EUR: 21.50),
    "claude-haiku-3-5":           ModelPrice(inputPer1M_EUR: 0.69, outputPer1M_EUR: 3.44),

    // === Mistral — câblés V1.x (3 tiers : 🚀 rapide / ⚖️ intermédiaire / 🧠 puissant) ===
    "mistral-small-latest":   ModelPrice(inputPer1M_EUR: 0.09, outputPer1M_EUR: 0.26),
    "mistral-medium-latest":  ModelPrice(inputPer1M_EUR: 0.34, outputPer1M_EUR: 1.72),
    "mistral-large-latest":   ModelPrice(inputPer1M_EUR: 1.72, outputPer1M_EUR: 5.16),
    // === Mistral — legacy (retirés du Picker, conservés — filet anti-drift) ===
    "codestral-latest":       ModelPrice(inputPer1M_EUR: 0.26, outputPer1M_EUR: 0.77),
    "ministral-8b-latest":    ModelPrice(inputPer1M_EUR: 0.09, outputPer1M_EUR: 0.09),
    "ministral-3b-latest":    ModelPrice(inputPer1M_EUR: 0.03, outputPer1M_EUR: 0.03),
    // === Mistral — 🆕 candidats prochains cycles Phase O ===
    "mistral-small-3.2":      ModelPrice(inputPer1M_EUR: 0.06, outputPer1M_EUR: 0.17),
    "devstral-medium":        ModelPrice(inputPer1M_EUR: 0.34, outputPer1M_EUR: 1.72),
    "devstral-small-1.1":     ModelPrice(inputPer1M_EUR: 0.06, outputPer1M_EUR: 0.24),
]

/// Coût estimé en EUR pour un volume de tokens sur un modèle donné.
/// Retourne `nil` si le modelId est absent de la grille (coût indéterminable
/// → la vue affiche `--,-- €` pour ce modèle) — filet anti-drift.
func estimatedCostEUR(modelId: String, inputTokens: Int, outputTokens: Int) -> Double? {
    guard let price = modelPricing[modelId] else { return nil }
    let inputCost = (Double(inputTokens) / 1_000_000.0) * price.inputPer1M_EUR
    let outputCost = (Double(outputTokens) / 1_000_000.0) * price.outputPer1M_EUR
    return inputCost + outputCost
}
