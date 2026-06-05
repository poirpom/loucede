/*
  tutorial.js — Tuto loucedé (Phases M.2.4 + M.2.5)

  Navigation entre les 4 sections + contrat bridge JS↔Swift INTACT.

  Stratégie (A) — decisions #9 : le contrat Swift (noms des fonctions, handler
  `tutoBridge`, flag `window._tutoInjecting`) ne change PAS. Seules les CIBLES
  DOM deviennent relatives à la SECTION ACTIVE : tick / injectResult /
  refocusEdit opèrent sur `.tuto-section.active [data-edit]` (ou la coche de la
  section active). La sélection (`_lastSelection`/`_lastRange`) reste globale.

  Swift appelle : window.tuto.lastSelection() / tick(step) / injectResult(text)
  / refocusEdit(). La page poste vers Swift via tutoBridge : { type:"ready" } au
  chargement, { type:"close" } au clic sur « Fermer » (écran final).

  M.2.5 : instrumentation (#log / log()) retirée ; bouton Fermer câblé.
*/

(function () {
  "use strict";

  // ─────────────────────────── JS → Swift ───────────────────────────
  function send(payload) {
    try { window.webkit.messageHandlers.tutoBridge.postMessage(payload); }
    catch (e) { /* bridge indisponible (page ouverte hors app) — no-op */ }
  }

  // ─────────────────────────── Résolution de la section active ───────────────────────────
  function activeSection() { return document.querySelector(".tuto-section.active"); }
  function activeEdit() {
    const sec = activeSection();
    return sec ? sec.querySelector("[data-edit]") : null;
  }

  // ─────────────────────────── Navigation ───────────────────────────
  const sections = Array.from(document.querySelectorAll(".tuto-section"));
  const progressEl = document.getElementById("progress");
  const TOTAL = sections.length;                                              // 4 — navigation
  const STEPS = document.querySelectorAll(".tuto-section.interactive").length; // 3 — écrans d'apprentissage

  function goToSection(index) {
    const target = sections.find((s) => Number(s.dataset.index) === index);
    if (!target) return;
    sections.forEach((s) => s.classList.toggle("active", s === target));
    document.body.dataset.section = String(index);
    // Indicateur : « Étape X / 3 » sur les écrans interactifs, masqué sur l'écran final.
    if (progressEl) {
      const isFinal = target.classList.contains("final");
      progressEl.style.display = isFinal ? "none" : "";
      if (!isFinal) progressEl.textContent = "Étape " + index + " / " + STEPS;
    }
    // Focus l'éditable de la nouvelle section (si présent — seule la section 2 en a).
    const edit = activeEdit();
    if (edit) edit.focus();
  }

  document.querySelectorAll(".tuto-next").forEach((btn) => {
    btn.addEventListener("click", () => {
      const current = Number(document.body.dataset.section) || 1;
      goToSection(Math.min(current + 1, TOTAL));
    });
  });

  // Bouton « Fermer » (écran final) → ferme la fenêtre via le bridge
  // (Swift : case "close" → window.close() → cleanup windowWillClose).
  const closeBtn = document.querySelector(".tuto-close");
  if (closeBtn) closeBtn.addEventListener("click", () => send({ type: "close" }));

  // ─────────────────────────── API Swift → JS (window.tuto.*) ───────────────────────────
  window.tuto = {
    // M.2.3-fix BUG 2 — dernière sélection NON VIDE mémorisée (texte + Range),
    // globale (toutes sections). On ne lit pas la sélection « live » au ⌥&
    // (timing fragile : un contenteditable peut collapser avant l'éval async).
    _lastSelection: "",
    _lastRange: null,

    /// Lue par Swift (handleTutorialShortcut) à la place de getSelection live.
    lastSelection() { return this._lastSelection; },

    /// Coche un milestone DANS LA SECTION ACTIVE (stratégie A). No-op gracieux
    /// si le milestone n'existe pas (ex. tick("magic") sur l'écran 3).
    /// Passe le milestone suivant en `active` (saute les lignes info, qui n'ont
    /// pas de data-state).
    tick(step) {
      const sec = activeSection();
      const li = sec ? sec.querySelector('[data-tick="' + step + '"]') : null;
      // Garde anti-réavance : ne rejoue pas si déjà coché (sinon un re-tick
      // ferait avancer indûment le milestone suivant).
      if (li && li.dataset.state !== "done") {
        li.dataset.state = "done";
        // Active le prochain milestone encore "upcoming".
        let next = li.nextElementSibling;
        while (next && next.dataset.state !== "upcoming") next = next.nextElementSibling;
        if (next) next.dataset.state = "active";
      }
      return true;
    },

    /// Injecte le résultat IA dans l'éditable de la SECTION ACTIVE (remplace le
    /// paste système). Texte échappé côté Swift via JSON. No-op gracieux sur les
    /// sections sans contenteditable (1 et 3).
    injectResult(text) {
      const edit = activeEdit();
      if (!edit) return false;
      edit.focus();
      // M.2.3-fix BUG 1 (bonus) — restaure la Range d'origine si elle est dans
      // CET éditable, pour REMPLACER la sélection (sinon insert au caret).
      const r = this._lastRange;
      if (r && edit.contains(r.commonAncestorContainer)) {
        const sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(r);
      }
      // M.2.3-fix BUG 1 — flag d'injection : la garde beforeinput laisse passer
      // execCommand('insertText') le temps de l'écriture programmatique.
      window._tutoInjecting = true;
      document.execCommand("insertText", false, text);
      window._tutoInjecting = false;
      return true;
    },

    /// Restaure le focus de l'éditable actif après fermeture du popover.
    refocusEdit() {
      const edit = activeEdit();
      if (!edit) return false;
      edit.focus();
      return document.activeElement === edit;
    }
  };

  // ─────────────────────────── JS → Swift : handshake ───────────────────────────
  window.addEventListener("load", () => send({ type: "ready" }));

  // Sélection globale (toutes sections) → mémorise la dernière non vide ET coche
  // le milestone « selection » en interne (Swift n'est pas notifié des
  // sélections). Logique JS pure — le contrat Swift reste intact.
  document.addEventListener("selectionchange", () => {
    const sel = document.getSelection();
    const s = String(sel);
    if (s.length) {
      window.tuto._lastSelection = s;
      if (sel.rangeCount) window.tuto._lastRange = sel.getRangeAt(0).cloneRange();
      const sec = activeSection();
      const stage = sec ? sec.querySelector(".tuto-stage") : null;
      if (stage && sel.anchorNode && stage.contains(sel.anchorNode)) {
        window.tuto.tick("selection");
      }
    }
  });

  // M.2.3 — pas de listener JS ⌥& : le hotkey Carbon de loucedé consomme la
  // touche au niveau système (cf. TutorialWindowController.handleTutorialShortcut).

  // Garde : bloque la saisie clavier ordinaire dans le(s) contenteditable
  // [data-edit] (section 2), sauf paste / injection programmatique (_tutoInjecting).
  document.querySelectorAll("[data-edit]").forEach((edit) => {
    edit.addEventListener("beforeinput", (e) => {
      const allowed = window._tutoInjecting
        || e.inputType === "insertFromPaste"
        || e.inputType === "insertReplacementText";
      if (!allowed) e.preventDefault();
    });
  });
})();
