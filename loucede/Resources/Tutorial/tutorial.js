/*
  tutorial.js — Tuto loucedé (Phase M.2.4)

  Navigation entre les 4 sections + contrat bridge JS↔Swift INTACT.

  Stratégie (A) — decisions #9 : le contrat Swift (noms des fonctions, handler
  `tutoBridge`, flag `window._tutoInjecting`) ne change PAS. Seules les CIBLES
  DOM deviennent relatives à la SECTION ACTIVE : tick / injectResult /
  refocusEdit opèrent sur `.tuto-section.active [data-edit]` (ou la coche de la
  section active). La sélection (`_lastSelection`/`_lastRange`) reste globale.

  Swift appelle : window.tuto.lastSelection() / tick(step) / injectResult(text)
  / refocusEdit(). Côté page → window.webkit.messageHandlers.tutoBridge.
*/

(function () {
  "use strict";

  // ─────────────────────────── Log instrumenté (🧪, retiré M.2.5) ───────────────────────────
  const logEl = document.getElementById("log");
  function log(dir, msg) {
    if (!logEl) return;
    const t = new Date().toISOString().substr(11, 12);
    logEl.textContent += "[" + t + "] " + dir + " " + msg + "\n";
    logEl.scrollTop = logEl.scrollHeight;
  }

  // ─────────────────────────── JS → Swift ───────────────────────────
  function send(payload) {
    try {
      window.webkit.messageHandlers.tutoBridge.postMessage(payload);
      log("JS->Swift", JSON.stringify(payload));
    } catch (e) {
      log("ERR", "bridge indisponible " + e);
    }
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
  const TOTAL = sections.length;

  function goToSection(index) {
    const target = sections.find((s) => Number(s.dataset.index) === index);
    if (!target) return;
    sections.forEach((s) => s.classList.toggle("active", s === target));
    document.body.dataset.section = String(index);
    if (progressEl) progressEl.textContent = "Étape " + index + " / " + TOTAL;
    log("nav", "section " + index);
    // Focus l'éditable de la nouvelle section (si présent).
    const edit = activeEdit();
    if (edit) edit.focus();
  }

  document.querySelectorAll(".tuto-next").forEach((btn) => {
    btn.addEventListener("click", () => {
      const current = Number(document.body.dataset.section) || 1;
      goToSection(Math.min(current + 1, TOTAL));
    });
  });

  // ─────────────────────────── API Swift → JS (window.tuto.*) ───────────────────────────
  window.tuto = {
    // M.2.3-fix BUG 2 — dernière sélection NON VIDE mémorisée (texte + Range),
    // globale (toutes sections). On ne lit pas la sélection « live » au ⌥&
    // (timing fragile : un contenteditable peut collapser avant l'éval async).
    _lastSelection: "",
    _lastRange: null,

    /// Lue par Swift (handleTutorialShortcut) à la place de getSelection live.
    lastSelection() {
      log("Swift->JS", "lastSelection() -> [" + this._lastSelection.length + "] " + JSON.stringify(this._lastSelection));
      return this._lastSelection;
    },

    /// Coche une sous-étape DANS LA SECTION ACTIVE (stratégie A). No-op gracieux
    /// si la sous-étape n'existe pas (ex. tick("ready") au load global).
    /// Passe la sous-étape suivante en `active`.
    tick(step) {
      const sec = activeSection();
      const li = sec ? sec.querySelector('[data-tick="' + step + '"]') : null;
      if (li) {
        li.dataset.state = "done";
        // Active la prochaine sous-étape encore "upcoming".
        let next = li.nextElementSibling;
        while (next && next.dataset.state !== "upcoming") next = next.nextElementSibling;
        if (next) next.dataset.state = "active";
      }
      log("Swift->JS", "tick(" + step + ")" + (li ? "" : " [no-op]"));
      return true;
    },

    /// Injecte le résultat IA dans l'éditable de la SECTION ACTIVE (remplace le
    /// paste système). Texte échappé côté Swift via JSON.
    injectResult(text) {
      const edit = activeEdit();
      if (!edit) { log("Swift->JS", "injectResult() [no edit]"); return false; }
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
      log("Swift->JS", "injectResult(" + JSON.stringify(text).slice(0, 60) + ")");
      return true;
    },

    /// Restaure le focus de l'éditable actif après fermeture du popover.
    refocusEdit() {
      const edit = activeEdit();
      if (!edit) { log("Swift->JS", "refocusEdit() [no edit]"); return false; }
      edit.focus();
      log("Swift->JS", "refocusEdit()");
      return document.activeElement === edit;
    }
  };

  // ─────────────────────────── JS → Swift : signaux ───────────────────────────
  window.addEventListener("load", () => send({ type: "ready" }));

  // Sélection globale (toutes sections) → mémorise la dernière non vide.
  document.addEventListener("selectionchange", () => {
    const sel = document.getSelection();
    const s = String(sel);
    if (s.length) {
      window.tuto._lastSelection = s;
      if (sel.rangeCount) window.tuto._lastRange = sel.getRangeAt(0).cloneRange();
      send({ type: "selection", text: s, len: s.length });
    }
  });

  // M.2.3 — pas de listener JS ⌥& : le hotkey Carbon de loucedé consomme la
  // touche au niveau système (cf. TutorialWindowController.handleTutorialShortcut).

  // Garde : bloque la saisie clavier ordinaire dans TOUS les contenteditable
  // [data-edit], sauf paste / injection programmatique (flag _tutoInjecting).
  document.querySelectorAll("[data-edit]").forEach((edit) => {
    edit.addEventListener("beforeinput", (e) => {
      const allowed = window._tutoInjecting
        || e.inputType === "insertFromPaste"
        || e.inputType === "insertReplacementText";
      if (!allowed) { e.preventDefault(); send({ type: "blockedInput", inputType: e.inputType }); }
    });
  });
})();
